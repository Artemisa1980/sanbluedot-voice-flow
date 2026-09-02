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
    case safeFallback
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

    init(
        outcome: EngineOutcome,
        rawText: String,
        personalizedText: String,
        finalText: String,
        model: String?,
        transcribeSeconds: Double? = nil,
        cleanupSeconds: Double? = nil
    ) {
        self.outcome = outcome
        self.rawText = rawText
        self.personalizedText = personalizedText
        self.finalText = finalText
        self.model = model
        self.transcribeSeconds = transcribeSeconds
        self.cleanupSeconds = cleanupSeconds
    }
}

private struct EnginePayload: Decodable {
    let rawText: String
    let personalizedText: String
    let finalText: String
    let model: String?
    let timings: EngineTimings?

    private enum CodingKeys: String, CodingKey {
        case rawText = "raw_text"
        case personalizedText = "personalized_text"
        case finalText = "final_text"
        case model
        case timings
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
        recordDistillationPair: Bool = false
    ) throws -> EngineResult {
        let invocation = EngineInvocation.make(
            configuration: configuration,
            audioURL: audioURL,
            baseEnvironment: ProcessInfo.processInfo.environment,
            cleaner: cleaner,
            mode: mode,
            geminiModel: geminiModel,
            providerAPIKey: apiKey,
            engineSourceRoot: engineSourceRoot,
            recordDistillationPair: recordDistillationPair
        )
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.currentDirectoryURL
        process.environment = invocation.environment
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            throw EngineRunnerError.launchFailed
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

        guard let text = String(data: output, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if process.terminationStatus != 0 {
                throw EngineRunnerError.engineFailed(process.terminationStatus, detail)
            }
            throw EngineRunnerError.emptyResult
        }

        let outcome: EngineOutcome
        switch process.terminationStatus {
        case 0: outcome = .cleaned
        case 2: outcome = .safeFallback
        default: throw EngineRunnerError.engineFailed(process.terminationStatus, detail)
        }

        guard let payload = try? JSONDecoder().decode(EnginePayload.self, from: output) else {
            throw EngineRunnerError.invalidResult
        }
        return EngineResult(
            outcome: outcome,
            rawText: payload.rawText,
            personalizedText: payload.personalizedText,
            finalText: payload.finalText,
            model: payload.model,
            transcribeSeconds: payload.timings?.transcribeSeconds,
            cleanupSeconds: payload.timings?.cleanupSeconds
        )
    }
}
