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

    // Built once, not per row (D-177).
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let shortClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    public var timeString: String {
        Self.clock.string(from: timestamp)
    }

    public var shortTimeString: String {
        Self.shortClock.string(from: timestamp)
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
    /// Where the history lived until 2026-10-25: user defaults, outside `vf export`
    /// (D-11). Read once to move it, then removed.
    public static let defaultsKey = "dot.sanblue.voiceflow.dictationHistory"

    /// Beside the other personal stores, so `vf export` carries it.
    public static var defaultStoreURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("sanblue.voiceflow/history.local.json")
    }

    /// The history on disk, moving the user-defaults copy there the first time.
    ///
    /// If the file on disk cannot be decoded due to damage or corruption, it is moved
    /// aside to `.corrupt-<timestamp>` and reported (R5) rather than silently returning
    /// an empty store that the next edit would overwrite (D-203).
    public static func loadReporting(
        from fileURL: URL = defaultStoreURL,
        defaults: UserDefaults = .standard
    ) -> (store: DictationHistoryStore, failure: String?) {
        VoiceSnippetStore.withFileLock(fileURL) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                guard let data = try? Data(contentsOf: fileURL) else {
                    return (DictationHistoryStore(), "The dictation history could not be read right now; it was left in place.")
                }
                guard let store = load(from: data) else {
                    return (DictationHistoryStore(), quarantine(fileURL, reason: "the file is not valid dictation history JSON"))
                }
                return (store, nil)
            }
            guard let data = defaults.data(forKey: defaultsKey), let store = load(from: data) else {
                return (DictationHistoryStore(), nil)
            }
            if let encoded = store.encode(), VoiceSnippetStore.writeFlushed(encoded, to: fileURL) {
                defaults.removeObject(forKey: defaultsKey)
            }
            return (store, nil)
        }
    }

    public static func loadFromDisk(
        at fileURL: URL = defaultStoreURL,
        defaults: UserDefaults = .standard
    ) -> DictationHistoryStore {
        loadReporting(from: fileURL, defaults: defaults).store
    }

    private static func quarantine(_ fileURL: URL, reason: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSSSSS"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: Date())
        let destination = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileURL.lastPathComponent).corrupt-\(stamp)")
        do {
            try FileManager.default.moveItem(at: fileURL, to: destination)
            return "dictation history could not be read (\(reason)). Kept as \(destination.lastPathComponent); "
                + "this session starts with none."
        } catch {
            return "dictation history could not be read (\(reason)) and could not be moved aside. "
                + "Nothing was written over it; fix or remove \(fileURL.lastPathComponent)."
        }
    }

    @discardableResult
    public func save(to fileURL: URL = defaultStoreURL) -> Bool {
        guard let data = encode() else { return false }
        return VoiceSnippetStore.withFileLock(fileURL) {
            VoiceSnippetStore.writeFlushed(data, to: fileURL)
        }
    }

    public private(set) var records: [DictationRecord]

    public init(records: [DictationRecord] = []) {
        self.records = Array(records.prefix(Self.maxCapacity))
    }

    /// One record that fails to decode is dropped alone; it used to take all ten with it
    /// (D-85).
    private struct Lossy: Decodable {
        let record: DictationRecord?
        init(from decoder: Decoder) throws {
            record = try? DictationRecord(from: decoder)
        }
    }

    public init(from decoder: Decoder) throws {
        // Support both single array representation and keyed container
        if let container = try? decoder.singleValueContainer(),
           let items = try? container.decode([Lossy].self) {
            self.records = Array(items.compactMap(\.record).prefix(Self.maxCapacity))
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let items = try container.decode([Lossy].self, forKey: .records)
        self.records = Array(items.compactMap(\.record).prefix(Self.maxCapacity))
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
