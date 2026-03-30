import Foundation

/// Word-level timing info from ASR transcription.
/// Corresponds to entries in the `words` array of each segment from Python.
struct Word: Identifiable, Codable, Sendable {
    let id: UUID
    /// The word text
    let text: String
    /// Start time in seconds
    let start: Double
    /// End time in seconds
    let end: Double
    /// Whether this word is kept in the final edit
    var isKept: Bool

    init(id: UUID = UUID(), text: String, start: Double, end: Double, isKept: Bool = true) {
        self.id = id
        self.text = text
        self.start = start
        self.end = end
        self.isKept = isKept
    }

    // Only text/start/end come from JSON — id is Swift-side.
    enum CodingKeys: String, CodingKey {
        case text, start, end
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try container.decode(String.self, forKey: .text)
        self.start = try container.decode(Double.self, forKey: .start)
        self.end = try container.decode(Double.self, forKey: .end)
        self.id = UUID()
        self.isKept = true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
    }
}
