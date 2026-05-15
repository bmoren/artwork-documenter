import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreGraphics
import CoreMedia
import ImageIO
import UniformTypeIdentifiers

@Observable
@MainActor
final class ScreenCaptureManager: NSObject {

    var availableDisplays: [SCDisplay] = []
    var availableWindows: [SCWindow] = []
    var permissionGranted: Bool = false
    var permissionDenied: Bool = false

    var onRecordingStarted: (() -> Void)?
    var onRecordingFinished: (() -> Void)?
    var onError: ((String) -> Void)?

    /// URL of the recorded file (always .mov).
    private(set) var recordedFileURL: URL?

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?

    // Continuation resumed by SCRecordingOutputDelegate when the file is finalised.
    private var finishContinuation: CheckedContinuation<Void, Error>?

    // MARK: - Available content

    func loadAvailableContent() async {
        do {
            let content = try await SCShareableContent.current
            availableDisplays = content.displays
            let selfBundleID = Bundle.main.bundleIdentifier ?? ""
            availableWindows = content.windows.filter {
                guard let app = $0.owningApplication else { return false }
                return $0.isOnScreen
                    && !($0.title?.isEmpty ?? true)
                    && $0.windowLayer == 0
                    && app.bundleIdentifier != selfBundleID
            }
            permissionGranted = true
            permissionDenied = false
        } catch {
            permissionGranted = false
            if (error as NSError).code == -3801 { permissionDenied = true }
        }
    }

    // MARK: - Screenshots

    func captureScreenshot(display: SCDisplay?, window: SCWindow?) async throws -> CGImage {
        let filter = makeFilter(display: display, window: window)
        let config = SCStreamConfiguration()
        if let d = display {
            let (w, h) = pixelSize(for: d)
            config.width  = w
            config.height = h
            config.scalesToFit = true
        } else if let w = window {
            // Set pixel dimensions from the window frame so the capture is
            // cropped to the window bounds without shadow padding.
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            config.width  = evenPixels(w.frame.width  * scale)
            config.height = evenPixels(w.frame.height * scale)
        }
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    func saveScreenshot(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CaptureError.saveFailed }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CaptureError.saveFailed }
    }

    // MARK: - Recording

    func startRecording(display: SCDisplay?, window: SCWindow?, outputURL: URL,
                        settings: ExportSettings) async throws {
        let filter = makeFilter(display: display, window: window)

        let streamConfig = SCStreamConfiguration()
        streamConfig.capturesAudio = true
        streamConfig.sampleRate    = 48000
        streamConfig.channelCount  = 2
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: settings.frameTimescale)

        // Pin stream dimensions so SCKit doesn't default to an arbitrary size.
        // Window: use window's pixel bounds to avoid black padding.
        // Display: scale to the target resolution (native = full pixel size).
        if let w = window {
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            streamConfig.width  = evenPixels(w.frame.width  * scale)
            streamConfig.height = evenPixels(w.frame.height * scale)
        } else if let d = display {
            let (w, h) = targetSize(for: d, resolution: settings.videoResolution)
            streamConfig.width  = w
            streamConfig.height = h
        }

        let movURL = outputURL.deletingPathExtension().appendingPathExtension("mov")
        if FileManager.default.fileExists(atPath: movURL.path) {
            try FileManager.default.removeItem(at: movURL)
        }
        recordedFileURL = movURL

        let recConfig = SCRecordingOutputConfiguration()
        recConfig.outputURL       = movURL
        recConfig.outputFileType  = .mov
        recConfig.videoCodecType  = settings.avVideoCodecType

        let newStream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        let recOut    = SCRecordingOutput(configuration: recConfig, delegate: self)
        try newStream.addRecordingOutput(recOut)
        try await newStream.startCapture()

        stream          = newStream
        recordingOutput = recOut

        onRecordingStarted?()
    }

    func stopRecording() async throws {
        guard let s = stream else { return }
        stream = nil

        // SCRecordingOutput finalises the file asynchronously after stopCapture().
        // We wait for the delegate signal before proceeding so the file is ready
        // for transcode / playback.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            finishContinuation = cont
            Task {
                do {
                    try await s.stopCapture()
                    // If the delegate fires before stopCapture() returns we're already
                    // done; if it fires after, we just wait. If stopCapture() itself
                    // throws, resume the continuation with that error.
                } catch {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let c = finishContinuation
                        finishContinuation = nil
                        c?.resume(throwing: error)
                    }
                }
            }
        }

        recordingOutput = nil
        onRecordingFinished?()
    }

    // MARK: - Dimension helpers

    // Video encoders require even dimensions; round up by 1 if odd.
    private func evenPixels(_ value: Double) -> Int {
        let n = Int(value)
        return n % 2 == 0 ? n : n + 1
    }

    private func pixelSize(for display: SCDisplay) -> (Int, Int) {
        if let mode = CGDisplayCopyDisplayMode(display.displayID) {
            let w = mode.pixelWidth
            let h = mode.pixelHeight
            if w > 0 && h > 0 { return (w, h) }
        }
        return (display.width * 2, display.height * 2)
    }

    // Returns the pixel dimensions the stream should capture at for a display,
    // capped to the target resolution while preserving the display's aspect ratio.
    // For .native, returns the display's full pixel size.
    private func targetSize(for display: SCDisplay,
                            resolution: ExportSettings.VideoResolution) -> (Int, Int) {
        let (nW, nH) = pixelSize(for: display)
        guard resolution != .native else { return (nW, nH) }
        let targetH: Double
        switch resolution {
        case .p1080:  targetH = 1080
        case .native: targetH = Double(nH) // unreachable
        }
        guard Double(nH) > targetH else { return (nW, nH) } // already at or below target
        let scale = targetH / Double(nH)
        return (evenPixels(Double(nW) * scale), evenPixels(targetH))
    }

    // MARK: - Filter

    private func makeFilter(display: SCDisplay?, window: SCWindow?) -> SCContentFilter {
        if let w = window { return SCContentFilter(desktopIndependentWindow: w) }
        if let d = display { return SCContentFilter(display: d, excludingWindows: []) }
        return SCContentFilter(display: availableDisplays[0], excludingWindows: [])
    }

    // MARK: - Errors

    enum CaptureError: LocalizedError {
        case noDisplayAvailable
        case saveFailed
        case recordingFailed(String)

        var errorDescription: String? {
            switch self {
            case .noDisplayAvailable:      "No display available for capture."
            case .saveFailed:              "Failed to save the captured image."
            case .recordingFailed(let m):  "Recording failed: \(m)"
            }
        }
    }
}

// MARK: - SCRecordingOutputDelegate

extension ScreenCaptureManager: SCRecordingOutputDelegate {

    /// Called when SCRecordingOutput has finished writing the file.
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let c = finishContinuation
            finishContinuation = nil
            c?.resume()
        }
    }

    /// Called when SCRecordingOutput encounters an error.
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput,
                                     didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let c = finishContinuation
            finishContinuation = nil
            if let c {
                c.resume(throwing: error)
            } else {
                onError?(error.localizedDescription)
            }
        }
    }
}

// MARK: - SCStreamDelegate

extension ScreenCaptureManager: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.onError?(error.localizedDescription)
        }
    }
}
