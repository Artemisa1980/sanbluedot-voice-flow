import Foundation

/// How long one take may run, and what is left on disk when the app stops.
public enum RecordingHygiene {
    /// A take ends here even if the release never arrives: a Mac that sleeps with the key
    /// down, or a release the event tap missed, kept the microphone open until the next
    /// press (D-67). Two minutes is far past any dictation and short of an unnoticed hour.
    public static let maximumRecordingSeconds: TimeInterval = 120

    /// The prefix every temporary take carries, so a sweep can find this app's files and
    /// only them.
    public static let temporaryAudioPrefix = "sanbluedot-voiceflow-"

    /// Takes a quit, a crash or a forced quit left behind (D-68). `keeping` is the take in
    /// use, which a sweep must never delete under the recorder or the engine.
    public static func strandedTakes(in directory: URL, keeping: URL? = nil) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { $0.hasPrefix(temporaryAudioPrefix) && $0.hasSuffix(".wav") }
            .map { directory.appendingPathComponent($0) }
            .filter { $0.standardizedFileURL != keeping?.standardizedFileURL }
    }

    /// Deletes the stranded takes and returns how many could not be deleted.
    @discardableResult
    public static func sweep(in directory: URL, keeping: URL? = nil) -> Int {
        strandedTakes(in: directory, keeping: keeping).reduce(0) { failures, url in
            (try? FileManager.default.removeItem(at: url)) == nil ? failures + 1 : failures
        }
    }
}
