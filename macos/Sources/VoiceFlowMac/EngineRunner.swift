import Foundation
import VoiceFlowMacCore

enum EngineRunnerError: LocalizedError {
    case launchFailed
    case engineFailed(Int32, String)
    case emptyResult
    case invalidResult
    case timedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .launchFailed:
            return "The local dictation engine could not start."
        case .engineFailed(let code, let detail):
            return detail.isEmpty
                ? "The local dictation engine failed with status \(code)."
                : "The local dictation engine failed with status \(code): \(detail)"
        case .emptyResult:
            return "The local dictation engine returned no text."
        case .invalidResult:
            return "The local dictation engine returned an invalid result."
        case .timedOut(let seconds):
            return String(
                format: "The local dictation engine did not finish within %.0f seconds.",
                seconds
            )
        }
    }
}

enum EngineOutcome: Equatable {
    case cleaned
    /// The cleanup did not survive, and the deterministic transcript was delivered
    /// instead. Which side refused matters: a guard rejection means the sentence was
    /// restructured too far to be verified, and a provider failure means the request
    /// never came back. They call for opposite responses from the speaker.
    case safeFallback(FallbackReason)
}

enum FallbackReason: String, Equatable {
    /// The provider answered, and the conservative guard refused what it returned.
    case guardRejected = "guard"
    /// The provider itself failed: busy, unreachable, or out of time.
    case providerFailed = "provider"

    /// What to tell the speaker, in the words that change what they would do next.
    var summary: String {
        switch self {
        case .guardRejected:
            return "the cleanup changed too much to verify"
        case .providerFailed:
            return "the provider did not answer"
        }
    }
}

struct EngineResult: Equatable {
    let outcome: EngineOutcome
    let rawText: String
    let personalizedText: String
    let finalText: String
    /// The cloud model that actually produced the text. Absent for local cleanup and
    /// for a run that fell back, so the interface never names a model that stayed
    /// silent.
    let model: String?
    /// Seconds the engine spent in speech recognition and in cleanup, as measured by
    /// the run that produced this text. `nil` means the engine reported no
    /// measurement, and the interface must then show none: the only honest source of
    /// a latency figure is this field.
    let transcribeSeconds: Double?
    let cleanupSeconds: Double?
    /// What the provider returned when the guard refused it. Kept so the speaker can
    /// see the cleanup that was rejected on their behalf and take it if it is fine.
    let rejectedText: String?

    /// Whether the cleanup was replaced by the deterministic transcript, and why.
    var fallbackReason: FallbackReason? {
        if case .safeFallback(let reason) = outcome { return reason }
        return nil
    }

    var usedFallback: Bool { fallbackReason != nil }

    init(
        outcome: EngineOutcome,
        rawText: String,
        personalizedText: String,
        finalText: String,
        model: String?,
        transcribeSeconds: Double? = nil,
        cleanupSeconds: Double? = nil,
        rejectedText: String? = nil
    ) {
        self.outcome = outcome
        self.rawText = rawText
        self.personalizedText = personalizedText
        self.finalText = finalText
        self.model = model
        self.transcribeSeconds = transcribeSeconds
        self.cleanupSeconds = cleanupSeconds
        self.rejectedText = rejectedText
    }
}

private struct EnginePayload: Decodable {
    let rawText: String
    let personalizedText: String
    let finalText: String
    let model: String?
    let timings: EngineTimings?
    let fallbackReason: String?
    let rejectedText: String?

    private enum CodingKeys: String, CodingKey {
        case rawText = "raw_text"
        case personalizedText = "personalized_text"
        case finalText = "final_text"
        case model
        case timings
        case fallbackReason = "fallback_reason"
        case rejectedText = "rejected_text"
    }
}

private struct EngineTimings: Decodable {
    let transcribeSeconds: Double?
    let cleanupSeconds: Double?

    private enum CodingKeys: String, CodingKey {
        case transcribeSeconds = "transcribe_seconds"
        case cleanupSeconds = "cleanup_seconds"
    }
}

final class EngineRunner {
    /// Last-resort watchdog. Each engine stage carries its own shorter limit, so this
    /// only fires when a stage stops honouring its own timeout.
    static let timeout: TimeInterval = 180

    /// The Apple cleanup helper, beside this executable, or nil when this build has none.
    ///
    /// Checked for existence rather than assumed: a build made before the helper existed
    /// would otherwise hand the engine a path to nothing, and the engine would report a
    /// missing binary instead of simply falling back to its own lookup.
    static let appleCleanerURL: URL? = {
        guard let executable = Bundle.main.executableURL else { return nil }
        let candidate = executable
            .deletingLastPathComponent()
            .appendingPathComponent("voiceflow-apple-cleaner")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }()

    /// The Parakeet helper beside this executable, or nil when this build has none.
    static let parakeetHelperURL: URL? = {
        guard let executable = Bundle.main.executableURL else { return nil }
        let candidate = executable
            .deletingLastPathComponent()
            .appendingPathComponent("voiceflow-parakeet")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }()

    private let configuration: VoiceFlowConfiguration
    private let engineSourceRoot: URL

    init(configuration: VoiceFlowConfiguration, engineSourceRoot: URL) {
        self.configuration = configuration
        self.engineSourceRoot = engineSourceRoot
    }

    func process(
        audioURL: URL,
        cleaner: CleanerMode? = nil,
        mode: ProcessingMode? = nil,
        geminiModel: GeminiModel? = nil,
        apiKey: String? = nil,
        appName: String? = nil,
        recordDistillationPair: Bool = false,
        speechEngine: SpeechEngine = .whisper
    ) throws -> EngineResult {
        // The helper sits beside this executable inside the bundle. Resolved once and
        // only when it is really there, so a build without it simply leaves the engine
        // with its own default instead of pointing at a path that does not exist.
        let invocation = EngineInvocation.make(
            configuration: configuration,
            audioURL: audioURL,
            baseEnvironment: ProcessInfo.processInfo.environment,
            cleaner: cleaner,
            mode: mode,
            geminiModel: geminiModel,
            providerAPIKey: apiKey,
            engineSourceRoot: engineSourceRoot,
            appName: appName,
            recordDistillationPair: recordDistillationPair,
            appleCleanerURL: Self.appleCleanerURL,
            speechEngine: speechEngine,
            parakeetHelperURL: Self.parakeetHelperURL
        )
        return try run(invocation)
    }

    /// One Words command. A read returns the snapshot; a change returns nil, or throws
    /// with what the engine said when it refused — the single-word confirmation, a pair
    /// with a side missing — so the window can show that sentence rather than a status.
    func words(_ command: WordsCommand) throws -> WordsSnapshot? {
        let invocation = EngineInvocation.makeWordsRun(
            configuration: configuration,
            command: command,
            engineSourceRoot: engineSourceRoot
        )
        let (status, output, detail) = try execute(invocation)
        guard status == 0 else {
            throw EngineRunnerError.engineFailed(status, detail)
        }
        guard command == .read else { return nil }
        guard let snapshot = try? JSONDecoder().decode(WordsSnapshot.self, from: output) else {
            throw EngineRunnerError.invalidResult
        }
        return snapshot
    }

    /// Run one engine invocation to completion and read its reply.
    private func run(_ invocation: EngineInvocation) throws -> EngineResult {
        let (status, output, detail) = try execute(invocation)

        guard let text = String(data: output, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if status != 0 {
                throw EngineRunnerError.engineFailed(status, detail)
            }
            throw EngineRunnerError.emptyResult
        }

        var outcome: EngineOutcome
        switch status {
        case 0: outcome = .cleaned
        case 2: outcome = .safeFallback(.providerFailed)  // refined from the payload below
        default: throw EngineRunnerError.engineFailed(status, detail)
        }

        guard let payload = try? JSONDecoder().decode(EnginePayload.self, from: output) else {
            throw EngineRunnerError.invalidResult
        }
        if case .safeFallback = outcome {
            // An older engine sends no reason. Treating a missing field as a provider
            // failure is the safer default: it never blames the speaker's sentence for
            // something the network did.
            outcome = .safeFallback(
                payload.fallbackReason.flatMap(FallbackReason.init(rawValue:))
                    ?? .providerFailed
            )
        }
        return EngineResult(
            outcome: outcome,
            rawText: payload.rawText,
            personalizedText: payload.personalizedText,
            finalText: payload.finalText,
            model: payload.model,
            transcribeSeconds: payload.timings?.transcribeSeconds,
            cleanupSeconds: payload.timings?.cleanupSeconds,
            rejectedText: payload.rejectedText
        )
    }

    /// Start one engine process, feed it, drain it under the watchdog, and hand back its
    /// exit status, its standard output and the tail of what it said on standard error.
    private func execute(_ invocation: EngineInvocation) throws -> (Int32, Data, String) {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.currentDirectoryURL
        process.environment = invocation.environment
        process.standardOutput = standardOutput
        process.standardError = standardError

        let standardInput = Pipe()
        if invocation.standardInput != nil {
            process.standardInput = standardInput
        }

        do {
            try process.run()
        } catch {
            throw EngineRunnerError.launchFailed
        }

        if let text = invocation.standardInput {
            DispatchQueue.global(qos: .userInitiated).async {
                let handle = standardInput.fileHandleForWriting
                if let data = text.data(using: .utf8) {
                    try? handle.write(contentsOf: data)
                }
                try? handle.close()
            }
        }

        // Drain both pipes while the child is still running. Waiting for exit first
        // deadlocks parent and child as soon as either pipe buffer fills.
        var output = Data()
        var errorOutput = Data()
        let drain = DispatchGroup()
        let drainQueue = DispatchQueue(
            label: "dot.sanblue.voiceflow.engine-drain",
            attributes: .concurrent
        )
        drainQueue.async(group: drain) {
            output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        }
        drainQueue.async(group: drain) {
            errorOutput = standardError.fileHandleForReading.readDataToEndOfFile()
        }

        if drain.wait(timeout: .now() + Self.timeout) == .timedOut {
            process.terminate()
            _ = drain.wait(timeout: .now() + 5)
            process.waitUntilExit()
            throw EngineRunnerError.timedOut(Self.timeout)
        }
        process.waitUntilExit()

        let detail = String(data: errorOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .suffix(400)
            .description ?? ""
        return (process.terminationStatus, output, detail)
    }
}
