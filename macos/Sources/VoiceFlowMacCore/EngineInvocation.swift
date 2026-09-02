import Foundation

public struct EngineInvocation: Equatable, Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let currentDirectoryURL: URL
    public let environment: [String: String]

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
        recordDistillationPair: Bool = false
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
            "--ollama-url", configuration.ollamaURL,
            "--ollama-model", configuration.ollamaModel,
            "--gemini-model", selectedGeminiModel,
            "--copy",
            "--json",
        ]
        if recordDistillationPair {
            arguments.append("--distill")
        }

        return EngineInvocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: arguments,
            currentDirectoryURL: configuration.projectRoot,
            environment: environment
        )
    }
}
