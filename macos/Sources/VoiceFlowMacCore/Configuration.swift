import Foundation

public enum ProviderCredentialEnvironment {
    public static func variableName(for provider: String) -> String {
        let normalized = provider.uppercased().replacingOccurrences(of: "-", with: "_")
        return "VOICEFLOW_\(normalized)_API_KEY"
    }
}

public enum ConfigurationError: LocalizedError, Equatable {
    case missingValue(String)
    case unknownOption(String)
    case invalidCleaner(String)
    case invalidMode(String)
    case invalidLanguage(String)
    case invalidShortcut(String)
    case shortcutConflict(String)
    case modifierOnlyModeShortcut(String)
    case invalidHoldDelay(String)

    public var errorDescription: String? {
        switch self {
        case .missingValue(let option):
            return "Missing value for \(option)."
        case .unknownOption(let option):
            return "Unknown option: \(option)."
        case .invalidCleaner(let cleaner):
            return "Unsupported cleaner: \(cleaner)."
        case .invalidMode(let mode):
            return "Unsupported mode: \(mode). Use clean, translate, meeting, actions, or transform."
        case .invalidLanguage(let language):
            return "Unsupported language: \(language)."
        case .invalidShortcut(let shortcut):
            return "Invalid shortcut: \(shortcut). Use fn alone or a modifier plus a supported key."
        case .shortcutConflict(let shortcut):
            return "\(shortcut) is already the push-to-talk shortcut. Give --mode-shortcut a different chord."
        case .invalidHoldDelay(let value):
            return "Invalid hold delay: \(value). Give a number of seconds between 0 and 3."
        case .modifierOnlyModeShortcut(let shortcut):
            return "\(shortcut) is a modifier by itself. The mode switch is tapped, not held, "
                + "so --mode-shortcut needs a modifier plus a key, such as control+option+m."
        }
    }
}

public enum CleanerMode: String, CaseIterable, Sendable {
    case literal
    case ollama
    case gemini

    /// Whether choosing this cleaner sends the transcript off the device.
    public var isCloud: Bool {
        // Keep this exhaustive: adding a provider must make an explicit privacy
        // classification before the project can compile.
        switch self {
        case .literal, .ollama:
            return false
        case .gemini:
            return true
        }
    }

    /// The environment variable the engine reads this provider's key from. The app
    /// owns the keychain item and injects the key here, so the engine never triggers a
    /// keychain prompt in the middle of a dictation.
    public var apiKeyVariable: String {
        ProviderCredentialEnvironment.variableName(for: rawValue)
    }

    public var displayName: String {
        switch self {
        case .literal:
            return "Literal — no cleanup"
        case .ollama:
            return "Local cleanup — Ollama"
        case .gemini:
            return "Gemini — cloud, text only"
        }
    }

    /// Where a speaker obtains this provider's credential. The exhaustive switch makes
    /// a future provider supply an accurate disclosure before it can compile.
    public var apiKeySourceName: String? {
        switch self {
        case .literal, .ollama:
            return nil
        case .gemini:
            return "Google AI Studio"
        }
    }
}

/// The Gemini models the window offers, listed newest first for the picker.
///
/// A model is listed here only after it has been measured against the live endpoint on
/// the same request shape. Display order is by version because that is how a person
/// scans a picker; the fallback order is `fallbackOrder`, by measured delivery.
public enum GeminiModel: String, CaseIterable, Sendable {
    case flash37 = "gemini-3.7-flash"
    case flash36 = "gemini-3.6-flash"
    case flash35 = "gemini-3.5-flash"

    public static let preferredDefault = GeminiModel.flash35

    /// The order the engine walks on a capacity error, by measured delivery rather than
    /// by version. Mirrors `MODEL_CHAIN` in `cleaners/gemini.py`, which is the authority;
    /// this copy exists only so the window can show the real order. `VoiceFlowMacCoreChecks`
    /// asserts the two stay the same size and content.
    public static let fallbackOrder: [GeminiModel] = [.flash35, .flash36, .flash37]

    /// Short label for the picker. The full identifier is the `rawValue`.
    public var shortName: String {
        switch self {
        case .flash37: return "3.7"
        case .flash36: return "3.6"
        case .flash35: return "3.5"
        }
    }

    /// When the figures below were taken.
    ///
    /// Shown beside them because nothing re-measures: the numbers are a photograph, and
    /// a picker that presents a dated measurement as a current fact recommends a model
    /// that may no longer be the one that answers. Re-measure with
    /// `scripts/cleaner_gate.py --cleaner gemini` and update this date with the figures.
    public static let measurementDate = "2026-08-31"

    /// Delivery measured on 2026-08-31, interleaved, identical output quality.
    /// Shown in the window so the choice is informed rather than a guess.
    public var measuredNote: String {
        switch self {
        case .flash37: return "3/6 · 12.5s"
        case .flash36: return "4/6 · 14.3s"
        case .flash35: return "5/6 · 2.3s"
        }
    }
}

public enum ProcessingMode: String, CaseIterable, Sendable {
    case clean
    case translate
    case meeting
    case actions
    case transform

    public var displayName: String {
        switch self {
        case .clean:
            return "Clean (Conservative)"
        case .translate:
            return "Translate (ES ➔ EN)"
        case .meeting:
            return "Meeting Notes & Action Items"
        case .actions:
            return "Voice Actions (macOS)"
        case .transform:
            return "Transform Selection"
        }
    }

    /// The badge the HUD and the mode switch show. Short enough to read at a glance
    /// while the speaker is already talking.
    public var badgeName: String {
        switch self {
        case .clean: return "CLEAN"
        case .translate: return "ES➔EN"
        case .meeting: return "NOTES"
        case .actions: return "ACTION"
        case .transform: return "TRANSFORM"
        }
    }

    /// The value the Python engine accepts for `--mode`.
    ///
    /// `actions` is an application mode, not an engine mode: the engine transcribes and
    /// cleans as usual and the parsing happens here, against the returned text. Sending
    /// the raw name instead made the engine reject the whole run with an argparse error,
    /// so every dictation failed while ACTION was selected.
    public var engineMode: String {
        switch self {
        case .clean, .actions: return "clean"
        case .translate: return "translate"
        case .meeting: return "meeting"
        case .transform: return "transform"
        }
    }

    /// Whether a dictation in this mode is examined for a spoken system command.
    ///
    /// R3c: only the mode the speaker selected for it. Parsing every dictation meant a
    /// sentence that merely began like an instruction was executed instead of written.
    public var parsesVoiceActions: Bool {
        switch self {
        case .actions: return true
        case .clean, .translate, .meeting, .transform: return false
        }
    }

    /// The next mode in the HUD toggle, wrapping at the end of `allCases`.
    public var next: ProcessingMode {
        let all = ProcessingMode.allCases
        guard let index = all.firstIndex(of: self) else { return .clean }
        return all[(index + 1) % all.count]
    }
}

public enum LanguageMode: String, Sendable {
    case auto
    case en
    case es
}

public enum ShortcutModifier: String, CaseIterable, Hashable, Sendable {
    case command
    case control
    case option
    case shift
    case fn

    fileprivate var displayName: String {
        switch self {
        case .command: return "⌘"
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .fn: return "fn"
        }
    }
}

public struct Shortcut: Equatable, Sendable {
    public let modifiers: Set<ShortcutModifier>
    public let keyName: String
    public let keyCode: UInt16?

    public init(specification: String) throws {
        let parts = specification
            .lowercased()
            .split(separator: "+")
            .map(String.init)

        if parts == [ShortcutModifier.fn.rawValue] {
            modifiers = [.fn]
            keyName = ShortcutModifier.fn.rawValue
            keyCode = nil
            return
        }

        guard parts.count >= 2, let keyName = parts.last else {
            throw ConfigurationError.invalidShortcut(specification)
        }

        let modifierParts = parts.dropLast()
        var modifiers = Set<ShortcutModifier>()
        for part in modifierParts {
            guard let modifier = ShortcutModifier(rawValue: part) else {
                throw ConfigurationError.invalidShortcut(specification)
            }
            modifiers.insert(modifier)
        }

        guard !modifiers.isEmpty, let keyCode = Self.keyCodes[keyName] else {
            throw ConfigurationError.invalidShortcut(specification)
        }

        self.modifiers = modifiers
        self.keyName = keyName
        self.keyCode = keyCode
    }

    public var displayName: String {
        if keyCode == nil {
            return "Fn/Globe"
        }
        let order: [ShortcutModifier] = [.control, .option, .shift, .command, .fn]
        let prefix = order
            .filter(modifiers.contains)
            .map(\.displayName)
            .joined()
        return prefix + keyName.uppercased()
    }

    private static let keyCodes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5,
        "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37,
        "j": 38, "k": 40, "n": 45, "m": 46,
        "space": 49, "escape": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118,
        "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "f13": 105, "f14": 107, "f15": 113, "f16": 106,
        "f17": 64, "f18": 79, "f19": 80, "f20": 90,
    ]
}

public struct VoiceFlowConfiguration: Equatable, Sendable {
    public let projectRoot: URL
    public let whisperModel: URL
    public let whisperBinary: String
    public let cleaner: CleanerMode
    public let mode: ProcessingMode
    public let language: LanguageMode
    public let ollamaURL: String
    public let ollamaModel: String
    public let geminiModel: String
    public let shortcut: Shortcut
    /// The chord that advances the processing mode from the HUD, without opening the
    /// station window. Tapped rather than held: it is a switch, not a trigger.
    public let modeShortcut: Shortcut
    /// How long the trigger must be held before the microphone opens.
    ///
    /// The Fn key sits where a hand rests, and a brush against it used to open the
    /// microphone and record a dictation of nothing — one such take reached the history
    /// as a single full stop. Anything shorter than this never starts the recorder, so
    /// an accidental touch costs no recording and no indicator light. The cost is the
    /// speech in that window, which is why the default is short: nobody speaks in the
    /// first half second of pressing a key.
    public let holdDelaySeconds: TimeInterval
    public let acceptanceLog: URL?

    public static func parse(
        arguments: [String],
        currentDirectory: URL
    ) throws -> VoiceFlowConfiguration {
        var projectRootValue: String?
        var whisperModelValue: String?
        var whisperBinary = "whisper-cli"
        var cleaner = CleanerMode.literal
        var mode = ProcessingMode.clean
        var language = LanguageMode.auto
        var ollamaURL = "http://127.0.0.1:11434"
        var ollamaModel = "qwen3:4b"
        var geminiModel = "gemini-3.5-flash"
        var shortcut = try Shortcut(specification: "fn")
        var modeShortcut = try Shortcut(specification: "control+option+m")
        var holdDelaySeconds: TimeInterval = 0.5
        var acceptanceLogValue: String?

        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard index + 1 < arguments.count else {
                throw ConfigurationError.missingValue(option)
            }
            let value = arguments[index + 1]

            switch option {
            case "--project-root":
                projectRootValue = value
            case "--whisper-model":
                whisperModelValue = value
            case "--whisper-bin":
                whisperBinary = value
            case "--cleaner":
                guard let parsed = CleanerMode(rawValue: value) else {
                    throw ConfigurationError.invalidCleaner(value)
                }
                cleaner = parsed
            case "--mode":
                guard let parsed = ProcessingMode(rawValue: value) else {
                    throw ConfigurationError.invalidMode(value)
                }
                mode = parsed
            case "--language":
                guard let parsed = LanguageMode(rawValue: value) else {
                    throw ConfigurationError.invalidLanguage(value)
                }
                language = parsed
            case "--ollama-url":
                ollamaURL = value
            case "--ollama-model":
                ollamaModel = value
            case "--gemini-model":
                geminiModel = value
            case "--shortcut":
                shortcut = try Shortcut(specification: value)
            case "--mode-shortcut":
                modeShortcut = try Shortcut(specification: value)
            case "--hold-delay":
                guard let parsed = TimeInterval(value), parsed >= 0, parsed <= 3 else {
                    throw ConfigurationError.invalidHoldDelay(value)
                }
                holdDelaySeconds = parsed
            case "--acceptance-log":
                acceptanceLogValue = value
            default:
                throw ConfigurationError.unknownOption(option)
            }
            index += 2
        }

        // Two shortcuts on one keyboard. A chord that is both the trigger and the mode
        // switch would start a recording every time the speaker changed mode, so the
        // collision is refused at launch rather than discovered mid-dictation.
        guard modeShortcut != shortcut else {
            throw ConfigurationError.shortcutConflict(modeShortcut.displayName)
        }
        // The mode switch is a tap, and a modifier alone can only be held. Accepting one
        // here and dropping it later in `HotkeyMonitor` left the app running with the
        // switch silently dead while the menu bar still advertised the chord.
        guard modeShortcut.keyCode != nil else {
            throw ConfigurationError.modifierOnlyModeShortcut(modeShortcut.displayName)
        }

        let projectRoot = resolve(
            projectRootValue ?? currentDirectory.path,
            relativeTo: currentDirectory
        )
        let whisperModel = resolve(
            whisperModelValue ?? "models/ggml-large-v3-turbo.bin",
            relativeTo: projectRoot
        )
        let acceptanceLog = acceptanceLogValue.map {
            resolve($0, relativeTo: projectRoot)
        }

        return VoiceFlowConfiguration(
            projectRoot: projectRoot,
            whisperModel: whisperModel,
            whisperBinary: whisperBinary,
            cleaner: cleaner,
            mode: mode,
            language: language,
            ollamaURL: ollamaURL,
            ollamaModel: ollamaModel,
            geminiModel: geminiModel,
            shortcut: shortcut,
            modeShortcut: modeShortcut,
            holdDelaySeconds: holdDelaySeconds,
            acceptanceLog: acceptanceLog
        )
    }

    public static let help = """
    sanblueᵈᵒᵗ VoiceFlow macOS runner

    Options:
      --project-root PATH    Project root; defaults to the current directory.
      --whisper-model PATH   Model path; defaults to models/ggml-large-v3-turbo.bin.
      --whisper-bin NAME     whisper.cpp executable; defaults to whisper-cli.
      --cleaner MODE         literal, ollama, or gemini; defaults to literal.
      --mode MODE            clean, translate, meeting, or actions; defaults to clean.
      --language MODE        auto, en, or es; defaults to auto.
      --ollama-url URL       Ollama base URL.
      --ollama-model NAME    Ollama model; defaults to qwen3:4b.
      --gemini-model NAME    Gemini model; defaults to gemini-3.5-flash.
      --shortcut CHORD       Defaults to fn (the Fn/Globe key alone).
      --mode-shortcut CHORD  Cycles the mode from the HUD; defaults to control+option+m.
      --hold-delay SECONDS   Hold before the microphone opens; defaults to 0.5, max 3.
      --acceptance-log PATH  Append private Phase 2 results as JSON Lines.
    """

    private static func resolve(_ path: String, relativeTo base: URL) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return base.appendingPathComponent(expanded).standardizedFileURL
    }
}
