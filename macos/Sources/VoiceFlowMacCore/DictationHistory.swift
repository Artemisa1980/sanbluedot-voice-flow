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
    public let didAutoPaste: Bool

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
        didAutoPaste: Bool = false
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
        self.didAutoPaste = didAutoPaste
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
        let sanitized = finalText
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
