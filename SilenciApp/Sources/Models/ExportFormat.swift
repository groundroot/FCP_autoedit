import Foundation

/// Supported export formats for the edited timeline.
enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case fcpxml
    case srt
    case itt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fcpxml: "FCPXML (Final Cut Pro)"
        case .srt: "SRT (자막)"
        case .itt: "iTT (iTunes Timed Text)"
        }
    }

    var fileExtension: String {
        switch self {
        case .fcpxml: "fcpxml"
        case .srt: "srt"
        case .itt: "itt"
        }
    }
}
