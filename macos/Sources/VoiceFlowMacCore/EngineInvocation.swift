import Foundation

public struct EngineInvocation: Equatable, Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let currentDirectoryURL: URL
    public let environment: [String: String]

    /// Text written to the child's standard input, or `nil` when the run sends none.
    ///
    /// A dictation sends none. An App Intent's text travels here rather than in
    /// `arguments`, because a process argument is not private: `ps -ww -ax` prints the
    /// full command line of every process the same user runs.
    public let standardInput: String?

    /// Build one engine run.
    ///
    /// `cleaner` overrides the launch configuration so the window's provider choice
    /// takes effect without restarting the app. `providerAPIKey` is placed in the child
    /// environment and only for a cloud cleaner, so a local run never carries a secret
    /// it has no use for.
    ///
    /// `mode` reaches the engine as `engineMode`, not as its own name. `actions` is an
    /// application mode: the engine cleans the transcript as usual and the spoken command
    /// is recognized here, from the text it returns.
    ///
    /// `recordDistillationPair` defaults to false and adds `--distill` only when the
    /// speaker turned the setting on. Keeping dictated text on disk is a decision, so
    /// the flag is absent from an ordinary run rather than implied by cloud cleanup.
    public static func make(
        configuration: VoiceFlowConfiguration,
        audioURL: URL,
        baseEnvironment: [String: String],
        cleaner: CleanerMode? = nil,
        mode: ProcessingMode? = nil,
        geminiModel: GeminiModel? = nil,
        providerAPIKey: String? = nil,
        engineSourceRoot: URL? = nil,
        appName: String? = nil,
        recordDistillationPair: Bool = false,
        appleCleanerURL: URL? = nil,
        speechEngine: SpeechEngine = .whisper,
        parakeetHelperURL: URL? = nil
    ) -> EngineInvocation {
        let selectedCleaner = cleaner ?? configuration.cleaner
        let selectedMode = mode ?? configuration.mode
        // The window's model choice overrides the launch configuration, so switching
        // model takes effect on the next dictation without restarting the app.
        let selectedGeminiModel = geminiModel?.rawValue ?? configuration.geminiModel
        var environment = baseEnvironment
        environment["PYTHONPATH"] = (
            engineSourceRoot
                ?? configuration.projectRoot.appendingPathComponent("src", isDirectory: true)
        ).path
        // A packaged app executes source from its signed Resources directory. Python
        // bytecode caches would mutate that directory after signing, so disable them.
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        // The app is the sole keychain authority for its child. This prevents the
        // Python terminal fallback from silently using a key the interface could not
        // read or did not explicitly inject.
        environment["VOICEFLOW_DISABLE_KEYCHAIN_FALLBACK"] = "1"
        let inheritedPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(inheritedPath)"

        // Do not trust the parent process environment for credentials. Strip every
        // VoiceFlow provider-key variable, including variables for providers a future
        // release may add, then inject only the selected key read explicitly from this
        // app's keychain.
        for name in Array(environment.keys)
        where name.hasPrefix("VOICEFLOW_") && name.hasSuffix("_API_KEY") {
            environment.removeValue(forKey: name)
        }
        if selectedCleaner.isCloud,
           let providerAPIKey,
           !providerAPIKey.isEmpty {
            environment[selectedCleaner.apiKeyVariable] = providerAPIKey
        }

        var arguments = [
            "python3",
            "-m", "sanbluedot_voiceflow",
            "process", audioURL.path,
            "--whisper-bin", configuration.whisperBinary,
            "--whisper-model", configuration.whisperModel.path,
            "--language", configuration.language.rawValue,
            "--cleaner", selectedCleaner.rawValue,
            "--mode", selectedMode.engineMode,
            "--gemini-model", selectedGeminiModel,
            "--copy",
            "--json",
        ]
        // Named on every run, so the engine never falls back to a default the window
        // does not show.
        arguments.append(contentsOf: ["--transcriber", speechEngine.rawValue])
        if speechEngine == .parakeet {
            arguments.append(contentsOf: ["--parakeet-models", configuration.parakeetModels.path])
            // The helper sits beside the app's own executable, on no PATH the child searches.
            if let parakeetHelperURL {
                arguments.append(contentsOf: ["--parakeet-bin", parakeetHelperURL.path])
            }
        }
        if let appName, !appName.isEmpty {
            arguments.append("--app-name=\(appName)")
        }
        if recordDistillationPair {
            arguments.append("--distill")
        }
        // Apple's model is reached through a helper the engine runs, so the engine has to
        // be told where it is. A packaged app carries it beside its own executable, and
        // that path is not on any PATH the child would search.
        if let appleCleanerURL {
            arguments.append(contentsOf: ["--apple-bin", appleCleanerURL.path])
        }

        return EngineInvocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: arguments,
            currentDirectoryURL: configuration.projectRoot,
            environment: environment,
            standardInput: nil
        )
    }

    /// Run `vf doctor --json` to inspect speech models, helpers and keychain credentials.
    public static func makeDoctorRun(
        configuration: VoiceFlowConfiguration,
        engineSourceRoot: URL? = nil
    ) -> EngineInvocation {
        let environment = textRunEnvironment(
            configuration: configuration,
            engineSourceRoot: engineSourceRoot
        )
        return EngineInvocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                "-m", "sanbluedot_voiceflow",
                "doctor",
                "--json",
            ],
            currentDirectoryURL: configuration.projectRoot,
            environment: environment,
            standardInput: nil
        )
    }

    /// One run over text that was never spoken to this machine.
    ///
    /// A shortcut hands over text that was written rather than dictated, so there is no
    /// recording: the engine's `clean` subcommand enters the pipeline after
    /// transcription and the text travels on standard input, because `ps -ww -ax`
    /// publishes arguments to every process the user runs and this is her document.
    ///
    /// framework.md R3d draws the rest. `--no-memory` keeps confirmed corrections and
    /// snippets off the text, because they repair and expand speech. A cloud engine is
    /// refused rather than run, because a shortcut shows nothing on screen that would say
    /// the text is leaving this Mac; no key is ever placed in this environment.
    public static func makeTextRun(
        configuration: VoiceFlowConfiguration,
        text: String,
        mode: ProcessingMode,
        cleaner: CleanerMode? = nil,
        engineSourceRoot: URL? = nil,
        appleCleanerURL: URL? = nil
    ) throws -> EngineInvocation {
        let selectedCleaner = cleaner ?? configuration.cleaner
        guard !selectedCleaner.isCloud else {
            throw TextRunRefusal.cloudEngine(selectedCleaner)
        }
        let environment = textRunEnvironment(
            configuration: configuration,
            engineSourceRoot: engineSourceRoot
        )

        var arguments = [
            "python3",
            "-m", "sanbluedot_voiceflow",
            "clean",
            "--mode", mode.engineMode,
            "--cleaner", selectedCleaner.rawValue,
            "--no-memory",
            "--json",
        ]
        if let appleCleanerURL {
            arguments.append(contentsOf: ["--apple-bin", appleCleanerURL.path])
        }

        return EngineInvocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: arguments,
            currentDirectoryURL: configuration.projectRoot,
            environment: environment,
            standardInput: text
        )
    }

    /// One Words command: read the vocabulary and corrections, or change one of them.
    ///
    /// The engine owns both stores — their locks, their atomic writes and the single-word
    /// confirmation — so the window asks it rather than writing the files itself, and a
    /// pair confirmed here is the same pair `vf correct` would have stored.
    public static func makeWordsRun(
        configuration: VoiceFlowConfiguration,
        command: WordsCommand,
        engineSourceRoot: URL? = nil
    ) -> EngineInvocation {
        EngineInvocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["python3", "-m", "sanbluedot_voiceflow"] + command.arguments,
            currentDirectoryURL: configuration.projectRoot,
            environment: textRunEnvironment(
                configuration: configuration,
                engineSourceRoot: engineSourceRoot
            ),
            standardInput: nil
        )
    }

    /// The child environment every text run shares: the engine source on the path, no
    /// bytecode written into a signed bundle, no keychain fallback, and no provider key
    /// inherited from the parent.
    private static func textRunEnvironment(
        configuration: VoiceFlowConfiguration,
        engineSourceRoot: URL?
    ) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONPATH"] = (
            engineSourceRoot
                ?? configuration.projectRoot.appendingPathComponent("src", isDirectory: true)
        ).path
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["VOICEFLOW_DISABLE_KEYCHAIN_FALLBACK"] = "1"
        let inheritedPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(inheritedPath)"
        for name in Array(environment.keys)
        where name.hasPrefix("VOICEFLOW_") && name.hasSuffix("_API_KEY") {
            environment.removeValue(forKey: name)
        }
        return environment
    }
}

/// Why a text run was not built.
public enum TextRunRefusal: Error, Equatable {
    /// The engine chosen in the window sends text off this Mac; a shortcut refuses it.
    case cloudEngine(CleanerMode)

    /// What the shortcut tells the speaker, in the words that change what she does next.
    public var message: String {
        switch self {
        case .cloudEngine(let cleaner):
            return "VoiceFlow's shortcuts run only on this Mac, and the engine chosen in "
                + "VoiceFlow is \(cleaner.shortName), which sends text to the cloud. "
                + "Choose Apple in VoiceFlow, then run the shortcut again."
        }
    }
}
