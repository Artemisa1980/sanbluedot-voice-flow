import FluidAudio
import Foundation

/// The speech adapter for Parakeet Ultra, invoked by the Python engine.
///
/// The engine owns the pipeline and reaches whisper.cpp and Apple's model the same way: by
/// running a binary and reading what it prints. Parakeet runs through FluidAudio on the
/// Neural Engine, which is Swift-only, so it arrives through that same door.
///
/// Contract, so the Python side can depend on it:
///   voiceflow-parakeet --models DIR AUDIO   stdout: {"text": "..."} · status 0
///   voiceflow-parakeet --models DIR --download   fetches the model into DIR · status 0
///   status 2 — the model is not in DIR yet · 1 — anything else · the reason on stderr
///
/// Nothing is downloaded during a dictation. A missing model is reported, and fetching it
/// is a separate, explicit run.
enum ExitStatus: Int32 {
    case delivered = 0
    case failed = 1
    case modelMissing = 2
}

func fail(_ message: String, _ status: ExitStatus) -> Never {
    try? FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
    exit(status.rawValue)
}

func emit(_ text: String) {
    // Encoded rather than interpolated: a transcript may carry quotes or backslashes.
    guard let data = try? JSONEncoder().encode(["text": text]) else {
        fail("The transcript could not be encoded.", .failed)
    }
    try? FileHandle.standardOutput.write(contentsOf: data)
    try? FileHandle.standardOutput.write(contentsOf: Data("\n".utf8))
}

@main
struct ParakeetHelper {
    static func main() async {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let flag = arguments.firstIndex(of: "--models"), flag + 1 < arguments.count else {
            fail("Usage: voiceflow-parakeet --models DIR (AUDIO | --download)", .failed)
        }
        let models = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        arguments.removeSubrange(flag...(flag + 1))

        if arguments == ["--download"] {
            do {
                try await AsrModels.download(to: models, version: .ultra)
                exit(ExitStatus.delivered.rawValue)
            } catch {
                fail("Parakeet Ultra could not be downloaded: \(error.localizedDescription)", .failed)
            }
        }

        guard arguments.count == 1 else {
            fail("Usage: voiceflow-parakeet --models DIR (AUDIO | --download)", .failed)
        }
        let audio = URL(fileURLWithPath: arguments[0])
        guard AsrModels.modelsExist(at: models, version: .ultra) else {
            fail("Parakeet Ultra is not at \(models.path). Fetch it once with --download.", .modelMissing)
        }

        // Files that exist are not enough: on a revision mismatch or any load error
        // FluidAudio deletes the model folder and downloads it again, inside a dictation.
        // Offline mode turns that into an ordinary failure and leaves the folder alone.
        ModelHub.offlineMode = true
        do {
            let loaded = try await AsrModels.load(from: models, version: .ultra)
            let manager = AsrManager()
            try await manager.loadModels(loaded)
            var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
            // A script filter, not a language lock. Parakeet chooses among 25 languages,
            // Russian and Ukrainian among them, and wrote English in Cyrillic on the
            // owner's corpus. Spanish and English share the Latin script, so a sentence
            // that mixes them stays mixed and only the Cyrillic tokens are refused.
            let result = try await manager.transcribe(audio, decoderState: &state, language: .spanish)
            emit(result.text)
            exit(ExitStatus.delivered.rawValue)
        } catch {
            fail("Parakeet could not transcribe: \(error.localizedDescription)", .failed)
        }
    }
}
