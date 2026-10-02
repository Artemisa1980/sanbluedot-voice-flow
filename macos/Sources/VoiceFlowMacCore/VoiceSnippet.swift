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

    // There is deliberately no `expand` here.
    //
    // R5b requires one non-cascading scan. This type used to run a second scan in the
    // app, over text the engine had already expanded, and that second pass matched the
    // *payload* of the first expansion: a `firma` snippet whose body says `mi linkedin`
    // came back with the link substituted, which is neither what one scan produces nor
    // what the engine reported for the same dictation. Expansion happens once, in
    // `snippets.py`, and this store is the editor the window writes with.

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

    /// Parse an envelope, or return nil so the caller can decide what a damaged file means.
    /// Returning an empty store here is what allowed a decode failure to look like an
    /// empty store and be overwritten; the distinction now survives to the caller.
    public static func decode(from data: Data) -> VoiceSnippetStore? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return nil
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

    /// The sidecar `flock` file `memory.py` uses for the same store. Both processes take
    /// the same lock, so a CLI `snippet add` and an app-side add cannot lose one another.
    public static func lockURL(for fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent(".\(fileURL.lastPathComponent).lock")
    }

    /// Serialize one store's read-modify-write cycle across processes, mirroring
    /// `exclusive_file_lock` in `memory.py`. A lock that cannot be taken does not block
    /// the speaker: the body still runs, unserialized, rather than failing the edit.
    public static func withFileLock<T>(_ fileURL: URL, _ body: () -> T) -> T {
        let lockURL = Self.lockURL(for: fileURL)
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = open(lockURL.path, O_RDWR | O_CREAT, 0o644)
        guard descriptor >= 0 else { return body() }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { return body() }
        defer { flock(descriptor, LOCK_UN) }
        return body()
    }

    /// Apply one edit to the file as it is now, under the lock the engine also takes.
    ///
    /// The window used to write the list it loaded at launch, so a `vf snippet add` made
    /// while it ran was erased by the next edit here (D-40). The file is re-read inside
    /// the lock, changed and written back. Returns the store as written, or nil when the
    /// file could not be read or written; nothing is written over a file this cannot read.
    public static func edit(
        at fileURL: URL = defaultStoreURL,
        _ change: (VoiceSnippetStore) -> Void
    ) -> VoiceSnippetStore? {
        withFileLock(fileURL) {
            let current: VoiceSnippetStore
            if FileManager.default.fileExists(atPath: fileURL.path) {
                guard let data = try? Data(contentsOf: fileURL),
                      let decoded = decode(from: data) else { return nil }
                current = decoded
            } else {
                current = VoiceSnippetStore()
            }
            change(current)
            guard let data = current.encode(),
                  (try? data.write(to: fileURL, options: .atomic)) != nil else { return nil }
            return current
        }
    }

    public func save(to fileURL: URL = defaultStoreURL) {
        guard let data = encode() else { return }
        Self.withFileLock(fileURL) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Read the store, preserving anything unreadable instead of replacing it.
    ///
    /// A damaged file used to decode to an empty store with no report; the next add from
    /// the window then wrote over the speaker's real snippets and destroyed them. The
    /// file is now moved aside under a dated name — the same rule `read_json_or_quarantine`
    /// applies in `memory.py` — and the failure is returned so the interface can say so.
    public static func loadReporting(from fileURL: URL = defaultStoreURL) -> (store: VoiceSnippetStore, failure: String?) {
        withFileLock(fileURL) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return (VoiceSnippetStore(), nil)
            }
            guard let data = try? Data(contentsOf: fileURL) else {
                return (VoiceSnippetStore(), quarantine(fileURL, reason: "the file could not be read"))
            }
            guard let store = decode(from: data) else {
                return (VoiceSnippetStore(), quarantine(fileURL, reason: "the file is not a valid snippet store"))
            }
            return (store, nil)
        }
    }

    public static func load(from fileURL: URL = defaultStoreURL) -> VoiceSnippetStore {
        loadReporting(from: fileURL).store
    }

    /// Move an unusable store aside under a dated name and describe what happened.
    /// Preserved rather than deleted: these are the speaker's own phrases.
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
            return "snippets could not be read (\(reason)). Kept as \(destination.lastPathComponent); "
                + "this session starts with none."
        } catch {
            return "snippets could not be read (\(reason)) and could not be moved aside. "
                + "Nothing was written over it; fix or remove \(fileURL.lastPathComponent)."
        }
    }
}
