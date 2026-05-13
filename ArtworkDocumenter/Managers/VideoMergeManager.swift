import Foundation
import AVFoundation
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

    func merge(mainURL: URL, clipURL: URL, position: InsertPosition) async throws {
        isMerging = true
        defer { isMerging = false }

        let mainAsset = AVURLAsset(url: mainURL)
        let clipAsset = AVURLAsset(url: clipURL)

        let mainDuration = try await mainAsset.load(.duration)
        let clipDuration  = try await clipAsset.load(.duration)

        let insertAt: CMTime
        switch position {
        case .start:
            insertAt = .zero
        case .end:
            insertAt = mainDuration
        case .timestamp(let seconds):
            let clamped = min(max(seconds, 0), mainDuration.seconds)
            insertAt = CMTime(seconds: clamped, preferredTimescale: 600)
        }

        let composition = AVMutableComposition()

        if insertAt > .zero {
            try await composition.insertTimeRange(
                CMTimeRange(start: .zero, duration: insertAt),
                of: mainAsset, at: .zero
            )
        }
        try await composition.insertTimeRange(
            CMTimeRange(start: .zero, duration: clipDuration),
            of: clipAsset, at: composition.duration
        )
        if insertAt < mainDuration {
            try await composition.insertTimeRange(
                CMTimeRange(start: insertAt, duration: mainDuration - insertAt),
                of: mainAsset, at: composition.duration
            )
        }

        let mergedURL = mainURL.deletingLastPathComponent()
            .appendingPathComponent("screen_recording_merged.mov")

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else { throw MergeError.exportSessionFailed }

        if FileManager.default.fileExists(atPath: mergedURL.path) {
            try FileManager.default.removeItem(at: mergedURL)
        }

        session.outputURL = mergedURL
        session.outputFileType = .mov

        // Bridge the callback-based export into async/await
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: session.error ?? MergeError.exportFailed)
                default:
                    continuation.resume(throwing: MergeError.exportFailed)
                }
            }
        }

        try FileManager.default.removeItem(at: mainURL)
        try FileManager.default.moveItem(at: mergedURL, to: mainURL)
    }

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
