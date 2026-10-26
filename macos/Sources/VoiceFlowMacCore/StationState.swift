/// What the station is doing, as the window's badge names it.
///
/// The badge knew only recording and ready, so processing and a failure both read READY
/// (D-72). The state is published from the same status line the menu bar shows.
public enum StationState: Equatable, Sendable {
    case ready
    case recording
    case processing
    case failed

    public var badgeLabel: String {
        switch self {
        case .ready: return "READY"
        case .recording: return "ON AIR"
        case .processing: return "PROCESSING"
        case .failed: return "FAILED"
        }
    }
}

/// What the capsule may say about a run before it starts.
///
/// It always read WHISPER and INFERENCE, while Parakeet listened and Literal or the
/// filler rule ran no model (D-73).
public enum RunLabels {
    public static func speech(_ engine: SpeechEngine) -> String {
        switch engine {
        case .whisper: return "WHISPER"
        case .parakeet: return "PARAKEET"
        }
    }

    /// Whether a model rewrites the text. Literal never does; with Parakeet an ordinary
    /// `clean` dictation is handled by rule (a spoken take-back still asks the model,
    /// which cannot be known before the transcript exists).
    public static func runsModel(cleaner: CleanerMode, mode: ProcessingMode, speech: SpeechEngine) -> Bool {
        if cleaner == .literal { return false }
        if speech == .parakeet && (mode == .clean || mode == .actions) { return false }
        return true
    }
}
