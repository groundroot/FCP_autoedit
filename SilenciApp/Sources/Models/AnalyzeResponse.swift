import Foundation

/// Top-level response from the Python `analyze` JSON-RPC method.
/// Contains transcribed segments and video metadata.
struct AnalyzeResponse: Codable, Sendable {
    let segments: [Segment]
    let videoInfo: VideoInfo

    enum CodingKeys: String, CodingKey {
        case segments
        case videoInfo = "video_info"
    }
}

/// Video file metadata returned alongside analysis results.
struct VideoInfo: Codable, Sendable {
    let fps: Double
    let width: Int
    let height: Int
    let duration: Double
}
