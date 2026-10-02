import AppIntents
import Foundation
import VoiceFlowMacCore

/// What Siri, Spotlight, Shortcuts and the Action button can ask this app to do.
///
/// Each intent takes text and returns text. None of them opens the microphone, asks for
/// a permission or shows a window, which is why they are the ones that arrived first:
/// the engine already does all four, and the only thing that was missing was saying so
/// in a language the system reads.
///
/// They run through `voiceflow clean --no-memory`, which enters the pipeline after
/// transcription. The conservative output guard applies exactly as it does to a
/// dictation; confirmed corrections and snippets do not, because they repair and expand
/// speech and this text was written (framework.md R3d).
///
/// The engine is whichever one the speaker last chose in the window, and only while it
/// runs on this Mac. A cloud engine is refused with the reason rather than swapped for a
/// local one: a shortcut shows nothing that would say the text is leaving, and a silent
/// swap would run an engine she did not pick.
@available(macOS 13.0, *)
enum IntentEngine {
    /// Where the app keeps the engine the speaker chose. Read directly because an intent
    /// may run with no window open and no delegate alive.
    private static let cleanerDefaultsKey = "dot.sanblue.voiceflow.cleaner"

    static func selectedCleaner(_ configuration: VoiceFlowConfiguration) -> CleanerMode {
        UserDefaults.standard.string(forKey: cleanerDefaultsKey)
            .flatMap(CleanerMode.init(rawValue:)) ?? configuration.cleaner
    }

    /// Run one text through the engine and return what it delivered.
    ///
    /// A cleanup the output guard refuses is not an error here: the engine exits with
    /// status 2 and delivers the deterministic text instead, which is the speaker's own
    /// words and the right thing to hand back. Only a real failure throws.
    static func run(text: String, mode: ProcessingMode) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw IntentFailure.noText
        }

        guard let configuration = AppIntentsContext.configuration else {
            throw IntentFailure.engineUnavailable("the app has not finished launching")
        }
        let invocation: EngineInvocation
        do {
            invocation = try EngineInvocation.makeTextRun(
                configuration: configuration,
                text: trimmed,
                mode: mode,
                cleaner: selectedCleaner(configuration),
                engineSourceRoot: AppIntentsContext.engineSourceRoot,
                appleCleanerURL: EngineRunner.appleCleanerURL
            )
        } catch let refusal as TextRunRefusal {
            throw IntentFailure.refused(refusal.message)
        }

        let process = Process()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.currentDirectoryURL
        process.environment = invocation.environment

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw IntentFailure.engineUnavailable(error.localizedDescription)
        }
        if let data = invocation.standardInput?.data(using: .utf8) {
            input.fileHandleForWriting.write(data)
        }
        input.fileHandleForWriting.closeFile()

        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        // 0 delivered, 2 delivered the deterministic text after a refused cleanup.
        guard process.terminationStatus == 0 || process.terminationStatus == 2 else {
            let detail = String(data: stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw IntentFailure.engineFailed(detail.isEmpty ? "The engine failed." : detail)
        }

        guard
            let payload = try? JSONSerialization.jsonObject(with: stdout) as? [String: Any],
            let final = payload["final_text"] as? String,
            !final.isEmpty
        else {
            throw IntentFailure.engineFailed("The engine returned nothing usable.")
        }
        return final
    }
}

@available(macOS 13.0, *)
enum IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    case noText
    case refused(String)
    case engineUnavailable(String)
    case engineFailed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noText:
            return "There was no text to work on."
        case .refused(let reason):
            return "\(reason)"
        case .engineUnavailable(let detail):
            return "VoiceFlow's engine could not be started: \(detail)"
        case .engineFailed(let detail):
            return "VoiceFlow could not finish: \(detail)"
        }
    }
}

/// The launch configuration and engine location, handed over by the app at startup.
///
/// An intent can run while the app is not in front, and it needs the same project root
/// and engine sources a dictation uses. The delegate sets this once; an intent that
/// arrives before launch has finished is refused with that reason rather than crashing.
@available(macOS 13.0, *)
enum AppIntentsContext {
    nonisolated(unsafe) static var configuration: VoiceFlowConfiguration? = nil
    nonisolated(unsafe) static var engineSourceRoot: URL?
}

@available(macOS 13.0, *)
struct CleanTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Clean Up Text"
    static var description = IntentDescription(
        "Removes fillers and adds punctuation without changing the words. Anything that changes more is refused and your own text comes back."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Text")
    var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: try IntentEngine.run(text: text, mode: .clean))
    }
}

@available(macOS 13.0, *)
struct TranslateTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate to English"
    static var description = IntentDescription(
        "Turns Spanish or mixed speech into professional US English, keeping names, numbers, URLs and code."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Text")
    var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: try IntentEngine.run(text: text, mode: .translate))
    }
}

@available(macOS 13.0, *)
struct MeetingNotesIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn Into Meeting Notes"
    static var description = IntentDescription(
        "Structures text into summary bullets and a checklist of action items, in the language it was written in."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Text")
    var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: try IntentEngine.run(text: text, mode: .meeting))
    }
}

/// The phrases Siri accepts without the speaker opening Shortcuts first.
///
/// `${applicationName}` is what Siri needs in order to know which app is meant, so each
/// phrase carries it. Four is the shape: one obvious phrase per intent, rather than a
/// list that competes with itself for the same words.
@available(macOS 13.0, *)
struct VoiceFlowShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CleanTextIntent(),
            phrases: ["Clean up this text with ${applicationName}"],
            shortTitle: "Clean Up Text",
            systemImageName: "text.badge.checkmark"
        )
        AppShortcut(
            intent: TranslateTextIntent(),
            phrases: ["Translate this to English with ${applicationName}"],
            shortTitle: "Translate to English",
            systemImageName: "character.bubble"
        )
        AppShortcut(
            intent: MeetingNotesIntent(),
            phrases: ["Turn this into meeting notes with ${applicationName}"],
            shortTitle: "Meeting Notes",
            systemImageName: "list.bullet.clipboard"
        )
    }
}
