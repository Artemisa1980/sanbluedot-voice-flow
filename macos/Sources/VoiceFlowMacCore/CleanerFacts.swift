import Foundation

/// One line of the engine information sheet.
public struct EngineFact: Sendable, Equatable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// What the speaker needs in order to choose an engine, and nothing else.
///
/// Every figure here is a measurement with a date. R9 forbids the interface from showing
/// a number it did not measure, and that applies hardest in a panel whose whole purpose
/// is to help someone decide: an invented latency would decide for them, wrongly. Where
/// nothing was measured, the sheet says so instead of estimating.
public extension CleanerMode {
    var facts: [EngineFact] {
        switch self {
        case .literal:
            return [
                EngineFact(label: "SPEED", value: "Instant. There is no cleanup step."),
                EngineFact(label: "DELIVERS", value: "Always. Nothing can be busy."),
                EngineFact(label: "PRIVACY", value: "Nothing leaves this Mac."),
                EngineFact(
                    label: "YOU GET",
                    value: "The transcript as the engine heard it, plus your confirmed corrections."
                ),
            ]
        case .ollama:
            return [
                EngineFact(label: "SPEED", value: "Runs on this Mac. Not measured on the fixed corpus."),
                EngineFact(label: "DELIVERS", value: "Always, while the Ollama daemon is running."),
                EngineFact(label: "PRIVACY", value: "Nothing leaves this Mac."),
                EngineFact(
                    label: "NEEDS",
                    value: "Ollama running locally. Without it the dictation falls back to the transcript."
                ),
            ]
        case .gemini:
            return [
                EngineFact(label: "SPEED", value: "4.19s median, worst success 7.29s."),
                EngineFact(label: "DELIVERS", value: "5 of 6. The sixth is Google capacity, not this project."),
                EngineFact(
                    label: "WHEN BUSY",
                    value: "All three models are tried, then the raw transcript arrives at 45s."
                ),
                EngineFact(
                    label: "PRIVACY",
                    value: "The transcript text leaves this Mac. The audio never does."
                ),
            ]
        }
    }

    /// The day the figures above were taken, or nil when this engine has none to date.
    /// Shown with them, because nothing re-measures and an undated number reads as today.
    var factsMeasuredOn: String? {
        switch self {
        case .literal, .ollama:
            return nil
        case .gemini:
            return "2026-08-31"
        }
    }

    /// One line for the speaker deciding right now.
    var recommendation: String {
        switch self {
        case .literal:
            return "Use it when you want your own words untouched."
        case .ollama:
            return "Use it when the text must not leave the Mac and you can wait."
        case .gemini:
            return "Best result when it answers. Avoid it when you cannot lose 45 seconds."
        }
    }
}
