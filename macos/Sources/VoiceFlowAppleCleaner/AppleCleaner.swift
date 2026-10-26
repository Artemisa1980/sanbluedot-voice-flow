import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// The cleanup adapter for Apple's on-device model, invoked by the Python engine.
///
/// The engine owns the pipeline, the personalization and the output guard, and it reaches
/// `whisper-cli` the same way: by running a binary and reading what it prints. Apple's
/// model is Swift-only, so it arrives through that same door rather than by moving
/// cleanup into the application, which would put the step in two places and leave the
/// guard applying to only one of them.
///
/// The instruction text is not written here. `cleaners/prompt.py` holds the one
/// conservative instruction every provider receives, because two providers cannot be
/// compared on the same corpus if they are told different things. This binary is handed
/// that text and returns what the model answered, unchanged.
///
/// Contract, so the Python side can depend on it:
///   stdin  — one JSON object: {"instructions": "...", "prompt": "..."}
///   stdout — one JSON object: {"cleaned_text": "..."}
///   stderr — the reason, whenever the exit status is not 0
///   status — 0 delivered · 2 the model is unavailable on this Mac · 1 anything else
///
/// `--prewarm` reads nothing and prints nothing: it asks the system to load the model and
/// exits. The app runs it when the microphone opens, so the load happens while the
/// speaker is still talking instead of after the transcript is ready. A cold load cost
/// 2.1 s against 1.1 s warm on the same sentence, measured 2026-09-27.
///
/// Status 2 is separate because it is not a failure of the request: the speaker is on a
/// Mac that cannot run the model, or Apple Intelligence has not finished downloading it,
/// and the engine reports that rather than presenting it as a provider error.
enum ExitStatus: Int32 {
    case delivered = 0
    case failed = 1
    case modelUnavailable = 2
}

struct Request: Decodable {
    let instructions: String
    let prompt: String
}

func fail(_ message: String, _ status: ExitStatus) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(status.rawValue)
}

func readRequest() -> Request {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard let request = try? JSONDecoder().decode(Request.self, from: input) else {
        fail("The request could not be read: stdin must carry {\"instructions\", \"prompt\"}.", .failed)
    }
    guard !request.prompt.isEmpty else {
        fail("The request carried no prompt.", .failed)
    }
    return request
}

func emit(_ cleaned: String) {
    // Encoded rather than interpolated: the answer is arbitrary text and may carry
    // quotes, newlines or backslashes, any of which would break a hand-built string.
    guard var data = try? JSONEncoder().encode(["cleaned_text": cleaned]) else {
        fail("The answer could not be encoded.", .failed)
    }
    data.append(contentsOf: [0x0A])
    // `try? write(contentsOf:)`: the legacy `write(_:)` raised an uncatchable exception
    // when the engine had already gone (D-189).
    try? FileHandle.standardOutput.write(contentsOf: data)
}

#if canImport(FoundationModels)

/// The shape the model must return.
///
/// Guided generation is the reason this adapter is shorter than its siblings: the model
/// is constrained to this structure, so there is no fenced-code stripping and no second
/// JSON parse of a string the provider chose to format its own way.
@available(macOS 26.0, *)
@Generable
struct CleanedText {
    let cleanedText: String
}

@available(macOS 26.0, *)
func runOnDeviceModel(_ request: Request) async {
    switch SystemLanguageModel.default.availability {
    case .available:
        break
    case .unavailable(let reason):
        fail("Apple's on-device model is unavailable on this Mac: \(reason).", .modelUnavailable)
    }

    let session = LanguageModelSession(instructions: request.instructions)
    do {
        // Greedy and at temperature zero, matching the Ollama adapter. Left to its own
        // defaults the model paraphrased instead of cleaning — "este, las siguientes
        // pruebas" came back as "estas pruebas" — and the output guard refused the whole
        // result, which is correct and also means the speaker gets no cleanup at all.
        // Conservative cleanup is not a task that benefits from sampling.
        let response = try await session.respond(
            to: request.prompt,
            generating: CleanedText.self,
            options: GenerationOptions(samplingMode: .greedy, temperature: 0.0)
        )
        let cleaned = response.content.cleanedText
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail("Apple's on-device model returned empty text.", .failed)
        }
        emit(cleaned)
        exit(ExitStatus.delivered.rawValue)
    } catch {
        fail("Apple's on-device model failed: \(error.localizedDescription)", .failed)
    }
}

/// Load the model into the system and leave. The system keeps it, not this process.
@available(macOS 26.0, *)
func prewarmOnDeviceModel() async {
    guard case .available = SystemLanguageModel.default.availability else {
        exit(ExitStatus.modelUnavailable.rawValue)
    }
    LanguageModelSession().prewarm()
    // `prewarm` returns before the load finishes; leaving at once could drop the request
    // with the process. Two seconds is shorter than any dictation it runs beside.
    try? await Task.sleep(nanoseconds: 2_000_000_000)
    exit(ExitStatus.delivered.rawValue)
}

@main
struct AppleCleaner {
    static func main() async {
        guard #available(macOS 26.0, *) else {
            if CommandLine.arguments.contains("--prewarm") {
                exit(ExitStatus.modelUnavailable.rawValue)
            }
            _ = readRequest()
            fail("Apple's on-device model needs macOS 26 or newer.", .modelUnavailable)
        }
        if CommandLine.arguments.contains("--prewarm") {
            await prewarmOnDeviceModel()
        }
        let request = readRequest()
        await runOnDeviceModel(request)
    }
}

#else

@main
struct AppleCleaner {
    static func main() {
        if CommandLine.arguments.contains("--prewarm") {
            exit(ExitStatus.modelUnavailable.rawValue)
        }
        _ = readRequest()
        fail("This build has no FoundationModels framework, so Apple cleanup is unavailable.", .modelUnavailable)
    }
}

#endif
