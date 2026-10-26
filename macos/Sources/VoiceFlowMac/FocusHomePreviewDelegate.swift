import AppKit
import SwiftUI
import VoiceFlowMacCore

/// UI-only harness. No AppDelegate, capture controller, stores, clipboard, keychain,
/// global hotkeys, model processes or networking are constructed by this delegate.
@MainActor
final class FocusHomePreviewDelegate: NSObject, NSApplicationDelegate {
    static let bundleIdentifier = "dot.sanblue.voiceflow.focus-home-preview"
    private let model = VoiceStationViewModel()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.statusTitle = "UI Preview"
        model.statusDetail = "UI preview · simulated controls only. No microphone, model, cloud or personal data is connected."
        model.activityLogs = [ActivityLogItem(message: "UI-only preview. All states are simulated.")]
        model.targetAppName = "Preview only"
        model.globalHotkeyAvailable = false
        model.needsAccessibility = true
        model.onModeSelect = { [weak self] in self?.model.selectedMode = $0 }
        model.onCleanerSelect = { [weak self] in self?.model.selectedCleaner = $0 }
        model.onGeminiModelSelect = { [weak self] in self?.model.selectedGeminiModel = $0 }
        model.onRecordPress = { [weak self] in
            self?.model.isRecording = true
            self?.model.isSelectionEnabled = false
            self?.model.statusTitle = "Preview recording"
        }
        model.onRecordRelease = { [weak self] in self?.finishSimulation() }
        model.onCancelRecording = { [weak self] in self?.finishSimulation() }
        model.onClearHistory = { [weak self] in self?.model.recentDictations = [] }
        model.onCopyHistoryRecord = { [weak self] _ in self?.reportSimulation("Copy") }
        model.onCopyRawRecord = { [weak self] _ in self?.reportSimulation("Copy original") }
        model.onRepasteHistoryRecord = { [weak self] _ in self?.reportSimulation("Re-paste") }
        model.onSetAPIKey = { [weak self] _ in self?.reportSimulation("Key entry") }
        model.onForgetAPIKey = { [weak self] _ in self?.reportSimulation("Key removal") }
        model.onOpenAccessibility = { [weak self] in self?.reportSimulation("Accessibility settings") }
        model.onOpenInputMonitoring = { [weak self] in self?.reportSimulation("Input Monitoring settings") }
        model.onRetryPermissions = { [weak self] in self?.reportSimulation("Permission check") }
        model.onRunHealthCheck = { [weak self] in
            self?.model.healthReport = "[PASS] Python: 3.14.7\n[PASS] whisper.cpp binary: found\n[PASS] Whisper model: ggml\n[PASS] Parakeet model: found\n[PASS] Gemini API key: configured"
        }
        model.onAddSnippet = { [weak self] trigger, expansion, description in
            guard let self else { return false }
            self.model.snippets.removeAll { $0.trigger.localizedCaseInsensitiveCompare(trigger) == .orderedSame }
            self.model.snippets.append(VoiceSnippet(trigger: trigger, expansion: expansion, description: description))
            return true
        }
        model.onDeleteSnippet = { [weak self] id in self?.model.snippets.removeAll { $0.id == id } }
        model.onAcceptRejectedCleanup = { [weak self] _ in self?.model.rejectedCleanup = nil }
        model.onDismissRejectedCleanup = { [weak self] in self?.model.rejectedCleanup = nil }
        model.words = WordsSnapshot(
            vocabulary: ["UTEL", "VoiceFlow", "Whisper", "Parakeet", "Ollama"],
            inPrompt: 5,
            corrections: [
                WordsCorrection(
                    heard: "oyamas",
                    intended: "Ollama",
                    confirmedAt: "2026-10-25T14:30:00Z",
                    source: "fix",
                    everywhere: true
                ),
                WordsCorrection(
                    heard: "i phone",
                    intended: "iPhone",
                    confirmedAt: "2026-10-24T18:20:00Z",
                    source: "window",
                    everywhere: false
                )
            ]
        )
        model.onRefreshWords = { [weak self] in
            self?.reportSimulation("Refresh Words")
        }
        model.onLearnCorrection = { [weak self] request in
            guard let self else { return }
            var current = self.model.words?.corrections ?? []
            if let replacing = request.replacing {
                current.removeAll { $0.heard.lowercased() == replacing.lowercased() }
            }
            for pair in request.pairs {
                current.removeAll { $0.heard.lowercased() == pair.heard.lowercased() }
                current.append(WordsCorrection(
                    heard: pair.heard,
                    intended: pair.intended,
                    confirmedAt: "2026-10-25T20:00:00Z",
                    source: request.source.rawValue,
                    everywhere: request.everywhere
                ))
            }
            let vocab = self.model.words?.vocabulary ?? []
            let inPrompt = self.model.words?.inPrompt ?? 0
            self.model.words = WordsSnapshot(vocabulary: vocab, inPrompt: inPrompt, corrections: current)
            self.model.wordsNotice = "learned: \(request.pairs.map(\.intended).joined(separator: ", "))"
            self.reportSimulation("Learn correction")
        }
        model.onForgetCorrection = { [weak self] heard in
            guard let self else { return }
            var current = self.model.words?.corrections ?? []
            current.removeAll { $0.heard.lowercased() == heard.lowercased() }
            let vocab = self.model.words?.vocabulary ?? []
            let inPrompt = self.model.words?.inPrompt ?? 0
            self.model.words = WordsSnapshot(vocabulary: vocab, inPrompt: inPrompt, corrections: current)
            self.model.wordsNotice = "deleted: \"\(heard)\""
            self.reportSimulation("Forget correction")
        }
        model.onAddWord = { [weak self] term in
            guard let self else { return }
            var vocab = self.model.words?.vocabulary ?? []
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !vocab.contains(trimmed) {
                vocab.append(trimmed)
            }
            let corrections = self.model.words?.corrections ?? []
            self.model.words = WordsSnapshot(vocabulary: vocab, inPrompt: vocab.count, corrections: corrections)
            self.model.wordsNotice = "added: \"\(trimmed)\""
            self.reportSimulation("Add vocabulary word")
        }
        model.onRemoveWord = { [weak self] term in
            guard let self else { return }
            var vocab = self.model.words?.vocabulary ?? []
            vocab.removeAll { $0 == term }
            let corrections = self.model.words?.corrections ?? []
            self.model.words = WordsSnapshot(vocabulary: vocab, inPrompt: vocab.count, corrections: corrections)
            self.model.wordsNotice = "removed: \"\(term)\""
            self.reportSimulation("Remove vocabulary word")
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Focus Home Preview — UI only"
        window.contentMinSize = ControlWindowController.contentFloor
        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero,
                                            size: ControlWindowController.contentFloor)).size
        window.contentView = NSHostingView(rootView: VoiceStationWindowView(viewModel: model))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        configureMenu()
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func configureMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let submenu = NSMenu(title: "Focus Home Preview")
        submenu.addItem(withTitle: "Quit Focus Home Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = submenu
        menu.addItem(appItem)
        let scenarios = NSMenuItem()
        let scenes = NSMenu(title: "Preview scenarios")
        for (title, action) in [
            ("Show sample history", #selector(sampleHistory)),
            ("Show held-back cleanup", #selector(sampleCleanup)),
            ("Lock a run in flight", #selector(lockRun)),
            ("Minimum window size", #selector(minimumSize)),
            ("Reference window size", #selector(referenceSize))
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            scenes.addItem(item)
        }
        scenarios.submenu = scenes
        menu.addItem(scenarios)
        NSApp.mainMenu = menu
    }

    private func finishSimulation() {
        model.isRecording = false
        model.isSelectionEnabled = true
        model.statusTitle = "UI Preview"
    }

    private func reportSimulation(_ action: String) {
        model.statusDetail = "UI preview · \(action) was simulated. No data was read, written or transmitted."
    }

    @objc private func sampleHistory() {
        model.recentDictations = [DictationRecord(
            rawText: "Preview sample: lets make the app easier to use without losing its personality",
            personalizedText: "Preview sample: lets make the app easier to use without losing its personality",
            finalText: "Preview sample: Let’s make the app easier to use without losing its personality.",
            cleaner: "UI fixture", mode: "clean", latencySeconds: 0),
        // A delivered transcript beside a real cleanup, because the two used to be
        // indistinguishable in this list and that is the row worth looking at.
        DictationRecord(
            rawText: "Preview sample: the cleanup this row shows was never applied",
            personalizedText: "Preview sample: the cleanup this row shows was never applied",
            finalText: "Preview sample: the cleanup this row shows was never applied",
            cleaner: "UI fixture", mode: "clean", latencySeconds: 0,
            usedFallback: true,
            fallbackReason: "the cleanup changed too much to verify")]
    }

    @objc private func sampleCleanup() {
        model.rejectedCleanup = "PREVIEW SAMPLE — This is a simulated suggestion held back for your review."
    }

    /// A run past the release and still in cleanup: selection locked, nothing held.
    ///
    /// The capsule unlocks the moment it is let go, so a held button cannot be used to
    /// reach this state with one pointer — and it is the state where the mode, engine
    /// and model switches must refuse out loud. Lock it from here, press one of them,
    /// and the refusal is the thing under review.
    @objc private func lockRun() {
        model.isSelectionEnabled = false
        model.statusTitle = "Preview cleanup"
        model.statusDetail = "Simulated run in flight. Selection is locked; navigation is not."
    }

    @objc private func minimumSize() { window?.setContentSize(ControlWindowController.contentFloor) }
    @objc private func referenceSize() { window?.setContentSize(NSSize(width: 1100, height: 800)) }
}
