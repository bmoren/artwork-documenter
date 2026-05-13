import Foundation
import AVFoundation
import CoreMedia
import UniformTypeIdentifiers

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
    var videoContainer: VideoContainer {
        didSet { save("exportVideoContainer", videoContainer.rawValue) }
    }
    var videoFrameRate: FrameRate {
        didSet { save("exportVideoFrameRate", videoFrameRate.rawValue) }
    }

    // MARK: - Images

    var imageFormat: ImageFormat {
        didSet { save("exportImageFormat", imageFormat.rawValue) }
    }
    var jpegQuality: JPEGQuality {
        didSet { save("exportJpegQuality", jpegQuality.rawValue) }
    }

    // MARK: - Init (loads from UserDefaults, falls back to defaults)

    init() {
        let d = UserDefaults.standard
        videoCodec      = VideoCodec(rawValue:      d.string(forKey: "exportVideoCodec")      ?? "") ?? .h264
        videoResolution = VideoResolution(rawValue: d.string(forKey: "exportVideoResolution") ?? "") ?? .p1080
        videoContainer  = VideoContainer(rawValue:  d.string(forKey: "exportVideoContainer")  ?? "") ?? .mp4
        videoFrameRate  = FrameRate(rawValue:       d.string(forKey: "exportVideoFrameRate")  ?? "") ?? .fps30
        imageFormat     = ImageFormat(rawValue:     d.string(forKey: "exportImageFormat")     ?? "") ?? .png
        jpegQuality     = JPEGQuality(rawValue:     d.string(forKey: "exportJpegQuality")     ?? "") ?? .high
    }

    private func save(_ key: String, _ value: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    // MARK: - Convenience accessors used by ScreenCaptureManager

    /// The exact pixel dimensions to pass to both SCStreamConfiguration and AVAssetWriterInput.
    /// Returns nil when .native is selected (caller queries display directly).
    var outputDimensions: (width: Int, height: Int)? { videoResolution.dimensions }

    var avVideoCodecType: AVVideoCodecType { videoCodec.avType }
    var avFileType: AVFileType { videoContainer.avFileType }
    var fileExtension: String  { videoContainer.fileExtension }
    var frameTimescale: Int32  { videoFrameRate.timescale }

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

        /// nil means "use display's actual pixel dimensions"
        var dimensions: (width: Int, height: Int)? {
            switch self {
            case .p720:   return (1280, 720)
            case .p1080:  return (1920, 1080)
            case .p1440:  return (2560, 1440)
            case .native: return nil
            }
        }
    }

    enum VideoContainer: String, CaseIterable {
        case mp4 = "MP4"
        case mov = "MOV"

        var fileExtension: String {
            switch self {
            case .mp4: return "mp4"
            case .mov: return "mov"
            }
        }

        var avFileType: AVFileType {
            switch self {
            case .mp4: return .mp4
            case .mov: return .mov
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

    enum ImageFormat: String, CaseIterable {
        case png  = "PNG"
        case jpeg = "JPEG"

        var utType: CFString {
            switch self {
            case .png:  return UTType.png.identifier  as CFString
            case .jpeg: return UTType.jpeg.identifier as CFString
            }
        }

        var fileExtension: String {
            switch self {
            case .png:  return "png"
            case .jpeg: return "jpg"
            }
        }
    }

    enum JPEGQuality: String, CaseIterable {
        case low    = "Low"
        case medium = "Medium"
        case high   = "High"

        var value: CGFloat {
            switch self {
            case .low:    return 0.5
            case .medium: return 0.75
            case .high:   return 0.92
            }
        }
    }
}
