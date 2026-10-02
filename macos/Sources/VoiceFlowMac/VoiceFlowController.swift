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
    /// The speaker took the recording back before it was delivered, or let go of the
    /// trigger before the microphone ever opened.
    case cancelled(reason: CancelReason)
    case failed(String)
}

/// Which control started a recording. The hotkey and the window's hold button share one
/// state machine, and without this a stray click on the button ended a dictation the
/// speaker was still holding the key for — then swallowed the real release in silence.
enum RecordingSource: Equatable {
    case hotkey
    case button
}

enum CancelReason {
    /// The trigger was released inside the hold delay. The microphone never opened.
    case tooShort
    /// Escape was pressed while recording. The audio is discarded, nothing is pasted.
    case escaped
    /// The selected mode cannot run with the selected cleaner. Refused at the press, so
    /// no recording is spent on a run the engine would refuse (D-23).
    case refused(String)
}

final class VoiceFlowController {
    var onStatusChange: ((VoiceFlowStatus) -> Void)?

    /// The provider the window currently shows. Changing it takes effect on the next
    /// recording, so the speaker is never mid-dictation when the destination changes.
    private(set) var selectedCleaner: CleanerMode
    private(set) var selectedMode: ProcessingMode
    private(set) var selectedGeminiModel: GeminiModel
    private(set) var selectedSpeechEngine: SpeechEngine = .whisper

    func selectSpeechEngine(_ engine: SpeechEngine) {
        selectedSpeechEngine = engine
    }

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
        /// The trigger is down but the hold delay has not elapsed. No microphone yet.
        case arming
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
    private var recordingSource: RecordingSource?
    private var armWorkItem: DispatchWorkItem?
    private let holdDelaySeconds: TimeInterval
    private var recordingStartedAt: Date?
    private var recordingCleaner: CleanerMode?
    private var recordingMode: ProcessingMode?
    private var recordingGeminiModel: GeminiModel?
    private var recordingSpeechEngine: SpeechEngine?

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
        holdDelaySeconds = configuration.holdDelaySeconds
    }

    func shortcutPressed(from source: RecordingSource = .hotkey) {
        guard state == .idle else { return }
        if let refusal = selectedMode.refusal(with: selectedCleaner) {
            onStatusChange?(.cancelled(reason: .refused(refusal)))
            return
        }
        // The microphone does not open on the press. It opens once the trigger has been
        // held, so a hand brushing the Fn key costs no recording and no indicator light.
        recordingSource = source
        state = .arming
        let work = DispatchWorkItem { [weak self] in
            self?.openMicrophone()
        }
        armWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDelaySeconds, execute: work)
    }

    private func openMicrophone() {
        guard state == .arming else { return }
        armWorkItem = nil
        do {
            try recorder.start()
            recordingStartedAt = Date()
            recordingCleaner = selectedCleaner
            recordingMode = selectedMode
            recordingGeminiModel = selectedGeminiModel
            recordingSpeechEngine = selectedSpeechEngine
            // Apple's model loads while the speaker talks, not after the transcript is
            // ready: a cold load cost about a second of every dictation.
            if selectedCleaner == .apple {
                AppleModelWarmer.prewarm()
            }
            // The selection is read once, at the press. A retry here fired a second
            // synthetic copy half a second later, by which time the frontmost window is
            // whatever the speaker moved to — so it could capture from an application the
            // press never pointed at, and it only ever ran when the first read had already
            // decided there was nothing selected.
            state = .recording
            onStatusChange?(.recording)
        } catch {
            fail(error)
        }
    }

    /// Take the recording back. The audio is deleted rather than transcribed, so a
    /// dictation the speaker changed their mind about leaves nothing behind.
    /// Take back whatever is in flight, from any control.
    ///
    /// Cancelling is not the hotkey's privilege: Escape reaches this through the global
    /// event tap, which needs Input Monitoring, and the app deliberately supports a
    /// speaker who never granted it and dictates with the window's button. A recording
    /// they could start and not stop is the take-back requirement unmet.
    func cancelRecording() {
        switch state {
        case .idle, .processing:
            return
        case .arming:
            // Nothing is recording yet; drop the pending open so it never happens.
            armWorkItem?.cancel()
            armWorkItem = nil
            state = .idle
            recordingSource = nil
            onStatusChange?(.cancelled(reason: .escaped))
            return
        case .recording:
            break
        }
        state = .idle
        recordingSource = nil
        recordingStartedAt = nil
        recordingCleaner = nil
        recordingMode = nil
        recordingGeminiModel = nil
        recordingSpeechEngine = nil
        // Cleared with the rest of the run's state. Leaving it behind relied on the next
        // press overwriting it, which is an invariant of a different method.
        if let audioURL = try? recorder.stop() {
            try? removeTemporaryAudio(at: audioURL)
        }
        onStatusChange?(.cancelled(reason: .escaped))
    }

    func shortcutReleased(from source: RecordingSource = .hotkey) {
        // Only the control that started this recording can end it. A click on the
        // window's button while the speaker holds the key used to cut the dictation in
        // half, and the key's own release was then discarded with nothing said.
        guard recordingSource == nil || recordingSource == source else { return }

        // Released inside the hold delay: the microphone never opened, so there is
        // nothing to stop and nothing to transcribe.
        if state == .arming {
            armWorkItem?.cancel()
            armWorkItem = nil
            state = .idle
            recordingSource = nil
            onStatusChange?(.cancelled(reason: .tooShort))
            return
        }
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
        let speechEngine = recordingSpeechEngine ?? selectedSpeechEngine
        // The `{app}` snippet macro names where the text is going, so it is read here,
        // while the target application is still the frontmost one.
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName
        recordingSource = nil
        recordingCleaner = nil
        recordingMode = nil
        recordingGeminiModel = nil
        recordingSpeechEngine = nil
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
                    appName: appName,
                    recordDistillationPair: recordDistillationPair,
                    speechEngine: speechEngine
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
                            usedFallback: result.usedFallback,
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

    /// True while a recording is running or about to start, so the window can offer a
    /// way out that does not depend on a keyboard permission.
    var isCancellable: Bool {
        state == .recording || state == .arming
    }

    private func fail(_ error: Error, additionalMessage: String? = nil) {
        armWorkItem?.cancel()
        armWorkItem = nil
        recordingSource = nil
        recordingStartedAt = nil
        recordingCleaner = nil
        // The rest of the run's state, cleared here too. Three of these were dropped on
        // the failure path while the success and cancellation paths cleared all of them,
        // which left a captured selection alive after a run that never used it.
        recordingMode = nil
        recordingGeminiModel = nil
        recordingSpeechEngine = nil
        state = .idle
        let suffix = additionalMessage.map { " \($0)" } ?? ""
        onStatusChange?(.failed(error.localizedDescription + suffix))
    }
}

/// Starts Apple's model loading in the system when a dictation begins.
///
/// The helper is run with `--prewarm`, asks the system to load the model and exits by
/// itself; the system keeps the model, not the process. Nothing waits for it and nothing
/// depends on it: if it fails, the cleanup is only as slow as it was before.
enum AppleModelWarmer {
    static func prewarm() {
        guard let helper = EngineRunner.appleCleanerURL else { return }
        let process = Process()
        process.executableURL = helper
        process.arguments = ["--prewarm"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
