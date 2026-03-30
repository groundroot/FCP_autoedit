import Foundation

/// A transcribed speech segment from the Python analysis pipeline.
/// Corresponds to the JSON structure returned by silence_cutter.server `analyze` method.
///
/// Python sends: `{ "seg_start": Double, "seg_end": Double, "text": String, "words": [...] }`
/// `id` and `isKept` are Swift-side only — not present in the JSON.
struct Segment: Identifiable, Codable, Sendable {
    let id: UUID
    /// Start time in seconds
    var start: Double
    /// End time in seconds
    var end: Double
    /// Transcribed text for this segment
    var text: String
    /// Whether this segment is kept in the final edit
    var isKept: Bool
    /// Word-level timing from ASR
    var words: [Word]

    /// Duration of this segment in seconds
    var duration: Double { end - start }

    /// Text composed only of kept words. Falls back to full text if no words exist.
    var keptText: String {
        guard !words.isEmpty else { return text }
        let kept = words.filter(\.isKept).map(\.text)
        return kept.isEmpty ? "" : kept.joined(separator: " ")
    }

    /// Text for export — uses keptText (word-filtered) if words exist, otherwise user-edited text.
    var exportText: String {
        guard !words.isEmpty else { return text }
        return keptText
    }

    init(id: UUID = UUID(), start: Double, end: Double, text: String, isKept: Bool = true, words: [Word] = []) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.isKept = isKept
        self.words = words
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case start = "seg_start"
        case end = "seg_end"
        case text
        case words
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.start = try container.decode(Double.self, forKey: .start)
        self.end = try container.decode(Double.self, forKey: .end)
        self.text = try container.decode(String.self, forKey: .text)
        self.words = try container.decodeIfPresent([Word].self, forKey: .words) ?? []
        // Swift-side defaults — not present in Python JSON
        self.id = UUID()
        self.isKept = true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(text, forKey: .text)
        try container.encode(words, forKey: .words)
    }
}
