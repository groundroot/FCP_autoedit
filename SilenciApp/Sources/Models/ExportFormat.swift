import Foundation

/// Supported export formats for the edited timeline.
enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case fcpxml
    case mp4
    case srt
    case itt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fcpxml: "FCPXML (Final Cut Pro)"
        case .mp4: "MP4 (영상 렌더링)"
        case .srt: "SRT (자막)"
        case .itt: "iTT (iTunes Timed Text)"
        }
    }

    var fileExtension: String {
        switch self {
        case .fcpxml: "fcpxml"
        case .mp4: "mp4"
        case .srt: "srt"
        case .itt: "itt"
        }
    }
}
