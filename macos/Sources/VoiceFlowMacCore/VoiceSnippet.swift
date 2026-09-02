import Foundation

public struct VoiceSnippet: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let trigger: String
    public let expansion: String
    public let description: String?

    public init(
        id: UUID = UUID(),
        trigger: String,
        expansion: String,
        description: String? = nil
    ) {
        self.id = id
        self.trigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        self.expansion = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        self.description = description?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public final class VoiceSnippetStore: @unchecked Sendable {
    private struct Envelope: Codable {
        let schemaVersion: Int
        let snippets: [VoiceSnippetPayload]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case snippets
        }
    }

    private struct VoiceSnippetPayload: Codable {
        let trigger: String
        let expansion: String
        let description: String?
    }

    private let lock = NSLock()
    private var _snippets: [VoiceSnippet] = []

    public var snippets: [VoiceSnippet] {
        lock.lock()
        defer { lock.unlock() }
        return _snippets
    }

    public init(snippets: [VoiceSnippet] = []) {
        self._snippets = snippets
    }

    public func add(trigger: String, expansion: String, description: String? = nil) -> VoiceSnippet? {
        let cleanTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanExpansion = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTrigger.isEmpty, !cleanExpansion.isEmpty else { return nil }

        let snippet = VoiceSnippet(trigger: cleanTrigger, expansion: cleanExpansion, description: description)
        lock.lock()
        defer { lock.unlock() }
        _snippets.removeAll { $0.trigger.localizedCaseInsensitiveCompare(cleanTrigger) == .orderedSame }
        _snippets.append(snippet)
        return snippet
    }

    @discardableResult
    public func delete(trigger: String) -> Bool {
        let cleanTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTrigger.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        let countBefore = _snippets.count
        _snippets.removeAll { $0.trigger.localizedCaseInsensitiveCompare(cleanTrigger) == .orderedSame }
        return _snippets.count < countBefore
    }

    @discardableResult
    public func delete(id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let countBefore = _snippets.count
        _snippets.removeAll { $0.id == id }
        return _snippets.count < countBefore
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        _snippets.removeAll()
    }

    /// Expand all registered snippet triggers inside text using word boundary safety and single-pass non-cascading matching.
    public func expand(text: String) -> String {
        let current = snippets
        guard !text.isEmpty, !current.isEmpty else { return text }

        // Sort longest triggers first so specific multi-word phrases match before substrings
        let sorted = current.sorted { $0.trigger.count > $1.trigger.count }
        let validSnippets = sorted.filter { !$0.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !validSnippets.isEmpty else { return text }

        // Map casefolded triggers to expansions
        var lookup: [String: String] = [:]
        for snip in validSnippets {
            let key = snip.trigger.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if lookup[key] == nil {
                lookup[key] = snip.expansion
            }
        }

        let combinedBranches = validSnippets
            .map { NSRegularExpression.escapedPattern(for: $0.trigger.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .joined(separator: "|")
        let pattern = "(?i)(?<!\\w)(?:\(combinedBranches))(?!\\w)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        guard !matches.isEmpty else { return text }

        // Replace matches in reverse order to preserve string indices without cascading
        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let matchedText = String(result[range]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let expansion = lookup[matchedText] {
                result.replaceSubrange(range, with: expansion)
            }
        }
        return result
    }

    public func encode() -> Data? {
        let current = snippets
        let payloads = current.map {
            VoiceSnippetPayload(trigger: $0.trigger, expansion: $0.expansion, description: $0.description)
        }
        let envelope = Envelope(schemaVersion: 1, snippets: payloads)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(envelope)
    }

    public static func decode(from data: Data) -> VoiceSnippetStore {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return VoiceSnippetStore()
        }
        let loaded = envelope.snippets.compactMap { payload -> VoiceSnippet? in
            guard !payload.trigger.isEmpty, !payload.expansion.isEmpty else { return nil }
            return VoiceSnippet(trigger: payload.trigger, expansion: payload.expansion, description: payload.description)
        }
        return VoiceSnippetStore(snippets: loaded)
    }

    public static var defaultStoreURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("sanblue.voiceflow/snippets.local.json")
    }

    public func save(to fileURL: URL = defaultStoreURL) {
        guard let data = encode() else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    public static func load(from fileURL: URL = defaultStoreURL) -> VoiceSnippetStore {
        guard let data = try? Data(contentsOf: fileURL) else {
            return VoiceSnippetStore()
        }
        return decode(from: data)
    }
}
