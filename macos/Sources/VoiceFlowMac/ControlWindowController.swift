import AppKit
import SwiftUI
import VoiceFlowMacCore

@MainActor
final class ControlWindowController: NSWindowController, NSWindowDelegate {
    var onRetryPermissions: (() -> Void)?
    var onOpenInputMonitoring: (() -> Void)?
    var onOpenAccessibility: (() -> Void)?
    var onCleanerChange: ((CleanerMode) -> Void)?
    var onSpeechEngineChange: ((SpeechEngine) -> Void)?
    var onModeChange: ((ProcessingMode) -> Void)?
    var onGeminiModelChange: ((GeminiModel) -> Void)?
    var onSetAPIKey: ((CleanerMode) -> Void)?
    var onForgetAPIKey: ((CleanerMode) -> Void)?
    var onCopyHistoryRecord: ((DictationRecord) -> Void)?
    var onCopyRawRecord: ((DictationRecord) -> Void)?
    var onRepasteHistoryRecord: ((DictationRecord) -> Void)?
    var onLearnCorrection: ((WordsLearnRequest) -> Void)?
    var onForgetCorrection: ((String) -> Void)?
    var onAddWord: ((String) -> Void)?
    var onRemoveWord: ((String) -> Void)?
    var onRefreshWords: (() -> Void)?
    var onClearHistory: (() -> Void)?
    var onCancelRecording: (() -> Void)?
    var onAcceptRejectedCleanup: ((String) -> Void)?
    var onDismissRejectedCleanup: (() -> Void)?
    var onAddSnippet: ((String, String, String?) -> Bool)?
    var onDeleteSnippet: ((UUID) -> Void)?
    var onRunHealthCheck: (() -> Void)?

    private var onRecordPressAction: (() -> Void)?
    private var onRecordReleaseAction: (() -> Void)?

    let viewModel = VoiceStationViewModel()

    /// The smallest content the station stays usable in.
    ///
    /// Raised from 560 to 700 on 2026-09-01, against two screenshots of the running window: at
    /// 560 the mode switch and the hold hint fall out of the control card, and at the
    /// measured 687 of the size she accepted they are all present. 710 keeps a margin
    /// so the second row of mode tiles does not fall below the fold at the floor (D-119).
    ///
    /// The width is the sidebar (184), the workspace padding (44), the 16 between the
    /// cards and two 320 floors — the control card's and the console's. At the earlier
    /// 760 the control card got 196 and spilled over the sidebar (D-57).
    static let contentFloor = NSSize(width: 884, height: 710)

    /// Where the station was last left. macOS keeps the frame under this name in the
    /// application's own defaults, so the window reopens where it was put instead of
    /// jumping back to the centre of whichever screen happens to be active.
    private static let frameAutosaveName = NSWindow.FrameAutosaveName("VoiceFlowStation")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "sanblueᵈᵒᵗ VoiceFlow — retro voice-station"
        // The floor is declared once, in content coordinates, and then converted to the
        // frame coordinates AppKit actually enforces. Stating it only as `minSize` made
        // the content area land a title bar short of what the layout needed, so the
        // overflow was split top and bottom and clipped the header and footer. Stating
        // it only as `contentMinSize` did not hold at all once the view stopped
        // declaring its own minimum height, and the window could be dragged down to a
        // band too short to show a card. Both are set from the same number.
        //
        // 560pt of height is what the control card needs to show every row without
        // scrolling: the capsule, the mode switch and the meter, plus the chain, the
        // header and the footer around them.
        window.contentMinSize = Self.contentFloor
        window.minSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: Self.contentFloor)
        ).size
        // From the token, not a repeat of its value. A window painted with a copy of
        // navy stays behind on the day the token moves, and nothing fails to warn.
        window.backgroundColor = NSColor(VoiceStationTokens.navy)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        Self.restoreRememberedFrame(of: window)
        configureContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A remembered frame is honoured only while it is still reachable. A window restored
    /// onto a display that is no longer attached is a window the speaker cannot find and
    /// cannot move back, so a frame that lands on no screen falls back to centring. The
    /// saved size is clamped by `minSize`, so a frame stored before the floor was raised
    /// cannot reopen the window shorter than its content.
    private static func restoreRememberedFrame(of window: NSWindow) {
        let restored = window.setFrameUsingName(frameAutosaveName)
        let reachable = NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }
        if !restored || !reachable {
            window.center()
        }
        _ = window.setFrameAutosaveName(frameAutosaveName)
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window else { return }
        viewModel.isWindowVisible = window.occlusionState.contains(.visible)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        viewModel.isWindowVisible = false
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        viewModel.isWindowVisible = true
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let floor = sender.frameRect(
            forContentRect: NSRect(origin: .zero, size: Self.contentFloor)
        ).size
        return NSSize(
            width: max(frameSize.width, floor.width),
            height: max(frameSize.height, floor.height)
        )
    }

    func configureRecording(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        onRecordPressAction = onPress
        onRecordReleaseAction = onRelease
    }

    func setRecordingEnabled(_ enabled: Bool) {
        viewModel.isRecordingEnabled = enabled
    }

    func setProviderSelectionEnabled(_ enabled: Bool) {
        viewModel.isSelectionEnabled = enabled
    }

    func setRetryPermissionsEnabled(_ enabled: Bool) {
        // Managed reactively in viewModel
    }

    /// Fill the provider list and show the current choice.
    func configureProviders(selected: CleanerMode) {
        viewModel.selectedCleaner = selected
    }

    /// Name the trigger the app is actually enforcing.
    ///
    /// The hold hint used to read a default that nothing ever wrote, so a window launched
    /// with `--shortcut` told the speaker to hold a key the app was not listening for.
    /// Offer a cleanup the guard refused, or clear the offer.
    func showRejectedCleanup(_ text: String?) {
        viewModel.rejectedCleanup = text
    }

    func configureShortcut(name: String) {
        viewModel.shortcutName = name
    }

    func configureMode(selected: ProcessingMode) {
        viewModel.selectedMode = selected
    }

    func configureSpeechEngine(selected: SpeechEngine) {
        viewModel.selectedSpeechEngine = selected
    }

    func configureGeminiModel(selected: GeminiModel) {
        viewModel.selectedGeminiModel = selected
    }

    func setHealthBusy(_ busy: Bool) {
        viewModel.isHealthBusy = busy
    }

    func setHealthReport(_ report: String?) {
        viewModel.healthReport = report
    }

    /// Say plainly where the words will go, and whether that route is ready.
    func updateProvider(selected: CleanerMode, keyStored: Bool) {
        viewModel.selectedCleaner = selected
        viewModel.hasKey = keyStored
        if selected.isCloud {
            if keyStored {
                viewModel.addLog("cloud key verified for \(selected.displayName)")
            } else if Keychain.status(account: selected.rawValue) == .unavailable {
                viewModel.addLog("warning: the keychain could not be read for \(selected.displayName) · it may be locked", isHighlight: true)
            } else {
                viewModel.addLog("warning: no api key stored for \(selected.displayName)", isHighlight: true)
            }
        }
    }

    func update(title: String, detail: String) {
        viewModel.statusTitle = title
        viewModel.statusDetail = detail
        if title == "Recording…" {
            viewModel.isRecording = true
            viewModel.stationState = .recording
            viewModel.addLog("recording started…")
        } else if title.hasPrefix("Cleaning") || title.hasPrefix("Processing") {
            viewModel.isRecording = false
            viewModel.stationState = .processing
            viewModel.addLog("processing transcript with \(viewModel.selectedCleaner.displayName) (\(viewModel.selectedMode.rawValue))…")
        } else {
            viewModel.isRecording = false
            viewModel.stationState = title == "VoiceFlow needs attention" ? .failed : .ready
            viewModel.addLog(title, isHighlight: title.hasPrefix("Pasted") || title.hasPrefix("Copied"))
        }
    }

    func updateRecentDictations(_ records: [DictationRecord]) {
        viewModel.recentDictations = records
    }

    /// Show the vocabulary and corrections the engine just reported.
    func updateWords(_ snapshot: WordsSnapshot) {
        viewModel.words = snapshot
    }

    /// Say what the last Words action did, or why the engine refused it.
    func setWordsNotice(_ notice: String?) {
        viewModel.wordsNotice = notice
    }

    /// Mark whether an asynchronous Words action is running (D-91).
    func setWordsBusy(_ busy: Bool) {
        viewModel.isWordsBusy = busy
    }

    /// Empty the teach form after a pair was stored, so the next one starts clean.
    func clearTeachForm() {
        viewModel.teachHeard = ""
        viewModel.teachIntended = ""
        viewModel.teachSentence = ""
        viewModel.teachEverywhere = false
        viewModel.teachContext = nil
        viewModel.editingHeard = nil
    }

    /// Empty the add-a-word field after the word was stored.
    func clearNewWord() {
        viewModel.newWord = ""
    }

    func updateSnippets(_ snippets: [VoiceSnippet]) {
        viewModel.snippets = snippets
    }

    func updateAudioLevel(_ level: Double) {
        viewModel.audioLevel = level
    }

    /// One finished run's readings, every field assigned: a stage that reported nothing
    /// shows a dash, never the previous run's figure (D-72).
    func updateRunTelemetry(sttLatency: Double?, llmLatency: Double?, wpm: Int?) {
        viewModel.lastSTTLatency = sttLatency
        viewModel.lastLLMLatency = llmLatency
        viewModel.lastWPM = wpm
        viewModel.hasDeliveredThisSession = true
    }

    /// Mark that at least one dictation or action was delivered in this session (D-107).
    func markDeliveredThisSession() {
        viewModel.hasDeliveredThisSession = true
    }

    func updateTelemetry(targetApp: String? = nil, targetBundleId: String? = nil) {
        if let app = targetApp {
            viewModel.targetAppName = app
            // The bundle list alone: the paste guard reads only that list, so a badge
            // that also matched names promised protection the paste did not give (D-138).
            if PasteTarget.isTerminal(bundleIdentifier: targetBundleId) {
                viewModel.targetAppProfile = "Terminal (Single-line Guard)"
            } else if PasteTarget.requiresClipboardDelivery(bundleIdentifier: targetBundleId) {
                viewModel.targetAppProfile = "Clipboard Only (Protected)"
            } else {
                viewModel.targetAppProfile = "Direct Auto-Paste"
            }
        }
    }

    func addLog(_ message: String, category: LogCategory = .system, latency: Double? = nil, tags: [String] = [], isHighlight: Bool = false) {
        viewModel.addLog(message, category: category, latency: latency, tags: tags, isHighlight: isHighlight)
    }

    private func configureContent() {
        viewModel.onRecordPress = { [weak self] in
            self?.onRecordPressAction?()
        }
        viewModel.onRecordRelease = { [weak self] in
            self?.onRecordReleaseAction?()
        }
        viewModel.onCleanerSelect = { [weak self] cleaner in
            self?.onCleanerChange?(cleaner)
        }
        viewModel.onSpeechEngineSelect = { [weak self] engine in
            self?.onSpeechEngineChange?(engine)
        }
        viewModel.onModeSelect = { [weak self] mode in
            self?.onModeChange?(mode)
        }
        viewModel.onCancelRecording = { [weak self] in
            self?.onCancelRecording?()
        }
        viewModel.onAcceptRejectedCleanup = { [weak self] text in
            self?.onAcceptRejectedCleanup?(text)
        }
        viewModel.onDismissRejectedCleanup = { [weak self] in
            self?.onDismissRejectedCleanup?()
        }
        viewModel.onGeminiModelSelect = { [weak self] model in
            self?.onGeminiModelChange?(model)
        }
        viewModel.onSetAPIKey = { [weak self] cleaner in
            self?.onSetAPIKey?(cleaner)
        }
        viewModel.onForgetAPIKey = { [weak self] cleaner in
            self?.onForgetAPIKey?(cleaner)
        }
        viewModel.onOpenInputMonitoring = { [weak self] in
            self?.onOpenInputMonitoring?()
        }
        viewModel.onOpenAccessibility = { [weak self] in
            self?.onOpenAccessibility?()
        }
        viewModel.onRetryPermissions = { [weak self] in
            self?.onRetryPermissions?()
        }
        viewModel.onCopyHistoryRecord = { [weak self] record in
            self?.onCopyHistoryRecord?(record)
        }
        viewModel.onCopyRawRecord = { [weak self] record in
            self?.onCopyRawRecord?(record)
        }
        viewModel.onRepasteHistoryRecord = { [weak self] record in
            self?.onRepasteHistoryRecord?(record)
        }
        viewModel.onLearnCorrection = { [weak self] request in
            self?.onLearnCorrection?(request)
        }
        viewModel.onForgetCorrection = { [weak self] heard in
            self?.onForgetCorrection?(heard)
        }
        viewModel.onAddWord = { [weak self] term in
            self?.onAddWord?(term)
        }
        viewModel.onRemoveWord = { [weak self] term in
            self?.onRemoveWord?(term)
        }
        viewModel.onRefreshWords = { [weak self] in
            self?.onRefreshWords?()
        }
        viewModel.onClearHistory = { [weak self] in
            self?.onClearHistory?()
        }
        viewModel.onAddSnippet = { [weak self] trigger, expansion, description in
            self?.onAddSnippet?(trigger, expansion, description) ?? false
        }
        viewModel.onDeleteSnippet = { [weak self] id in
            self?.onDeleteSnippet?(id)
        }
        viewModel.onRunHealthCheck = { [weak self] in
            self?.onRunHealthCheck?()
        }

        let hostingView = NSHostingView(rootView: VoiceStationWindowView(viewModel: viewModel))
        window?.contentView = hostingView

        // Installing a hosting view makes AppKit recompute the window's limits from the
        // SwiftUI layout, which discarded the floor set in `init`. Re-apply it here, and
        // clamp in `windowWillResize` as well: the delegate is asked on every drag step,
        // so it holds whatever the content view decides its own minimum is.
        // The hosting view must not push its own sizing onto the window. Its defaults are
        // what recomputed the limits and discarded the floor when it was installed.
        hostingView.sizingOptions = []

        if let window {
            window.contentMinSize = Self.contentFloor
            window.minSize = window.frameRect(
                forContentRect: NSRect(origin: .zero, size: Self.contentFloor)
            ).size
            window.delegate = self
        }
    }
}
