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
    case modeNeedsRewritingCleaner(String)

    public var errorDescription: String? {
        switch self {
        case .missingValue(let option):
            return "Missing value for \(option)."
        case .unknownOption(let option):
            return "Unknown option: \(option)."
        case .invalidCleaner(let cleaner):
            return "Unsupported cleaner: \(cleaner)."
        case .invalidMode(let mode):
            return "Unsupported mode: \(mode). Use clean, translate, meeting, or actions."
        case .invalidLanguage(let language):
            return "Unsupported language: \(language)."
        case .invalidShortcut(let shortcut):
            return "Invalid shortcut: \(shortcut). Use fn alone or a modifier plus a supported key."
        case .shortcutConflict(let shortcut):
            return "\(shortcut) is already the push-to-talk shortcut. Give --mode-shortcut a different chord."
        case .invalidHoldDelay(let value):
            return "Invalid hold delay: \(value). Give a number of seconds between 0 and 3."
        case .modeNeedsRewritingCleaner(let refusal):
            return "\(refusal)."
        case .modifierOnlyModeShortcut(let shortcut):
            return "\(shortcut) is a modifier by itself. The mode switch is tapped, not held, "
                + "so --mode-shortcut needs a modifier plus a key, such as control+option+m."
        }
    }
}

public enum CleanerMode: String, CaseIterable, Sendable {
    case literal
    case apple
    case gemini

    /// Whether choosing this cleaner sends the transcript off the device.
    public var isCloud: Bool {
        // Keep this exhaustive: adding a provider must make an explicit privacy
        // classification before the project can compile.
        switch self {
        case .literal, .apple:
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

    /// The name on the engine button.
    ///
    /// `displayName` reads well in a sentence and does not fit in a row of four: the
    /// bank truncated it to "Literal…", "Local c…", "Local c…", "Gemini…", which made
    /// the two local engines indistinguishable from each other. The short name is the
    /// engine; `kindName` beside it is what choosing it means.
    public var shortName: String {
        switch self {
        case .literal: return "Literal"
        case .apple: return "Apple"
        case .gemini: return "Gemini"
        }
    }

    /// One word for where the text goes. The privacy fact, at a glance.
    public var kindName: String {
        switch self {
        case .literal: return "no cleanup"
        case .apple: return "on this Mac"
        case .gemini: return "cloud"
        }
    }

    public var displayName: String {
        switch self {
        case .literal:
            return "Literal — no cleanup"
        case .apple:
            return "Local cleanup — Apple"
        case .gemini:
            return "Gemini — cloud, text only"
        }
    }

    /// Where a speaker obtains this provider's credential. The exhaustive switch makes
    /// a future provider supply an accurate disclosure before it can compile.
    public var apiKeySourceName: String? {
        switch self {
        case .literal, .apple:
            return nil
        case .gemini:
            return "Google AI Studio"
        }
    }
}

/// Which local engine turns the recording into text. Both run on this Mac.
///
/// Whisper reads the vocabulary before it listens, and that prompt is what suppresses its
/// punctuation. Parakeet Ultra reads no vocabulary, writes its own punctuation and
/// capitals, and runs on the Neural Engine through FluidAudio.
public enum SpeechEngine: String, CaseIterable, Sendable {
    case whisper
    case parakeet

    public var shortName: String {
        switch self {
        case .whisper: return "Whisper turbo"
        case .parakeet: return "Parakeet Ultra"
        }
    }

    /// The name on the signal chain's speech stage.
    public var chainName: String {
        switch self {
        case .whisper: return "whisper turbo"
        case .parakeet: return "parakeet ultra"
        }
    }

    /// When the figures below were taken. Nothing re-measures, so they carry the date.
    public static let measurementDate = "2026-10-01"

    /// Word error and engine time on the owner's 19 recorded samples, the same corpus and
    /// confirmed corrections for both, `scripts/replay.py`, measured on `measurementDate`.
    public var measuredNote: String {
        switch self {
        case .whisper: return "10.6% · 2.37s"
        case .parakeet: return "9.3% · 0.24s"
        }
    }
}

/// The Gemini models the window offers.
///
/// `gemini-3.8-flash` is the preferred Flash model, and `gemini-4-argon` is available
/// for deeper cleanup and reasoning.
public enum GeminiModel: String, CaseIterable, Sendable {
    case flash38 = "gemini-3.8-flash"
    case argon4 = "gemini-4-argon"

    public static let preferredDefault = GeminiModel.flash38

    /// The order the engine walks on a capacity error. Mirrors `MODEL_CHAIN` in
    /// `cleaners/gemini.py`, which is the authority; this copy exists only so the window
    /// can show the real order. `VoiceFlowMacCoreChecks` asserts the two stay the same
    /// size and content.
    public static let fallbackOrder: [GeminiModel] = [.flash38, .argon4]

    /// Short label for the picker. The full identifier is the `rawValue`.
    public var shortName: String {
        switch self {
        case .flash38: return "3.8"
        case .argon4: return "Argon"
        }
    }

    /// When the figures below were taken; `nil` until the model is measured with
    /// `scripts/cleaner_gate.py --cleaner gemini`. Shown beside them because nothing
    /// re-measures, so a figure is a photograph of one day.
    public static let measurementDate: String? = nil

    /// Delivery and median time, once measured. Says so plainly until then, so the
    /// window never presents a guess as a measurement.
    public var measuredNote: String {
        switch self {
        case .flash38, .argon4: return "not measured yet"
        }
    }
}

public enum ProcessingMode: String, CaseIterable, Sendable {
    case clean
    case translate
    case meeting
    case actions

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
        }
    }

    /// The canonical short name shown on mode selector tiles in the station and Words (D-183).
    public var shortTitle: String {
        switch self {
        case .clean: return "CLEAN"
        case .translate: return "ES ➔ EN"
        case .meeting: return "NOTES"
        case .actions: return "ACTIONS"
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
        }
    }

    /// Whether this mode asks a model to rewrite the text.
    ///
    /// The literal cleaner returns what it was given, so each of these paired with it
    /// produced an ordinary dictation under a label promising otherwise: translate
    /// handed back the speaker's own Spanish under an English badge. The engine refuses the pairing in `cli.py`
    /// `REWRITING_MODES`, which is the authority; this copy exists so the interface can
    /// decline before a recording is spent, and `VoiceFlowMacCoreChecks` reads the
    /// engine's list and fails the build if the two drift apart.
    public var needsRewritingCleaner: Bool {
        switch self {
        case .translate, .meeting: return true
        case .clean, .actions: return false
        }
    }

    /// Why a dictation in this mode cannot run with this cleaner, or nil when it can.
    ///
    /// Five paths set one side or the other — the two mode banks, the ⌃⌥M cycle, the
    /// menu and the launch arguments — and only one of them checked, so the engine
    /// refused the run after the recording was spent (D-23). The press and the launch
    /// read this one rule instead.
    public func refusal(with cleaner: CleanerMode) -> String? {
        guard needsRewritingCleaner, cleaner == .literal else { return nil }
        return "\(badgeName) needs an engine that can rewrite text · pick local or cloud cleanup first"
    }

    /// Whether a dictation in this mode is examined for a spoken system command.
    ///
    /// R3c: only the mode the speaker selected for it. Parsing every dictation meant a
    /// sentence that merely began like an instruction was executed instead of written.
    public var parsesVoiceActions: Bool {
        switch self {
        case .actions: return true
        case .clean, .translate, .meeting: return false
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
        // Apple's on-device model, measured against the fixed corpus on 2026-09-26:
        // 18 of 19 accepted by the guard, punctuation F1 34.8% → 84.8%, 0.61s median.
        // Ollama held this place and reaches 34.8% → 48.0% on the same nineteen
        // recordings, which is why the default moved rather than staying on literal:
        // a cleanup step earns being on by measuring better than no cleanup at all.
        var cleaner = CleanerMode.apple
        var mode = ProcessingMode.clean
        var language = LanguageMode.auto
        var geminiModel = "gemini-3.8-flash"
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
        // `--cleaner literal --mode translate` would start an app whose every dictation
        // the engine refuses after recording it.
        if let refusal = mode.refusal(with: cleaner) {
            throw ConfigurationError.modeNeedsRewritingCleaner(refusal)
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
            geminiModel: geminiModel,
            shortcut: shortcut,
            modeShortcut: modeShortcut,
            holdDelaySeconds: holdDelaySeconds,
            acceptanceLog: acceptanceLog
        )
    }

    /// Where Parakeet Ultra lives: under the project's ignored `models/`, beside Whisper.
    public var parakeetModels: URL {
        projectRoot.appendingPathComponent("models/fluidaudio/parakeet-ultra", isDirectory: true)
    }

    public static let help = """
    sanblueᵈᵒᵗ VoiceFlow macOS runner

    Options:
      --project-root PATH    Project root; defaults to the current directory.
      --whisper-model PATH   Model path; defaults to models/ggml-large-v3-turbo.bin.
      --whisper-bin NAME     whisper.cpp executable; defaults to whisper-cli.
      --cleaner MODE         literal, apple, or gemini; defaults to apple.
      --mode MODE            clean, translate, meeting, or actions; defaults to clean.
      --language MODE        auto, en, or es; defaults to auto.
      --gemini-model NAME    Gemini model; defaults to gemini-3.8-flash.
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
