import AppKit
import Foundation
import VoiceFlowMacCore

enum VoiceFlowStatus {
    case idle
    case recording
    case processing
    case copied(
        TimeInterval,
        usedFallback: Bool,
        acceptanceCount: Int?,
        acceptanceError: String?,
        audioCleanupError: String?,
        /// The cloud model that produced the text. `nil` for local cleanup.
        model: String?,
        /// The mode this dictation actually ran in, captured when the shortcut was
        /// pressed. Reading the current selection instead would apply a mode the
        /// speaker switched to while the engine was still working.
        mode: ProcessingMode,
        result: EngineResult,
        /// How long the speaker actually held the shortcut and spoke. Speaking rate is
        /// words over this, never words over the processing time, which measures the
        /// machine rather than the speaker.
        spokenSeconds: TimeInterval
    )
    case failed(String)
}

final class VoiceFlowController {
    var onStatusChange: ((VoiceFlowStatus) -> Void)?

    /// The provider the window currently shows. Changing it takes effect on the next
    /// recording, so the speaker is never mid-dictation when the destination changes.
    private(set) var selectedCleaner: CleanerMode
    private(set) var selectedMode: ProcessingMode
    private(set) var selectedGeminiModel: GeminiModel

    func selectCleaner(_ cleaner: CleanerMode) {
        selectedCleaner = cleaner
    }

    func selectGeminiModel(_ model: GeminiModel) {
        selectedGeminiModel = model
    }

    func selectMode(_ mode: ProcessingMode) {
        selectedMode = mode
    }

    /// Whether this Mac keeps each cloud dictation as a local distillation pair.
    /// Off unless the speaker turned it on: the pairs are the spoken sentences
    /// themselves, so storing them is a choice, not a consequence of cloud cleanup.
    var recordDistillationPairs = false

    /// True when the selected cloud provider is ready to receive text.
    func hasAPIKey(for cleaner: CleanerMode) -> Bool {
        guard cleaner.isCloud else { return false }
        return Keychain.hasKey(account: cleaner.rawValue)
    }

    var currentAudioLevel: Float {
        recorder.currentAudioLevel()
    }

    /// True only between dictations. The mode switch reads this: changing mode while
    /// the engine is mid-run would show one mode and deliver another.
    var isIdle: Bool {
        state == .idle
    }

    private enum State {
        case idle
        case recording
        case processing
    }

    private let recorder = AudioRecorder()
    private let engineRunner: EngineRunner
    private let acceptanceLogger: AcceptanceLogger?
    private let processingQueue = DispatchQueue(
        label: "dot.sanblue.voiceflow.processing",
        qos: .userInitiated
    )
    private var state = State.idle
    private var recordingStartedAt: Date?
    private var recordingCleaner: CleanerMode?
    private var recordingMode: ProcessingMode?
    private var recordingGeminiModel: GeminiModel?

    init(configuration: VoiceFlowConfiguration, engineSourceRoot: URL) {
        engineRunner = EngineRunner(
            configuration: configuration,
            engineSourceRoot: engineSourceRoot
        )
        acceptanceLogger = configuration.acceptanceLog.map(AcceptanceLogger.init)
        selectedCleaner = configuration.cleaner
        selectedMode = configuration.mode
        selectedGeminiModel =
            GeminiModel(rawValue: configuration.geminiModel) ?? .preferredDefault
    }

    func shortcutPressed() {
        guard state == .idle else { return }
        do {
            try recorder.start()
            recordingStartedAt = Date()
            recordingCleaner = selectedCleaner
            recordingMode = selectedMode
            recordingGeminiModel = selectedGeminiModel
            state = .recording
            onStatusChange?(.recording)
        } catch {
            fail(error)
        }
    }

    func shortcutReleased() {
        guard state == .recording else { return }

        let audioURL: URL
        do {
            audioURL = try recorder.stop()
        } catch {
            fail(error)
            return
        }
        let spokenSeconds = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartedAt = nil

        state = .processing
        onStatusChange?(.processing)
        let startedAt = Date()

        // Read the key on the main thread before handing work to the queue, so the
        // choice that was on screen is the one that runs.
        let cleaner = recordingCleaner ?? selectedCleaner
        let mode = recordingMode ?? selectedMode
        let geminiModel = recordingGeminiModel ?? selectedGeminiModel
        recordingCleaner = nil
        recordingMode = nil
        recordingGeminiModel = nil
        let apiKey = cleaner.isCloud ? Keychain.read(account: cleaner.rawValue) : nil
        let recordDistillationPair = recordDistillationPairs

        processingQueue.async { [self] in
            do {
                let result = try self.engineRunner.process(
                    audioURL: audioURL,
                    cleaner: cleaner,
                    mode: mode,
                    geminiModel: geminiModel,
                    apiKey: apiKey,
                    recordDistillationPair: recordDistillationPair
                )
                let elapsed = Date().timeIntervalSince(startedAt)
                var acceptanceCount: Int?
                var acceptanceError: String?
                if let acceptanceLogger = self.acceptanceLogger {
                    do {
                        acceptanceCount = try acceptanceLogger.append(
                            result: result,
                            latency: elapsed,
                            audioURL: audioURL
                        )
                    } catch {
                        // Dictation already succeeded, but acceptance evidence is not
                        // optional once that mode was requested. Surface the failure.
                        acceptanceError = error.localizedDescription
                    }
                }
                let audioCleanupError = self.cleanupWarning(for: audioURL)
                DispatchQueue.main.async {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(result.finalText, forType: .string)

                    self.state = .idle
                    self.onStatusChange?(
                        .copied(
                            elapsed,
                            usedFallback: result.outcome == .safeFallback,
                            acceptanceCount: acceptanceCount,
                            acceptanceError: acceptanceError,
                            audioCleanupError: audioCleanupError,
                            model: result.model,
                            mode: mode,
                            result: result,
                            spokenSeconds: spokenSeconds
                        )
                    )
                }
            } catch {
                let audioCleanupError = self.cleanupWarning(for: audioURL)
                DispatchQueue.main.async {
                    self.fail(error, additionalMessage: audioCleanupError)
                }
            }
        }
    }

    private func cleanupWarning(for audioURL: URL) -> String? {
        do {
            try removeTemporaryAudio(at: audioURL)
            return nil
        } catch {
            return "Privacy warning: temporary audio remains at \(audioURL.path): " +
                error.localizedDescription
        }
    }

    private func fail(_ error: Error, additionalMessage: String? = nil) {
        recordingStartedAt = nil
        recordingCleaner = nil
        state = .idle
        let suffix = additionalMessage.map { " \($0)" } ?? ""
        onStatusChange?(.failed(error.localizedDescription + suffix))
    }
}
