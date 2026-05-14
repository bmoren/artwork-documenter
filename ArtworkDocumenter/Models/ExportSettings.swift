import Foundation
import AVFoundation
import CoreMedia

/// Persisted export preferences. Stored in UserDefaults so they survive
/// across sessions. Injected into the SwiftUI environment alongside ProjectState.
@Observable
final class ExportSettings {

    // MARK: - Video

    var videoCodec: VideoCodec {
        didSet { save("exportVideoCodec", videoCodec.rawValue) }
    }
    var videoResolution: VideoResolution {
        didSet { save("exportVideoResolution", videoResolution.rawValue) }
    }
    var videoFrameRate: FrameRate {
        didSet { save("exportVideoFrameRate", videoFrameRate.rawValue) }
    }

    // MARK: - Init

    init() {
        let d = UserDefaults.standard
        videoCodec      = VideoCodec(rawValue:      d.string(forKey: "exportVideoCodec")      ?? "") ?? .h264
        videoResolution = VideoResolution(rawValue: d.string(forKey: "exportVideoResolution") ?? "") ?? .p1080
        videoFrameRate  = FrameRate(rawValue:       d.string(forKey: "exportVideoFrameRate")  ?? "") ?? .fps30
    }

    private func save(_ key: String, _ value: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    // MARK: - Hardcoded output format (always MP4)

    var avFileType: AVFileType { .mp4 }
    var fileExtension: String  { "mp4" }

    // MARK: - Convenience accessors used by recording pipeline

    var avVideoCodecType: AVVideoCodecType { videoCodec.avType }
    var frameTimescale: Int32              { videoFrameRate.timescale }

    /// AVAssetExportSession preset matching the chosen codec and resolution.
    var exportPreset: String {
        switch videoCodec {
        case .h264:
            switch videoResolution {
            case .p720:           return AVAssetExportPreset1280x720
            case .p1080, .p1440: return AVAssetExportPreset1920x1080
            case .native:         return AVAssetExportPresetHighestQuality
            }
        case .hevc:
            switch videoResolution {
            case .p720, .p1080: return AVAssetExportPresetHEVC1920x1080
            case .p1440, .native: return AVAssetExportPresetHEVCHighestQuality
            }
        }
    }

    // MARK: - Enums

    enum VideoCodec: String, CaseIterable {
        case h264 = "H.264"
        case hevc = "H.265 (HEVC)"

        var avType: AVVideoCodecType {
            switch self {
            case .h264: return .h264
            case .hevc: return .hevc
            }
        }
    }

    enum VideoResolution: String, CaseIterable {
        case p720   = "720p"
        case p1080  = "1080p"
        case p1440  = "1440p"
        case native = "Native"

        var label: String {
            switch self {
            case .p720:   return "720p (HD)"
            case .p1080:  return "1080p (Full HD)"
            case .p1440:  return "1440p (QHD)"
            case .native: return "Native"
            }
        }
    }

    enum FrameRate: String, CaseIterable {
        case fps24 = "24 fps"
        case fps30 = "30 fps"
        case fps60 = "60 fps"

        var timescale: Int32 {
            switch self {
            case .fps24: return 24
            case .fps30: return 30
            case .fps60: return 60
            }
        }
    }
}
