import AppKit
import SwiftUI
import VoiceFlowMacCore

@MainActor
final class ControlWindowController: NSWindowController, NSWindowDelegate {
    var onRetryPermissions: (() -> Void)?
    var onOpenInputMonitoring: (() -> Void)?
    var onOpenAccessibility: (() -> Void)?
    var onCleanerChange: ((CleanerMode) -> Void)?
    var onModeChange: ((ProcessingMode) -> Void)?
    var onGeminiModelChange: ((GeminiModel) -> Void)?
    var onSetAPIKey: ((CleanerMode) -> Void)?
    var onForgetAPIKey: ((CleanerMode) -> Void)?
    var onCopyHistoryRecord: ((DictationRecord) -> Void)?
    var onCopyRawRecord: ((DictationRecord) -> Void)?
    var onRepasteHistoryRecord: ((DictationRecord) -> Void)?
    var onClearHistory: (() -> Void)?
    var onCancelRecording: (() -> Void)?
    var onAcceptRejectedCleanup: ((String) -> Void)?
    var onDismissRejectedCleanup: (() -> Void)?
    var onAddSnippet: ((String, String, String?) -> Void)?
    var onDeleteSnippet: ((UUID) -> Void)?

    private var onRecordPressAction: (() -> Void)?
    private var onRecordReleaseAction: (() -> Void)?

    let viewModel = VoiceStationViewModel()

    /// The smallest content the station stays usable in.
    ///
    /// Raised from 560 to 700 on 2026-09-01, against two screenshots of the running window: at
    /// 560 the mode switch and the hold hint fall out of the control card, and at the
    /// measured 687 of the size she accepted they are all present. 700 keeps a margin.
    static let contentFloor = NSSize(width: 760, height: 700)

    /// Where the station was last left. macOS keeps the frame under this name in the
    /// application's own defaults, so the window reopens where it was put instead of
    /// jumping back to the centre of whichever screen happens to be active.
    private static let frameAutosaveName = NSWindow.FrameAutosaveName("VoiceFlowStation")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 700),
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
    func configureProviders(available: [CleanerMode], selected: CleanerMode) {
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

    func configureGeminiModel(selected: GeminiModel) {
        viewModel.selectedGeminiModel = selected
    }

    /// Say plainly where the words will go, and whether that route is ready.
    func updateProvider(selected: CleanerMode, keyStored: Bool) {
        viewModel.selectedCleaner = selected
        viewModel.hasKey = keyStored
        if selected.isCloud {
            if keyStored {
                viewModel.addLog("cloud key verified for \(selected.displayName)")
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
            viewModel.addLog("recording started…")
        } else if title.hasPrefix("Cleaning") || title.hasPrefix("Processing") {
            viewModel.isRecording = false
            viewModel.addLog("processing transcript with \(viewModel.selectedCleaner.displayName) (\(viewModel.selectedMode.rawValue))…")
        } else {
            viewModel.isRecording = false
            viewModel.addLog(title, isHighlight: title.hasPrefix("Pasted") || title.hasPrefix("Copied"))
        }
    }

    func updateRecentDictations(_ records: [DictationRecord]) {
        viewModel.recentDictations = records
    }

    func updateSnippets(_ snippets: [VoiceSnippet]) {
        viewModel.snippets = snippets
    }

    func updateAudioLevel(_ level: Double) {
        viewModel.audioLevel = level
    }

    func updateTelemetry(sttLatency: Double? = nil, llmLatency: Double? = nil, wpm: Int? = nil, targetApp: String? = nil, targetBundleId: String? = nil) {
        if let stt = sttLatency { viewModel.lastSTTLatency = stt }
        if let llm = llmLatency { viewModel.lastLLMLatency = llm }
        if let rate = wpm { viewModel.lastWPM = rate }
        if let app = targetApp {
            viewModel.targetAppName = app
            if PasteTarget.isTerminal(bundleIdentifier: targetBundleId) || app.lowercased().contains("terminal") || app.lowercased().contains("iterm") || app.lowercased().contains("ghostty") || app.lowercased().contains("warp") {
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
        viewModel.onClearHistory = { [weak self] in
            self?.onClearHistory?()
        }
        viewModel.onAddSnippet = { [weak self] trigger, expansion, description in
            self?.onAddSnippet?(trigger, expansion, description)
        }
        viewModel.onDeleteSnippet = { [weak self] id in
            self?.onDeleteSnippet?(id)
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
