import Foundation
@preconcurrency import AVFoundation
import CoreMedia

enum InsertPosition {
    case start
    case end
    case timestamp(Double)
}

@Observable
@MainActor
final class VideoMergeManager {

    var isMerging: Bool = false
    var mergeProgress: Double = 0

    func merge(mainURL: URL, clipURL: URL, position: InsertPosition,
               settings: ExportSettings) async throws {
        isMerging = true
        mergeProgress = 0
        defer { isMerging = false }

        let mainAsset = AVURLAsset(url: mainURL)
        let clipAsset = AVURLAsset(url: clipURL)

        let mainDuration = try await mainAsset.load(.duration)
        let clipDuration  = try await clipAsset.load(.duration)

        let insertAt: CMTime
        switch position {
        case .start:     insertAt = .zero
        case .end:       insertAt = mainDuration
        case .timestamp(let seconds):
            let clamped = min(max(seconds, 0), mainDuration.seconds)
            insertAt = CMTime(seconds: clamped, preferredTimescale: 600)
        }

        // Load source tracks
        let mainVideoTracks = try await mainAsset.loadTracks(withMediaType: .video)
        let clipVideoTracks = try await clipAsset.loadTracks(withMediaType: .video)
        let mainAudioTracks = try await mainAsset.loadTracks(withMediaType: .audio)
        let clipAudioTracks = try await clipAsset.loadTracks(withMediaType: .audio)

        let mainVideoTrack = mainVideoTracks.first
        let clipVideoTrack = clipVideoTracks.first

        // Determine render size from the main video's effective (post-transform) dimensions
        let renderSize: CGSize
        if let mv = mainVideoTrack {
            let natural   = try await mv.load(.naturalSize)
            let preferred = try await mv.load(.preferredTransform)
            let r = CGRect(origin: .zero, size: natural).applying(preferred)
            renderSize = CGSize(width: r.width.magnitude, height: r.height.magnitude)
        } else {
            renderSize = CGSize(width: 1920, height: 1080)
        }

        let mainTransform = (try? await mainVideoTrack?.load(.preferredTransform)) ?? .identity

        // Build the composition with explicit, separately-managed tracks so we know
        // exactly which track carries the clip at which time range.
        let composition = AVMutableComposition()

        // --- Video tracks ---
        let compMainVideo = composition.addMutableTrack(withMediaType: .video,
                                                        preferredTrackID: kCMPersistentTrackID_Invalid)!
        let compClipVideo = composition.addMutableTrack(withMediaType: .video,
                                                        preferredTrackID: kCMPersistentTrackID_Invalid)!

        if let mv = mainVideoTrack {
            if insertAt > .zero {
                try compMainVideo.insertTimeRange(
                    CMTimeRange(start: .zero, duration: insertAt), of: mv, at: .zero)
            }
            if insertAt < mainDuration {
                try compMainVideo.insertTimeRange(
                    CMTimeRange(start: insertAt, duration: mainDuration - insertAt),
                    of: mv, at: insertAt + clipDuration)
            }
        }
        if let cv = clipVideoTrack {
            try compClipVideo.insertTimeRange(
                CMTimeRange(start: .zero, duration: clipDuration), of: cv, at: insertAt)
        }

        // --- Audio tracks ---
        for at in mainAudioTracks {
            let compAudio = composition.addMutableTrack(withMediaType: .audio,
                                                        preferredTrackID: kCMPersistentTrackID_Invalid)!
            if insertAt > .zero {
                try? compAudio.insertTimeRange(
                    CMTimeRange(start: .zero, duration: insertAt), of: at, at: .zero)
            }
            if insertAt < mainDuration {
                try? compAudio.insertTimeRange(
                    CMTimeRange(start: insertAt, duration: mainDuration - insertAt),
                    of: at, at: insertAt + clipDuration)
            }
        }
        for at in clipAudioTracks {
            let compAudio = composition.addMutableTrack(withMediaType: .audio,
                                                        preferredTrackID: kCMPersistentTrackID_Invalid)!
            try? compAudio.insertTimeRange(
                CMTimeRange(start: .zero, duration: clipDuration), of: at, at: insertAt)
        }

        // --- Video composition with letterbox for the clip segment ---
        let clipFit: CGAffineTransform
        if let cv = clipVideoTrack {
            clipFit = try await letterboxTransform(track: cv, renderSize: renderSize)
        } else {
            clipFit = .identity
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: settings.frameTimescale)

        var instructions: [AVMutableVideoCompositionInstruction] = []

        // Pre-clip: [0, insertAt) — main fills frame
        if insertAt > .zero {
            let instr = AVMutableVideoCompositionInstruction()
            instr.timeRange = CMTimeRange(start: .zero, duration: insertAt)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compMainVideo)
            layer.setTransform(mainTransform, at: .zero)
            instr.layerInstructions = [layer]
            instructions.append(instr)
        }

        // Clip: [insertAt, insertAt+clipDuration) — clip letterboxed, black background
        let clipInstr = AVMutableVideoCompositionInstruction()
        clipInstr.timeRange = CMTimeRange(start: insertAt, duration: clipDuration)
        clipInstr.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let clipLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: compClipVideo)
        clipLayer.setTransform(clipFit, at: insertAt)
        clipInstr.layerInstructions = [clipLayer]
        instructions.append(clipInstr)

        // Post-clip: [insertAt+clipDuration, end) — main fills frame
        if insertAt < mainDuration {
            let postStart = insertAt + clipDuration
            let instr = AVMutableVideoCompositionInstruction()
            instr.timeRange = CMTimeRange(start: postStart, duration: mainDuration - insertAt)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compMainVideo)
            layer.setTransform(mainTransform, at: postStart)
            instr.layerInstructions = [layer]
            instructions.append(instr)
        }

        videoComposition.instructions = instructions

        // --- Export ---
        let ext = mainURL.pathExtension.lowercased()
        let mergedURL = mainURL.deletingLastPathComponent()
            .appendingPathComponent("screen_recording_merged.\(ext)")

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: settings.exportPreset
        ) else { throw MergeError.exportSessionFailed }

        session.videoComposition = videoComposition

        if FileManager.default.fileExists(atPath: mergedURL.path) {
            try FileManager.default.removeItem(at: mergedURL)
        }

        let pollTask = Task { @MainActor in
            while !Task.isCancelled {
                mergeProgress = Double(session.progress)
                if session.progress >= 1.0 { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        defer { pollTask.cancel() }

        try await session.export(to: mergedURL, as: settings.avFileType)
        mergeProgress = 1.0

        try FileManager.default.removeItem(at: mainURL)
        try FileManager.default.moveItem(at: mergedURL, to: mainURL)
    }

    /// Transcode a MOV capture to the user's preferred format and resolution.
    /// Deletes the source MOV on success and returns the new file URL.
    func transcode(movURL: URL, settings: ExportSettings) async throws -> URL {
        let outputURL = movURL.deletingPathExtension()
            .appendingPathExtension(settings.fileExtension)

        let asset = AVURLAsset(url: movURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: settings.exportPreset)
        else { throw MergeError.exportSessionFailed }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        try await session.export(to: outputURL, as: settings.avFileType)
        try? FileManager.default.removeItem(at: movURL)

        return outputURL
    }

    // MARK: - Letterbox transform

    // Returns the transform that fits `track` inside `renderSize` with black bars,
    // correctly handling any rotation baked into the track's preferred transform.
    private func letterboxTransform(track: AVAssetTrack, renderSize: CGSize) async throws -> CGAffineTransform {
        let naturalSize       = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)

        // Apply the preferred transform to get the actual display rect.
        // It may have a negative origin (e.g. a 90° rotation moves the origin).
        let displayRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)

        // Translate to remove any negative offset so the video starts at (0,0).
        let normalize = CGAffineTransform(translationX: -displayRect.origin.x,
                                          y: -displayRect.origin.y)

        let effectiveW = displayRect.width.magnitude
        let effectiveH = displayRect.height.magnitude

        // Scale to fit (letterbox or pillarbox)
        let scale  = min(renderSize.width / effectiveW, renderSize.height / effectiveH)
        let offsetX = (renderSize.width  - effectiveW * scale) / 2
        let offsetY = (renderSize.height - effectiveH * scale) / 2

        return preferredTransform
            .concatenating(normalize)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
    }

    // MARK: - Errors

    enum MergeError: LocalizedError {
        case exportSessionFailed
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .exportSessionFailed: "Could not create export session."
            case .exportFailed: "Video merge failed during export."
            }
        }
    }
}
