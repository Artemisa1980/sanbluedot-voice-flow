import Foundation

public struct DictationRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let rawText: String
    public let personalizedText: String
    public let finalText: String
    public let cleaner: String
    public let mode: String
    public let model: String?
    public let latencySeconds: Double
    public let usedFallback: Bool
    /// Which side refused, in the words the log uses. One bit said a fallback happened
    /// and never whether the guard rejected a cleanup or the provider never answered,
    /// and those call for opposite responses. Optional: records written before this
    /// field decode with nil rather than failing.
    public let fallbackReason: String?
    public let didAutoPaste: Bool
    /// What FIX made of this dictation, kept in the row it came from. A fix that joined
    /// History as a row of its own duplicated the dictation and, with ten slots, pushed
    /// a real one out. Optional: records written before it decode with nil.
    public let fixedText: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        rawText: String,
        personalizedText: String,
        finalText: String,
        cleaner: String,
        mode: String,
        model: String? = nil,
        latencySeconds: Double,
        usedFallback: Bool = false,
        fallbackReason: String? = nil,
        didAutoPaste: Bool = false,
        fixedText: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rawText = rawText
        self.personalizedText = personalizedText
        self.finalText = finalText
        self.cleaner = cleaner
        self.mode = mode
        self.model = model
        self.latencySeconds = latencySeconds
        self.usedFallback = usedFallback
        self.fallbackReason = fallbackReason
        self.didAutoPaste = didAutoPaste
        self.fixedText = fixedText
    }

    /// The text this row stands for now: the fix when there is one, else what was delivered.
    public var currentText: String {
        fixedText ?? finalText
    }

    /// The same dictation with its fix attached. Identity and time are kept, so the row
    /// stays where it was.
    public func withFix(_ text: String) -> DictationRecord {
        DictationRecord(
            id: id,
            timestamp: timestamp,
            rawText: rawText,
            personalizedText: personalizedText,
            finalText: finalText,
            cleaner: cleaner,
            mode: mode,
            model: model,
            latencySeconds: latencySeconds,
            usedFallback: usedFallback,
            fallbackReason: fallbackReason,
            didAutoPaste: didAutoPaste,
            fixedText: text
        )
    }

    /// Whether two texts say the same words, ignoring case, accents and punctuation.
    ///
    /// A fix exists to drop what the speaker took back. One that only moved a comma or
    /// restored an accent changed nothing worth a fix, and is reported as nothing to
    /// correct rather than stored.
    public static func sameWords(_ first: String, _ second: String) -> Bool {
        words(first) == words(second)
    }

    private static func words(_ text: String) -> [String] {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    public var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }

    public var shortTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }

    /// Single-line compact snippet for menu display.
    public func menuPreview(maxLength: Int = 42) -> String {
        let limit = max(0, maxLength)
        let sanitized = currentText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.count <= limit {
            return sanitized
        }
        let index = sanitized.index(sanitized.startIndex, offsetBy: limit)
        return String(sanitized[..<index]) + "…"
    }

    public var menuTitle: String {
        let modeTag: String
        switch mode.lowercased() {
        case "translate":
            modeTag = "ES➔EN"
        case "meeting":
            modeTag = "NOTES"
        case "action", "actions":
            modeTag = "ACTION"
        case "fix":
            modeTag = "FIX"
        default:
            modeTag = "CLEAN"
        }
        return "[\(shortTimeString)] (\(modeTag)) \"\(menuPreview())\""
    }
}

public struct DictationHistoryStore: Codable, Equatable, Sendable {
    public static let maxCapacity = 10
    public static let defaultsKey = "dot.sanblue.voiceflow.dictationHistory"

    public private(set) var records: [DictationRecord]

    public init(records: [DictationRecord] = []) {
        self.records = Array(records.prefix(Self.maxCapacity))
    }

    public init(from decoder: Decoder) throws {
        // Support both single array representation and keyed container
        if let container = try? decoder.singleValueContainer(),
           let items = try? container.decode([DictationRecord].self) {
            self.records = Array(items.prefix(Self.maxCapacity))
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let items = try container.decode([DictationRecord].self, forKey: .records)
        self.records = Array(items.prefix(Self.maxCapacity))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(records)
    }

    public mutating func append(_ record: DictationRecord) {
        records.insert(record, at: 0)
        if records.count > Self.maxCapacity {
            records.removeLast(records.count - Self.maxCapacity)
        }
    }

    /// Attach a fix to the row it belongs to. False when the row is no longer held.
    public mutating func attachFix(_ text: String, to id: UUID) -> Bool {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return false }
        records[index] = records[index].withFix(text)
        return true
    }

    public mutating func clear() {
        records.removeAll()
    }

    public func encode() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public static func load(from data: Data) -> DictationHistoryStore? {
        if let store = try? JSONDecoder().decode(DictationHistoryStore.self, from: data) {
            return store
        }
        // Fallback for legacy keyed format
        struct LegacyContainer: Codable {
            let records: [DictationRecord]
        }
        if let legacy = try? JSONDecoder().decode(LegacyContainer.self, from: data) {
            return DictationHistoryStore(records: legacy.records)
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case records
    }
}
