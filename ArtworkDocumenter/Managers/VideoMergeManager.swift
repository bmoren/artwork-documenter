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

    func merge(mainURL: URL, clipURL: URL, position: InsertPosition,
               settings: ExportSettings) async throws {
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

        let ext = mainURL.pathExtension.lowercased()
        let mergedURL = mainURL.deletingLastPathComponent()
            .appendingPathComponent("screen_recording_merged.\(ext)")

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: settings.exportPreset
        ) else { throw MergeError.exportSessionFailed }

        if FileManager.default.fileExists(atPath: mergedURL.path) {
            try FileManager.default.removeItem(at: mergedURL)
        }

        try await session.export(to: mergedURL, as: settings.avFileType)

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
