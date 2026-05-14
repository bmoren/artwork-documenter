import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreGraphics
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
        }
        config.scalesToFit = true
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

    // MARK: - Dimension helpers (screenshots only)

    private func pixelSize(for display: SCDisplay) -> (Int, Int) {
        if let mode = CGDisplayCopyDisplayMode(display.displayID) {
            let w = mode.pixelWidth
            let h = mode.pixelHeight
            if w > 0 && h > 0 { return (w, h) }
        }
        return (display.width * 2, display.height * 2)
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
