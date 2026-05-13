import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CoreMedia

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

    private var stream: SCStream?

    // Writer state. Written from @MainActor before/after recording;
    // read from SCStreamOutput callbacks during recording.
    // sessionLock guards the one-time startSession call.
    nonisolated(unsafe) private var assetWriter: AVAssetWriter?
    nonisolated(unsafe) private var videoInput: AVAssetWriterInput?
    nonisolated(unsafe) private var audioInput: AVAssetWriterInput?
    nonisolated(unsafe) private var sessionStarted = false
    private let sessionLock = NSLock()

    // MARK: - Available content

    func loadAvailableContent() async {
        do {
            let content = try await SCShareableContent.current
            availableDisplays = content.displays
            availableWindows = content.windows.filter {
                $0.isOnScreen &&
                !($0.title?.isEmpty ?? true) &&
                $0.owningApplication != nil
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

    func saveScreenshot(_ image: CGImage, to url: URL, settings: ExportSettings) throws {
        let props: CFDictionary?
        if settings.imageFormat == .jpeg {
            props = [kCGImageDestinationLossyCompressionQuality: settings.jpegQuality.value] as CFDictionary
        } else {
            props = nil
        }
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, settings.imageFormat.utType, 1, nil)
        else { throw CaptureError.saveFailed }
        CGImageDestinationAddImage(dest, image, props)
        guard CGImageDestinationFinalize(dest) else { throw CaptureError.saveFailed }
    }

    // MARK: - Recording

    func startRecording(display: SCDisplay?, window: SCWindow?, outputURL: URL,
                        settings: ExportSettings) async throws {
        let filter = makeFilter(display: display, window: window)

        // Use the export setting dimensions, or fall back to native display size
        let (outW, outH): (Int, Int)
        if let fixed = settings.outputDimensions {
            outW = fixed.width
            outH = fixed.height
        } else {
            (outW, outH) = captureSize(display: display, window: window)
        }

        let streamConfig = SCStreamConfiguration()
        streamConfig.capturesAudio = true
        streamConfig.sampleRate    = 48000
        streamConfig.channelCount  = 2
        streamConfig.width         = outW
        streamConfig.height        = outH
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: settings.frameTimescale)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        let writer = try AVAssetWriter(url: outputURL, fileType: settings.avFileType)

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: settings.avVideoCodecType,
            AVVideoWidthKey: outW,
            AVVideoHeightKey: outH,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrateFor(outW, outH)
            ]
        ])
        vInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(vInput) else { throw CaptureError.writerSetupFailed("Cannot add video input") }
        writer.add(vInput)

        // kAudioFormatMPEG4AAC must be wrapped in Int() to bridge to NSNumber correctly
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ])
        aInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(aInput) else { throw CaptureError.writerSetupFailed("Cannot add audio input") }
        writer.add(aInput)

        assetWriter    = writer
        videoInput     = vInput
        audioInput     = aInput
        sessionStarted = false

        guard writer.startWriting() else {
            throw writer.error ?? CaptureError.writerSetupFailed("startWriting failed")
        }

        let newStream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        try newStream.addStreamOutput(self, type: .audio,  sampleHandlerQueue: .global(qos: .userInteractive))
        try await newStream.startCapture()
        stream = newStream

        onRecordingStarted?()
    }

    func stopRecording() async throws {
        guard let s = stream else { return }
        stream = nil
        // stopCapture() drains all pending SCStreamOutput callbacks before returning
        try await s.stopCapture()

        guard let writer = assetWriter else { return }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            let err = writer.error?.localizedDescription ?? "Unknown error"
            assetWriter = nil; videoInput = nil; audioInput = nil; sessionStarted = false
            throw CaptureError.writerSetupFailed("finishWriting failed: \(err)")
        }

        assetWriter    = nil
        videoInput     = nil
        audioInput     = nil
        sessionStarted = false

        onRecordingFinished?()
    }

    // MARK: - Dimension helpers

    /// Returns actual pixel dimensions matching what SCStream will output.
    /// Both SCStreamConfiguration and AVAssetWriterInput MUST use these same values.
    private func captureSize(display: SCDisplay?, window: SCWindow?) -> (Int, Int) {
        if let d = display {
            return pixelSize(for: d)
        }
        if let w = window {
            // SCWindow.frame is in screen points; assume 2× Retina scaling.
            // Round to even numbers required by H.264.
            let pw = (Int(w.frame.width)  * 2 / 2) * 2
            let ph = (Int(w.frame.height) * 2 / 2) * 2
            return (max(pw, 2), max(ph, 2))
        }
        return (1920, 1080)
    }

    private func pixelSize(for display: SCDisplay) -> (Int, Int) {
        if let mode = CGDisplayCopyDisplayMode(display.displayID) {
            let w = (mode.pixelWidth  / 2) * 2
            let h = (mode.pixelHeight / 2) * 2
            if w > 0 && h > 0 { return (w, h) }
        }
        // Fallback: SCDisplay.width/height are logical points; multiply by 2 for Retina
        return ((display.width * 2 / 2) * 2, (display.height * 2 / 2) * 2)
    }

    // MARK: - Filter

    /// Scale bitrate with resolution so quality stays consistent across presets.
    private func bitrateFor(_ w: Int, _ h: Int) -> Int {
        let pixels = w * h
        let base   = 1920 * 1080   // 1080p baseline
        let bps    = 8_000_000     // 8 Mbps at 1080p
        return max(2_000_000, Int(Double(bps) * Double(pixels) / Double(base)))
    }

    private func makeFilter(display: SCDisplay?, window: SCWindow?) -> SCContentFilter {
        if let w = window { return SCContentFilter(desktopIndependentWindow: w) }
        if let d = display { return SCContentFilter(display: d, excludingWindows: []) }
        return SCContentFilter(display: availableDisplays[0], excludingWindows: [])
    }

    // MARK: - Errors

    enum CaptureError: LocalizedError {
        case noDisplayAvailable
        case saveFailed
        case writerSetupFailed(String)

        var errorDescription: String? {
            switch self {
            case .noDisplayAvailable:       "No display available for capture."
            case .saveFailed:               "Failed to save the captured image."
            case .writerSetupFailed(let m): "Recording setup failed: \(m)"
            }
        }
    }
}

// MARK: - SCStreamOutput

extension ScreenCaptureManager: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let writer = assetWriter,
              writer.status == .writing
        else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Start the writer session exactly once, protected against concurrent
        // video + audio callbacks arriving simultaneously.
        sessionLock.withLock {
            if !sessionStarted {
                writer.startSession(atSourceTime: pts)
                sessionStarted = true
            }
        }

        switch type {
        case .screen:
            if let input = videoInput, input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }
        case .audio:
            if let input = audioInput, input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }
        @unknown default:
            break
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
