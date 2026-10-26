import Foundation

/// The badge one activity-log line carries, and which console tab it falls into.
///
/// The category and the rule that assigns it live here rather than beside the SwiftUI
/// view, because `VoiceFlowMac` is an executable target that no check can import. The
/// colour of each badge stays with the view; the decision does not.
public enum LogCategory: String, CaseIterable, Sendable {
    case stt = "WHISPER"
    case gemini = "GEMINI"
    case apple = "APPLE"
    case action = "ACTION"
    case snippet = "SNIPPET"
    case paste = "PASTE"
    case system = "SYS"
    case warn = "WARN"

    /// Read a category out of the message itself.
    ///
    /// Order matters: a provider name wins over the generic words, so "gemini is at
    /// capacity" is a provider line and not a warning. The matches are whole words, so
    /// an ordinary sentence containing "transaction" is not filed under actions.
    public static func inferred(from message: String) -> LogCategory {
        let words = Set(
            message
                .lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )
        for (category, triggers) in orderedTriggers where !words.isDisjoint(with: triggers) {
            return category
        }
        return .system
    }

    /// Checked in order. A line naming a provider is about that provider even when it
    /// also says "failed".
    private static let orderedTriggers: [(LogCategory, Set<String>)] = [
        (.gemini, ["gemini"]),
        (.apple, ["apple"]),
        (.stt, ["whisper", "heard"]),
        (.action, ["action", "executed"]),
        (.snippet, ["snippet", "snippets", "expanded"]),
        (.paste, ["pasted", "copied", "paste"]),
        // A fallback is a degraded outcome, not routine traffic: the speaker got the
        // transcript instead of the cleanup they asked for.
        (.warn, ["failed", "error", "warning", "warn", "fallback", "ignored"]),
    ]
}


/// The words the floating capsule shows. Pure text, so a check can assert what the
/// speaker reads without standing up an AppKit panel.
public enum HUDBadge {
    /// While recording, the badge names the mode so the speaker sees it before speaking.
    public static func recording(mode: ProcessingMode) -> String {
        switch mode {
        case .clean: return "ON AIR"
        case .translate: return "ON AIR • ES➔EN"
        case .meeting: return "ON AIR • MEETING"
        case .actions: return "ON AIR • ACTION"
        }
    }

    /// While recording, the badge names the mode and the detected target application context.
    public static func recording(mode: ProcessingMode, context: AppContext?) -> String {
        guard let context = context, context.category != .general else {
            return recording(mode: mode)
        }
        switch mode {
        case .clean: return "ON AIR • \(context.shortName)"
        case .translate: return "ES➔EN • \(context.shortName)"
        case .meeting: return "MEETING • \(context.shortName)"
        case .actions: return "ACTION • \(context.shortName)"
        }
    }

    /// While processing, it names the work and the provider doing it. The action mode
    /// names no provider: the command is recognized here, not by a cleaner.
    public static func processing(mode: ProcessingMode, cleanerName: String) -> String {
        let provider = cleanerName.uppercased()
        switch mode {
        case .clean: return "CLEANING (\(provider))"
        case .translate: return "TRANSLATING (\(provider))"
        case .meeting: return "STRUCTURING (\(provider))"
        case .actions: return "PARSING ACTION"
        }
    }

    /// `gemini-3.8-flash` reads as `3.8` in a capsule this narrow. The full identifier
    /// stays in the station window's activity log.
    public static func shortModelName(_ model: String) -> String {
        model
            .replacingOccurrences(of: "gemini-", with: "")
            .replacingOccurrences(of: "-flash", with: "")
    }
}
