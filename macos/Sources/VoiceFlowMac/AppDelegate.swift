import AppKit
import CoreGraphics
import Foundation
import VoiceFlowMacCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var statusMenuItem: NSMenuItem!
    private var shortcutMenuItem: NSMenuItem!
    private var modeMenuItem: NSMenuItem!
    private var retryMenuItem: NSMenuItem!
    private var showMenuItem: NSMenuItem!
    private var controlWindow: ControlWindowController!
    private var configuration: VoiceFlowConfiguration?
    private var controller: VoiceFlowController?
    private var hotkeyMonitor: HotkeyMonitor?
    private var globalHotkeyAvailable = false
    private var selectedCleaner = CleanerMode.literal
    private var selectedMode = ProcessingMode.clean

    /// The engine the speaker picked, remembered across launches.
    ///
    /// R6 makes this the rule for the cloud model, and the reason is the same one: the
    /// app is opened from the Finder with no arguments, so a choice that lives only in
    /// launch configuration is no choice at all. An explicit `--cleaner` still wins,
    /// because a speaker who names an engine on the command line means that run.
    private static let cleanerDefaultsKey = "dot.sanblue.voiceflow.cleaner"

    /// The speech engine the speaker picked, remembered across launches for the same
    /// reason as the cleaner: the app is opened from the Finder with no arguments.
    private static let speechEngineDefaultsKey = "dot.sanblue.voiceflow.speechEngine"
    private var selectedSpeechEngine: SpeechEngine = {
        UserDefaults.standard.string(forKey: AppDelegate.speechEngineDefaultsKey)
            .flatMap(SpeechEngine.init(rawValue:)) ?? .whisper
    }()

    /// The cloud model the speaker picked, remembered across launches. The app is
    /// launched from Finder with no arguments, so without this the choice would reset
    /// to the compiled default every time.
    private static let geminiModelDefaultsKey = "dot.sanblue.voiceflow.geminiModel"
    private var selectedGeminiModel: GeminiModel = {
        let stored = UserDefaults.standard.string(forKey: AppDelegate.geminiModelDefaultsKey)
        return stored.flatMap(GeminiModel.init(rawValue:)) ?? .preferredDefault
    }()

    /// Whether each cloud dictation is kept as a local distillation pair. The pairs
    /// are the spoken sentences themselves, so this stays off until the speaker turns
    /// it on, and the choice is remembered across launches like the model choice.
    private static let distillationDefaultsKey = "dot.sanblue.voiceflow.recordDistillationPairs"
    private var recordDistillationPairs = UserDefaults.standard.bool(
        forKey: AppDelegate.distillationDefaultsKey
    )
    private var distillationMenuItem: NSMenuItem!
    private var retryPermissionsAvailable = true
    private let floatingHUD = FloatingHUDController()
    private static let historyLoad = DictationHistoryStore.loadReporting()
    private var historyStore: DictationHistoryStore = AppDelegate.historyLoad.store
    private static let snippetLoad = VoiceSnippetStore.loadReporting()
    private var snippetStore: VoiceSnippetStore = AppDelegate.snippetLoad.store
    private var historyMenuItem: NSMenuItem!
    private var historyMenu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureApplicationMenu()
        // A release while the Mac slept was never seen; read the key again on wake.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue, so the main actor is already the one running.
            MainActor.assumeIsolated { self?.hotkeyMonitor?.resyncAfterWake() }
        }

        if CommandLine.arguments.dropFirst().contains("--help") {
            print(VoiceFlowConfiguration.help)
            NSApplication.shared.terminate(nil)
            return
        }

        var launchError: Error?
        do {
            let projectRoot = defaultProjectRoot()
            let configuration = try VoiceFlowConfiguration.parse(
                arguments: Array(CommandLine.arguments.dropFirst()),
                currentDirectory: projectRoot
            )
            try validate(configuration)
            self.configuration = configuration
            // An App Intent can run with no window open, so it cannot ask the delegate
            // where the engine is. Handed over here, once, from the same parse.
            AppIntentsContext.configuration = configuration
            AppIntentsContext.engineSourceRoot = engineSourceRoot(for: configuration)

            let cleanerWasGiven = CommandLine.arguments.contains("--cleaner")
            selectedCleaner = cleanerWasGiven
                ? configuration.cleaner
                : UserDefaults.standard
                    .string(forKey: AppDelegate.cleanerDefaultsKey)
                    .flatMap(CleanerMode.init(rawValue:))
                    ?? configuration.cleaner
            selectedMode = configuration.mode
        } catch {
            launchError = error
        }

        // Build the interface only after launch arguments have been parsed. This keeps
        // the provider shown in the window identical to the provider that will run.
        configureWindow()
        configureStatusMenu()

        if let launchError {
            updateStatus(.failed(launchError.localizedDescription))
        } else if let configuration {
            shortcutMenuItem.title = "Shortcut: \(configuration.shortcut.displayName)"
            controlWindow.configureShortcut(name: configuration.shortcut.displayName)
            updateModeMenuItem()
            authorizeAndStart()
            refreshWords()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.discardAudioOnTermination()
    }

    private func configureWindow() {
        controlWindow = ControlWindowController()
        controlWindow.onRetryPermissions = { [weak self] in
            self?.retryPermissions()
        }
        controlWindow.onOpenInputMonitoring = { [weak self] in
            self?.openInputMonitoringSettings()
        }
        controlWindow.onOpenAccessibility = { [weak self] in
            self?.openAccessibilitySettings()
        }
        // The window's button is a distinct control from the hotkey, and says so, so a
        // click cannot end a dictation the speaker is holding the key for.
        controlWindow.configureRecording(
            onPress: { [weak self] in self?.controller?.shortcutPressed(from: .button) },
            onRelease: { [weak self] in self?.controller?.shortcutReleased(from: .button) }
        )
        controlWindow.onCancelRecording = { [weak self] in
            self?.controller?.cancelRecording()
        }
        controlWindow.configureProviders(
            selected: selectedCleaner
        )
        controlWindow.configureMode(selected: selectedMode)
        controlWindow.configureGeminiModel(selected: selectedGeminiModel)
        controlWindow.configureSpeechEngine(selected: selectedSpeechEngine)
        controlWindow.onSpeechEngineChange = { [weak self] engine in
            guard let self else { return }
            self.selectedSpeechEngine = engine
            self.controller?.selectSpeechEngine(engine)
            UserDefaults.standard.set(engine.rawValue, forKey: AppDelegate.speechEngineDefaultsKey)
            self.controlWindow.addLog("speech: \(engine.shortName)", isHighlight: true)
        }
        controlWindow.onCleanerChange = { [weak self] cleaner in
            self?.selectedCleaner = cleaner
            self?.controller?.selectCleaner(cleaner)
            self?.refreshProvider(cleaner)
            UserDefaults.standard.set(
                cleaner.rawValue, forKey: AppDelegate.cleanerDefaultsKey
            )
        }
        controlWindow.onModeChange = { [weak self] mode in
            // The window already shows the new mode and wrote its own log line, so this
            // path only carries the choice outward.
            self?.applyProcessingMode(mode, confirmInHUD: false, syncWindow: false)
        }
        controlWindow.onGeminiModelChange = { [weak self] model in
            guard let self else { return }
            self.selectedGeminiModel = model
            self.controller?.selectGeminiModel(model)
            UserDefaults.standard.set(
                model.rawValue, forKey: AppDelegate.geminiModelDefaultsKey
            )
        }
        controlWindow.onSetAPIKey = { [weak self] cleaner in
            self?.promptForAPIKey(cleaner)
        }
        controlWindow.onForgetAPIKey = { [weak self] cleaner in
            self?.forgetAPIKey(cleaner)
        }
        controlWindow.updateRecentDictations(historyStore.records)
        controlWindow.onCopyHistoryRecord = { [weak self] record in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(record.currentText, forType: .string)
            self?.playCompletionSound()
        }
        controlWindow.onCopyRawRecord = { [weak self] record in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(record.rawText, forType: .string)
            self?.playCompletionSound()
        }
        controlWindow.onRepasteHistoryRecord = { [weak self] record in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(record.currentText, forType: .string)
            self?.playCompletionSound()
            NSApplication.shared.hide(nil)
            AutoPaste.paste(after: 0.15) { [weak self] didAutoPaste, _ in
                let action = didAutoPaste ? "re-pasted" : "copied"
                self?.controlWindow?.addLog("\(action) from history: \"\(record.menuPreview())\"", isHighlight: true)
            }
        }
        controlWindow.onRefreshWords = { [weak self] in
            self?.refreshWords()
        }
        controlWindow.onLearnCorrection = { [weak self] request in
            guard let self else { return }
            // An edit that changed the heard side is a new key: the old pair goes, so
            // the list never holds both the misspelling and its replacement.
            // Learned first, forgotten after: the runner stops at the first failure, so a
            // refused learn now keeps the old pair instead of losing it (D-51).
            var commands: [WordsCommand] = []
            for pair in request.pairs {
                commands.append(.learn(
                    heard: pair.heard,
                    intended: pair.intended,
                    everywhere: request.everywhere && pair.isOneWord,
                    source: request.source
                ))
            }
            if let old = request.replacing, let first = request.pairs.first,
               old.lowercased() != first.heard.lowercased() {
                commands.append(.forget(heard: old))
            }
            let learned = request.pairs
                .map { "\"\($0.heard)\" → \"\($0.intended)\"" }
                .joined(separator: ", ")
            self.runWords(commands, success: "learned: \(learned)") { [weak self] in
                self?.applyLearnedFix(request)
                self?.controlWindow.clearTeachForm()
            }
        }
        controlWindow.onForgetCorrection = { [weak self] heard in
            self?.runWords([.forget(heard: heard)], success: "deleted: \"\(heard)\"")
        }
        controlWindow.onAddWord = { [weak self] term in
            self?.runWords([.addWord(term)], success: "added to vocabulary: \"\(term)\"") { [weak self] in
                self?.controlWindow.clearNewWord()
            }
        }
        controlWindow.onRemoveWord = { [weak self] term in
            self?.runWords([.removeWord(term)], success: "removed from vocabulary: \"\(term)\"")
        }
        controlWindow.onClearHistory = { [weak self] in
            self?.clearDictationHistory()
        }
        // The guard's refusal becomes a question. Accepting puts the text on the
        // clipboard and says so; nothing is pasted behind the speaker's back, because
        // the cursor has moved on since the dictation ended.
        controlWindow.onAcceptRejectedCleanup = { [weak self] text in
            guard let self else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            self.playCompletionSound()
            self.controlWindow.showRejectedCleanup(nil)
            self.controlWindow.addLog("held-back cleanup accepted · copied", isHighlight: true)
        }
        controlWindow.onDismissRejectedCleanup = { [weak self] in
            self?.controlWindow.showRejectedCleanup(nil)
            self?.controlWindow.addLog("held-back cleanup discarded")
        }
        controlWindow.updateSnippets(snippetStore.snippets)
        // A store that could not be read is said out loud. Starting empty in silence is
        // how the next add from this window used to overwrite the speaker's real file.
        if let failure = AppDelegate.snippetLoad.failure {
            controlWindow.addLog(failure, isHighlight: true)
        }
        if let failure = AppDelegate.historyLoad.failure {
            controlWindow.addLog(failure, isHighlight: true)
        }
        // Every edit re-reads the file under the engine's lock, so a `vf snippet add` made
        // while the app runs survives the next edit here (D-40).
        controlWindow.onAddSnippet = { [weak self] trigger, expansion, description in
            guard let self else { return false }
            // A repeated trigger replaced the old snippet without asking (D-75).
            if let current = self.snippetStore.existing(trigger: trigger) {
                let alert = NSAlert()
                alert.messageText = "Replace the snippet [\(current.trigger)]?"
                alert.informativeText = "It expands to: \(current.expansion)"
                alert.addButton(withTitle: "Replace")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return false }
            }
            var added: VoiceSnippet?
            guard let written = VoiceSnippetStore.edit({
                added = $0.add(trigger: trigger, expansion: expansion, description: description)
            }) else {
                self.controlWindow.addLog("the snippet was not saved · the store could not be read or written", isHighlight: true)
                return false
            }
            self.snippetStore = written
            self.controlWindow.updateSnippets(written.snippets)
            guard let snip = added else { return false }
            self.controlWindow.addLog("added voice snippet [\(snip.trigger)]", isHighlight: true)
            return true
        }
        controlWindow.onDeleteSnippet = { [weak self] id in
            guard let self,
                  let trigger = self.snippetStore.snippets.first(where: { $0.id == id })?.trigger
            else { return }
            var deleted = false
            guard let written = VoiceSnippetStore.edit({ deleted = $0.delete(trigger: trigger) }) else {
                self.controlWindow.addLog("the snippet was not deleted · the store could not be read or written", isHighlight: true)
                return
            }
            self.snippetStore = written
            self.controlWindow.updateSnippets(written.snippets)
            if deleted {
                self.controlWindow.addLog("deleted voice snippet", isHighlight: true)
            }
        }
        controlWindow.onRunHealthCheck = { [weak self] in
            self?.runHealthCheck()
        }
        refreshProvider(selectedCleaner)
        controlWindow.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func forgetAPIKey(_ cleaner: CleanerMode) {
        switch Keychain.delete(account: cleaner.rawValue) {
        case .removed, .notFound:
            break
        case .failed(let status):
            let failure = NSAlert()
            failure.messageText = "The key was not removed."
            failure.informativeText =
                "The keychain refused the request (status \(status)). The existing key remains available."
            failure.runModal()
        }
        refreshProvider(cleaner)
    }

    private func refreshProvider(_ cleaner: CleanerMode) {
        controlWindow.updateProvider(
            selected: cleaner,
            keyStored: cleaner.isCloud && Keychain.hasKey(account: cleaner.rawValue)
        )
    }

    /// Ask for the key in a secure field and hand it straight to the keychain. It is
    /// never held in a property, written to preferences, or shown again.
    private func promptForAPIKey(_ cleaner: CleanerMode) {
        let alert = NSAlert()
        alert.messageText = "\(cleaner.displayName) API key"
        let sourceName = cleaner.apiKeySourceName ?? "the provider's developer console"
        alert.informativeText = "Paste the API key from \(sourceName). It is stored in your macOS keychain on this Mac only, never in a project file. Transcript text is sent to \(cleaner.displayName); audio never is."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 4, width: 300, height: 24))
        field.placeholderString = "API key"
        let pasteButton = ClipboardPasteButton(destination: field)
        pasteButton.frame = NSRect(x: 308, y: 0, width: 82, height: 32)
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: 32))
        accessory.addSubview(field)
        accessory.addSubview(pasteButton)
        alert.accessoryView = accessory
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if !Keychain.store(field.stringValue, account: cleaner.rawValue) {
            let failure = NSAlert()
            failure.messageText = "The key was not saved."
            failure.informativeText = "The keychain refused the item, or the field was empty. Nothing was sent."
            failure.runModal()
        }
        refreshProvider(cleaner)
    }

    /// Programmatic AppKit applications do not receive the standard application menu
    /// that an Xcode app template installs. Text fields route Command+V through that
    /// menu, including fields inside a modal alert, so install the ordinary responder-
    /// chain edit actions before any window is shown.
    private func configureApplicationMenu() {
        let mainMenu = NSMenu()

        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(
            withTitle: "Quit sanblueᵈᵒᵗ VoiceFlow",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(
            withTitle: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        editMenu.addItem(
            withTitle: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "Z"
        )
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    private func configureStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.toolTip = "sanblueᵈᵒᵗ VoiceFlow"
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        showStatusIcon()

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        shortcutMenuItem = NSMenuItem(title: "Shortcut", action: nil, keyEquivalent: "")
        shortcutMenuItem.isEnabled = false
        menu.addItem(shortcutMenuItem)

        // The mode switch is a hotkey, so it needs somewhere to be discovered. This row
        // both names the chord and performs the switch when it is clicked.
        modeMenuItem = NSMenuItem(
            title: "Mode",
            action: #selector(cycleProcessingMode),
            keyEquivalent: ""
        )
        modeMenuItem.target = self
        menu.addItem(modeMenuItem)
        updateModeMenuItem()
        menu.addItem(.separator())

        historyMenuItem = NSMenuItem(title: "Recent Dictations (0)", action: nil, keyEquivalent: "")
        historyMenu = NSMenu(title: "Recent Dictations")
        historyMenuItem.submenu = historyMenu
        menu.addItem(historyMenuItem)
        rebuildHistoryMenu()
        menu.addItem(.separator())

        showMenuItem = NSMenuItem(
            title: "Show VoiceFlow",
            action: #selector(toggleControlWindow),
            keyEquivalent: "s"
        )
        showMenuItem.target = self
        menu.addItem(showMenuItem)

        distillationMenuItem = NSMenuItem(
            title: "Keep Distillation Pairs",
            action: #selector(toggleDistillationRecording),
            keyEquivalent: ""
        )
        distillationMenuItem.target = self
        distillationMenuItem.toolTip =
            "Stores the raw and cleaned text of each Gemini dictation on this Mac. "
            + "Delete it with: vf distill clear --yes"
        menu.addItem(distillationMenuItem)
        updateDistillationMenuItem()

        retryMenuItem = NSMenuItem(
            title: "Retry Permissions",
            action: #selector(retryPermissions),
            keyEquivalent: "r"
        )
        retryMenuItem.target = self
        menu.addItem(retryMenuItem)

        let quitItem = NSMenuItem(
            title: "Quit VoiceFlow",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        statusMenu = menu
        // Keep statusItem.menu = nil so left click triggers handleStatusItemClick directly.
        // Right-click or Control-click displays statusMenu via statusItem.popUpMenu(statusMenu).
    }

    private func rebuildHistoryMenu() {
        historyMenu.removeAllItems()
        let count = historyStore.records.count
        historyMenuItem.title = "Recent Dictations (\(count))"

        if historyStore.records.isEmpty {
            let emptyItem = NSMenuItem(title: "No recent dictations", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            historyMenu.addItem(emptyItem)
            return
        }

        for (index, record) in historyStore.records.enumerated() {
            let item = NSMenuItem(
                title: "\(index + 1). \(record.menuTitle)",
                action: #selector(historyItemClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = record.id.uuidString

            let itemSubmenu = NSMenu()
            let copyFinalItem = NSMenuItem(
                title: "📋 Copy Final Text",
                action: #selector(copyHistoryFinalText(_:)),
                keyEquivalent: ""
            )
            copyFinalItem.target = self
            copyFinalItem.representedObject = record.id.uuidString
            itemSubmenu.addItem(copyFinalItem)

            if record.rawText != record.finalText && !record.rawText.isEmpty {
                let copyRawItem = NSMenuItem(
                    title: "🎙️ Copy Raw Transcript",
                    action: #selector(copyHistoryRawText(_:)),
                    keyEquivalent: ""
                )
                copyRawItem.target = self
                copyRawItem.representedObject = record.id.uuidString
                itemSubmenu.addItem(copyRawItem)
            }

            let pasteItem = NSMenuItem(
                title: "⚡ Re-paste at Cursor",
                action: #selector(repasteHistoryItem(_:)),
                keyEquivalent: ""
            )
            pasteItem.target = self
            pasteItem.representedObject = record.id.uuidString
            itemSubmenu.addItem(pasteItem)

            item.submenu = itemSubmenu
            historyMenu.addItem(item)
        }

        historyMenu.addItem(.separator())
        let clearItem = NSMenuItem(
            title: "Clear History",
            action: #selector(clearDictationHistory),
            keyEquivalent: ""
        )
        clearItem.target = self
        historyMenu.addItem(clearItem)
    }

    @objc private func historyItemClicked(_ sender: NSMenuItem) {
        copyHistoryFinalText(sender)
    }

    @objc private func copyHistoryFinalText(_ sender: NSMenuItem) {
        guard let uuidString = sender.representedObject as? String,
              let id = UUID(uuidString: uuidString),
              let record = historyStore.records.first(where: { $0.id == id }) else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.currentText, forType: .string)
        playCompletionSound()
        controlWindow?.addLog("copied from history: \"\(record.menuPreview())\"", isHighlight: true)
    }

    @objc private func copyHistoryRawText(_ sender: NSMenuItem) {
        guard let uuidString = sender.representedObject as? String,
              let id = UUID(uuidString: uuidString),
              let record = historyStore.records.first(where: { $0.id == id }) else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.rawText, forType: .string)
        playCompletionSound()
        controlWindow?.addLog("copied raw transcript from history", isHighlight: true)
    }

    @objc private func repasteHistoryItem(_ sender: NSMenuItem) {
        guard let uuidString = sender.representedObject as? String,
              let id = UUID(uuidString: uuidString),
              let record = historyStore.records.first(where: { $0.id == id }) else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.currentText, forType: .string)
        playCompletionSound()
        AutoPaste.paste(after: 0.15) { [weak self] didAutoPaste, _ in
            let action = didAutoPaste ? "re-pasted" : "copied"
            self?.controlWindow?.addLog("\(action) from history: \"\(record.menuPreview())\"", isHighlight: true)
        }
    }

    @objc private func clearDictationHistory() {
        historyStore.clear()
        saveHistory()
        rebuildHistoryMenu()
        controlWindow?.updateRecentDictations([])
        controlWindow?.addLog("history cleared")
    }

    /// Read the vocabulary and corrections into the Words section.
    private func refreshWords() {
        runWords([], success: nil)
    }

    /// Run Words commands in order, then read the stores again, off the main thread.
    ///
    /// The engine owns both stores, so every change goes through it and the section is
    /// redrawn from what it reports afterwards, never from what the window assumed. A
    /// refusal is shown in the engine's own words: the single-word confirmation, a pair
    /// with a side missing.
    private let wordsQueue = DispatchQueue(label: "dot.sanblue.voiceflow.words", qos: .userInitiated)

    private func runWords(
        _ commands: [WordsCommand],
        success: String?,
        onSuccess: (@MainActor () -> Void)? = nil
    ) {
        guard let configuration else { return }
        controlWindow.setWordsBusy(true)
        let runner = EngineRunner(
            configuration: configuration,
            engineSourceRoot: engineSourceRoot(for: configuration)
        )
        // One serial queue: concurrent Words runs could finish out of order (D-106).
        // `self` is captured weakly once, here, so the nested closure agrees (D-188).
        wordsQueue.async { [weak self] in
            var failure: String?
            for command in commands {
                do {
                    _ = try runner.words(command)
                } catch EngineRunnerError.engineFailed(_, let detail) where !detail.isEmpty {
                    failure = detail
                    break
                } catch {
                    failure = error.localizedDescription
                    break
                }
            }
            let snapshot = try? runner.words(.read)
            DispatchQueue.main.async {
                guard let self else { return }
                self.controlWindow.setWordsBusy(false)
                if let snapshot {
                    self.controlWindow.updateWords(snapshot)
                } else if failure == nil {
                    // A failed read left the section empty with no message (D-106).
                    failure = "your words could not be read · try again"
                }
                if let failure {
                    NSSound.beep()
                    self.controlWindow.setWordsNotice(failure)
                    self.controlWindow.addLog("words · \(failure)", isHighlight: true)
                } else if let success {
                    self.controlWindow.setWordsNotice(success)
                    self.controlWindow.addLog("words · \(success)", isHighlight: true)
                    onSuccess?()
                }
            }
        }
    }

    /// On-demand System Health & Status check (I-84, R7: user-initiated, zero background telemetry).
    private func runHealthCheck() {
        guard let configuration else { return }
        controlWindow.setHealthBusy(true)
        let runner = EngineRunner(
            configuration: configuration,
            engineSourceRoot: engineSourceRoot(for: configuration)
        )
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let rawReport = try? runner.doctor()
            DispatchQueue.main.async {
                guard let self else { return }
                self.controlWindow.setHealthBusy(false)
                if let rawReport, !rawReport.isEmpty {
                    self.controlWindow.setHealthReport(rawReport)
                    self.controlWindow.addLog("diagnostics · complete", isHighlight: true)
                } else {
                    self.controlWindow.setHealthReport("Could not run doctor checks.")
                    self.controlWindow.addLog("diagnostics · failed", isHighlight: true)
                }
            }
        }
    }

    /// Validate the host Python version at engine startup (D-168).
    private func checkPythonRuntime() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "python3", "-c",
                "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}'); sys.exit(0 if sys.version_info >= (3, 11) else 1)"
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    guard let self else { return }
                    if process.terminationStatus != 0 {
                        self.controlWindow.addLog(
                            "warning: Python \(output) detected · VoiceFlow engine requires Python 3.11 or newer",
                            isHighlight: true
                        )
                    } else {
                        self.controlWindow.addLog("python runtime verified (v\(output))")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.controlWindow.addLog(
                        "warning: python3 executable not found on PATH · engine requires Python 3.11+",
                        isHighlight: true
                    )
                }
            }
        }
    }

    /// FIX fixes the dictation it was opened from, not only the next ones.
    ///
    /// Runs only after the engine stored the pair, so a refused pair never changes a row.
    /// The row keeps what was delivered and shows the fix beside it; COPY and RE-PASTE
    /// then hand over the fixed text.
    private func applyLearnedFix(_ request: WordsLearnRequest) {
        guard let id = request.dictation,
              let record = historyStore.records.first(where: { $0.id == id }) else { return }
        var fixed = record.currentText
        var missing: [String] = []
        for pair in request.pairs {
            if let applied = CorrectionApplication.apply(
                heard: pair.heard, intended: pair.intended, to: fixed
            ) {
                fixed = applied
            } else {
                missing.append("\"\(pair.heard)\"")
            }
        }
        guard fixed != record.currentText else {
            controlWindow.setWordsNotice(
                "learned for the next dictations · \(missing.joined(separator: ", ")) is not "
                    + "in what that dictation delivered, so that row is unchanged"
            )
            return
        }
        guard historyStore.attachFix(fixed, to: id) else { return }
        saveHistory()
        rebuildHistoryMenu()
        controlWindow.updateRecentDictations(historyStore.records)
        let partial = missing.isEmpty
            ? ""
            : " · not in that dictation's text, learned only: \(missing.joined(separator: ", "))"
        controlWindow.setWordsNotice(
            "fixed in that dictation and learned for the next ones · COPY or RE-PASTE it from History"
                + partial
        )
        controlWindow.addLog("words · fixed the \(record.timeString) dictation", isHighlight: true)
    }

    private func saveHistory() {
        if !historyStore.save() {
            controlWindow.addLog("the history was not saved · history.local.json could not be written", isHighlight: true)
        }
    }

    @objc private func retryPermissions() {
        guard retryPermissionsAvailable else {
            NSSound.beep()
            return
        }
        authorizeAndStart()
    }

    /// Advance to the next processing mode from anywhere, without opening the station
    /// window.
    ///
    /// Refused while a dictation is in flight: the engine already received the mode it
    /// was given, so switching here would only mislabel a run that cannot change.
    @objc private func cycleProcessingMode() {
        guard controller?.isIdle ?? true else {
            controlWindow.addLog("mode switch ignored · a dictation is still running")
            return
        }
        applyProcessingMode(selectedMode.next, confirmInHUD: true, syncWindow: true)
    }

    /// Put one mode choice everywhere the speaker might look for it: the engine's next
    /// run, the station window, the menu bar, and — when the switch came from the
    /// hotkey — the floating capsule, which is the only surface visible at the time.
    private func applyProcessingMode(
        _ mode: ProcessingMode,
        confirmInHUD: Bool,
        syncWindow: Bool
    ) {
        selectedMode = mode
        controller?.selectMode(mode)
        if syncWindow {
            controlWindow.configureMode(selected: mode)
            controlWindow.addLog("mode switched to: \(mode.rawValue)", isHighlight: true)
        }
        updateModeMenuItem()
        if confirmInHUD {
            floatingHUD.showModeChanged(mode)
        }
    }

    private func updateModeMenuItem() {
        let chord = configuration?.modeShortcut.displayName ?? "⌃⌥M"
        modeMenuItem?.title = "Mode: \(selectedMode.badgeName) — \(chord) to cycle"
    }

    @objc private func toggleDistillationRecording() {
        recordDistillationPairs.toggle()
        UserDefaults.standard.set(
            recordDistillationPairs,
            forKey: AppDelegate.distillationDefaultsKey
        )
        controller?.recordDistillationPairs = recordDistillationPairs
        updateDistillationMenuItem()
        controlWindow.addLog(
            recordDistillationPairs
                ? "distillation: on · each gemini dictation is kept on this Mac"
                : "distillation: off · nothing further is stored",
            isHighlight: true
        )
    }

    private func updateDistillationMenuItem() {
        distillationMenuItem.state = recordDistillationPairs ? .on : .off
    }

    private func setRetryPermissionsAvailable(_ available: Bool) {
        retryPermissionsAvailable = available
        retryMenuItem?.isEnabled = available
        controlWindow?.setRetryPermissionsEnabled(available)
    }

    @objc private func showControlWindow() {
        controlWindow.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        updateShowMenuItemTitle()
    }

    @objc private func toggleControlWindow() {
        guard let window = controlWindow.window else {
            showControlWindow()
            return
        }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            showControlWindow()
        }
        updateShowMenuItemTitle()
    }

    private func updateShowMenuItemTitle() {
        guard let showMenuItem else { return }
        if controlWindow?.window?.isVisible == true {
            showMenuItem.title = "Hide VoiceFlow"
        } else {
            showMenuItem.title = "Show VoiceFlow"
        }
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) == true) {
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            toggleControlWindow()
        }
    }

    /// The status item shows either the icon or a one-character state marker, and
    /// `imagePosition` has to travel with it. A button left on `.imageOnly` with no image
    /// draws nothing at all, and an empty menu bar is indistinguishable from an app that
    /// is not running — which is exactly what the recording, processing, success and
    /// failure states looked like.
    private func showStatusIcon() {
        guard let button = statusItem.button else { return }
        button.image = Self.makeMeowBubbleIcon()
        button.title = ""
        button.imagePosition = .imageOnly
    }

    private func showStatusMarker(_ marker: String) {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.title = marker
        button.imagePosition = .noImage
    }

    /// Meow-Bubble: a speech bubble with pointy cat ears and sound dots.
    /// Vector template image: black fill/stroke with alpha, automatically tinted
    /// by macOS for dark/light menubar and active state.
    static func makeMeowBubbleIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            ctx.saveGState()

            // Map 24x24 SVG coordinate space into rect (with Y inverted so (0,0) is top-left like SVG)
            let scaleX = rect.width / 24.0
            let scaleY = rect.height / 24.0
            ctx.translateBy(x: 0, y: rect.height)
            ctx.scaleBy(x: scaleX, y: -scaleY)

            let color = NSColor.black.cgColor
            ctx.setStrokeColor(color)
            ctx.setFillColor(color)
            ctx.setLineWidth(1.8)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            // 1. Cat Ears (Solid Polygons)
            let leftEar = CGMutablePath()
            leftEar.move(to: CGPoint(x: 6, y: 5))
            leftEar.addLine(to: CGPoint(x: 4, y: 1))
            leftEar.addLine(to: CGPoint(x: 9, y: 3.5))
            leftEar.closeSubpath()
            ctx.addPath(leftEar)
            ctx.fillPath()

            let rightEar = CGMutablePath()
            rightEar.move(to: CGPoint(x: 18, y: 5))
            rightEar.addLine(to: CGPoint(x: 20, y: 1))
            rightEar.addLine(to: CGPoint(x: 15, y: 3.5))
            rightEar.closeSubpath()
            ctx.addPath(rightEar)
            ctx.fillPath()

            // 2. Speech Bubble Outline
            let bubble = CGMutablePath()
            bubble.move(to: CGPoint(x: 4, y: 11))
            bubble.addCurve(to: CGPoint(x: 12, y: 4), control1: CGPoint(x: 4, y: 7), control2: CGPoint(x: 7.5, y: 4))
            bubble.addCurve(to: CGPoint(x: 20, y: 11), control1: CGPoint(x: 16.5, y: 4), control2: CGPoint(x: 20, y: 7))
            bubble.addCurve(to: CGPoint(x: 12, y: 18), control1: CGPoint(x: 20, y: 15), control2: CGPoint(x: 16.5, y: 18))
            bubble.addCurve(to: CGPoint(x: 8.7, y: 17.4), control1: CGPoint(x: 10.8, y: 18), control2: CGPoint(x: 9.7, y: 17.8))
            bubble.addLine(to: CGPoint(x: 4, y: 19))
            bubble.addLine(to: CGPoint(x: 4.8, y: 15.6))
            bubble.addCurve(to: CGPoint(x: 4, y: 11), control1: CGPoint(x: 4.3, y: 14.3), control2: CGPoint(x: 4, y: 12.7))
            bubble.closeSubpath()
            ctx.addPath(bubble)
            ctx.strokePath()

            // 3. Three sound/dictation dots in the center
            let dotRadius: CGFloat = 0.9
            for cx in [9.0, 12.0, 15.0] {
                let dotRect = CGRect(x: cx - dotRadius, y: 11.0 - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                ctx.fillEllipse(in: dotRect)
            }

            ctx.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func openInputMonitoringSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openAccessibilitySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func authorizeAndStart() {
        guard let configuration else { return }

        // A hold may be in flight. Dropping the controller under it left the arm timer
        // pointing at an object nothing owned, and the speaker was told nothing at all —
        // unlike the ordinary refusal, which says the touch was too short.
        if controller?.isCancellable == true {
            controller?.cancelRecording()
        }

        setRetryPermissionsAvailable(false)

        hotkeyMonitor?.stop()
        hotkeyMonitor = nil
        controller = nil
        globalHotkeyAvailable = false
        controlWindow.setRecordingEnabled(false)

        statusMenuItem.title = "Waiting for microphone permission…"
        controlWindow.update(
            title: "Microphone permission",
            detail: "Allow microphone access to enable local recording."
        )
        AudioRecorder.requestAccess { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.updateStatus(
                        .failed("Grant Microphone access, then choose Retry Permissions.")
                    )
                    return
                }
                self.startRuntime(configuration: configuration)
            }
        }
    }

    private func startRuntime(configuration: VoiceFlowConfiguration) {
        // Permission callbacks are asynchronous, so two Retry taps can both arrive
        // here. Replacing a live monitor without stopping it would leave its event tap
        // registered on the run loop with a dangling unretained callback context.
        hotkeyMonitor?.stop()
        hotkeyMonitor = nil
        globalHotkeyAvailable = false

        let controller = VoiceFlowController(
            configuration: configuration,
            engineSourceRoot: engineSourceRoot(for: configuration)
        )
        // The speaker can choose a provider while microphone permission is pending.
        // Carry that visible choice into the newly-created controller.
        controller.selectCleaner(selectedCleaner)
        controller.selectMode(selectedMode)
        controller.selectGeminiModel(selectedGeminiModel)
        controller.selectSpeechEngine(selectedSpeechEngine)
        controller.recordDistillationPairs = recordDistillationPairs
        controller.onStatusChange = { [weak self] status in
            self?.updateStatus(status)
        }
        controller.sweepStrandedTakes()
        checkPythonRuntime()

        self.controller = controller
        controlWindow.setRecordingEnabled(true)

        if CGPreflightListenEventAccess() {
            let monitor = HotkeyMonitor(
                shortcut: configuration.shortcut,
                modeShortcut: configuration.modeShortcut,
                onPressed: { [weak controller] in controller?.shortcutPressed() },
                onReleased: { [weak controller] in controller?.shortcutReleased() },
                onModeCycle: { [weak self] in
                    DispatchQueue.main.async { self?.cycleProcessingMode() }
                },
                onCancel: { [weak controller] in
                    DispatchQueue.main.async { controller?.cancelRecording() }
                }
            )
            do {
                try monitor.start()
                hotkeyMonitor = monitor
                globalHotkeyAvailable = true
            } catch {
                globalHotkeyAvailable = false
            }
        } else {
            _ = CGRequestListenEventAccess()
        }
        updateStatus(.idle)
    }

    private var statusIconTask: Task<Void, Never>?

    private func updateStatus(_ status: VoiceFlowStatus) {
        statusIconTask?.cancel()
        statusIconTask = nil
        switch status {
        case .idle:
            setRetryPermissionsAvailable(true)
            controlWindow.setProviderSelectionEnabled(true)
            showStatusIcon()
            let shortcut = configuration?.shortcut.displayName ?? "Fn/Globe"
            if globalHotkeyAvailable {
                statusMenuItem.title = "Ready — hold \(shortcut) or the button"
                controlWindow.update(
                    title: "Ready",
                    detail: "Hold \(shortcut) anywhere, or hold the button below."
                )
            } else {
                statusMenuItem.title = "Button ready — Fn needs Input Monitoring"
                controlWindow.update(
                    title: "Button ready",
                    detail: "Hold the button below. Enable Input Monitoring and Retry for Fn/Globe."
                )
            }
        case .cancelled(let reason):
            // A recording taken back leaves nothing behind: no paste, no history entry,
            // no audio. Both cases are said out loud, because a trigger that quietly
            // does nothing is indistinguishable from one that is broken.
            setRetryPermissionsAvailable(true)
            controlWindow.setProviderSelectionEnabled(true)
            showStatusIcon()
            switch reason {
            case .tooShort:
                let seconds = configuration?.holdDelaySeconds ?? 0.5
                controlWindow.addLog(
                    String(format: "ignored a touch shorter than %.1fs · the microphone stayed closed", seconds)
                )
                floatingHUD.hideImmediately()
            case .escaped:
                controlWindow.addLog("recording cancelled · the audio was discarded", isHighlight: true)
                floatingHUD.showCancelled()
            case .refused(let refusal):
                controlWindow.addLog(refusal, isHighlight: true)
                floatingHUD.showFailed(message: refusal)
            }
            updateStatus(.idle)

        case .recording:
            setRetryPermissionsAvailable(false)
            controlWindow.setProviderSelectionEnabled(false)
            showStatusMarker("●")
            statusMenuItem.title = "Recording… release to transcribe"
            let shortcut = configuration?.shortcut.displayName ?? "Fn/Globe"
            let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Desktop"
            let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let targetContext = AppContext.resolve(bundleIdentifier: frontBundle, localizedName: frontApp)
            controlWindow.updateTelemetry(targetApp: frontApp, targetBundleId: frontBundle)
            controlWindow.update(
                title: "Recording…",
                detail: "Release \(shortcut) or the button to transcribe the audio locally."
            )
            floatingHUD.showRecording(
                cleanerName: selectedCleaner.rawValue,
                mode: selectedMode,
                speechLabel: RunLabels.speech(selectedSpeechEngine),
                runsModel: RunLabels.runsModel(
                    cleaner: selectedCleaner, mode: selectedMode, speech: selectedSpeechEngine
                ),
                context: targetContext
            ) { [weak self] in
                let level = self?.controller?.currentAudioLevel ?? 0.0
                self?.controlWindow.updateAudioLevel(Double(level))
                return level
            }
        case .processing:
            setRetryPermissionsAvailable(false)
            controlWindow.setProviderSelectionEnabled(false)
            showStatusMarker("…")
            floatingHUD.showProcessing()
            if selectedCleaner.isCloud {
                statusMenuItem.title = "Cleaning transcript with \(selectedCleaner.displayName)…"
                controlWindow.update(
                    title: "Cleaning transcript with \(selectedCleaner.displayName)…",
                    detail: "Only transcript text is sent. Audio stays on this Mac."
                )
            } else {
                statusMenuItem.title = "Processing locally…"
                controlWindow.update(
                    title: "Processing locally…",
                    detail: "The recording stays on this Mac."
                )
            }
        case .copied(
            let elapsed,
            let usedFallback,
            let acceptanceCount,
            let acceptanceError,
            let audioCleanupError,
            let model,
            let runMode,
            let result,
            let spokenSeconds,
            let runCleaner
        ):
            setRetryPermissionsAvailable(true)
            controlWindow.setProviderSelectionEnabled(true)
            showStatusMarker("✓")
            playCompletionSound()
            // Kept so a newer status cancels it: left running it erased a later `!`
            // marker 2.5 s after the success it belonged to (D-169).
            statusIconTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { return }
                if self.controller?.isIdle != false {
                    self.showStatusIcon()
                }
            }

            // Speech recognition did half the work and left no trace: the MIC/STT filter
            // read zero however much was dictated. One line per run, naming the language
            // the engine chose and what it returned, so the filter has something to show
            // and a misheard word can be found where it happened.
            let heardPreview = result.rawText.count > 90
                ? String(result.rawText.prefix(90)) + "…"
                : result.rawText
            controlWindow.addLog(
                // The engine that listened, not always Whisper (D-80).
                "\(selectedSpeechEngine == .parakeet ? "parakeet" : "whisper") heard: \"\(heardPreview)\"",
                category: .stt
            )

            // Clear before anything can return early. An executed voice action used to
            // skip this, leaving a card from an older run on screen; USE THIS then
            // copied text that belonged to a dictation the speaker had moved past.
            self.controlWindow.showRejectedCleanup(result.rejectedText)

            // R3c: a dictation is examined for a spoken command only in the mode the
            // speaker selected for it. Parsing every dictation meant a sentence that
            // merely opened like an instruction was executed instead of written, and
            // the speaker had no way to say which one they meant.
            let detectedAction = runMode.parsesVoiceActions
                ? (VoiceActionParser.parse(text: result.finalText)
                    ?? VoiceActionParser.parse(text: result.rawText))
                : nil
            if let action = detectedAction {
                let execution = VoiceActionExecutor.execute(action)
                if execution.isSuccess {
                    // Name what the executor actually did. A spoken app name with no app
                    // behind it opens that name's website, and saying "Open App" there
                    // would report something that did not happen.
                    let performed = execution.label(for: action)
                    floatingHUD.showActionExecuted(description: performed)

                    let record = DictationRecord(
                        rawText: result.rawText,
                        personalizedText: result.personalizedText,
                        finalText: performed,
                        cleaner: runCleaner.rawValue,
                        mode: "action",
                        model: model,
                        latencySeconds: elapsed,
                        usedFallback: usedFallback,
                        fallbackReason: result.fallbackReason?.summary,
                        didAutoPaste: false
                    )
                    self.historyStore.append(record)
                    self.saveHistory()
                    self.rebuildHistoryMenu()
                    self.controlWindow.updateRecentDictations(self.historyStore.records)
                    self.controlWindow.markDeliveredThisSession()

                    let resultMsg = "⚡ action: \(performed)"
                    self.statusMenuItem.title = String(format: "%@ · in %.1f seconds", resultMsg, elapsed)
                    self.controlWindow.addLog("\(resultMsg) (from: \"\(result.finalText)\")", isHighlight: true)
                    self.controlWindow.update(
                        title: "Executed: \(performed)",
                        detail: String(format: "Matched \"\(result.finalText)\" · %.1fs", elapsed)
                    )
                    return
                }
                self.controlWindow.addLog("action not executed: \(action.displayDescription) · continuing dictation")
                // The controller left the clipboard alone for a command; a command that
                // did not run is dictation again, so its text is copied now (D-50).
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.finalText, forType: .string)
            }

            // ACTION mode with nothing recognized. Pasting in silence here is what made
            // the mode look broken: the speaker asked for a command to be looked for and
            // got the same result as every other mode, with nothing saying why.
            let unrecognizedCommand = runMode.parsesVoiceActions && detectedAction == nil
            if unrecognizedCommand {
                self.controlWindow.addLog(
                    "no action recognized · dictated instead: \"\(result.finalText)\"",
                    isHighlight: true
                )
            }

            // Snippets are already expanded. The engine runs the one scan R5b allows,
            // over the same store this window edits, and reports the result as
            // `final_text`. A second scan here re-matched the payload of the first
            // expansion and delivered a string neither pass produces alone, while the
            // history recorded that string and the engine's telemetry recorded another.
            let deliveredText = result.finalText

            // The paste outcome is only known once the deferred keystroke has run its
            // decisive target check, so every label that depends on it is written from
            // inside the completion rather than guessed beforehand.
            AutoPaste.paste { [weak self] didAutoPaste, flattened in
                guard let self else { return }
                // Spoken words, not delivered ones: a translation, notes or a snippet
                // expansion changed the count without the speaker saying more (D-26).
                let wordCount = result.rawText.split(whereSeparator: \.isWhitespace).count
                let measuredWPM: Int? = spokenSeconds >= 0.5 && wordCount > 0
                    ? Int((Double(wordCount) / spokenSeconds) * 60.0)
                    : nil
                let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Desktop"
                let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                let targetContext = AppContext.resolve(bundleIdentifier: frontBundle, localizedName: frontApp)

                self.floatingHUD.showCompleted(
                    didAutoPaste: didAutoPaste,
                    usedFallback: usedFallback,
                    model: model,
                    latencySeconds: elapsed,
                    wpm: measuredWPM,
                    targetContext: targetContext,
                    unrecognizedCommand: unrecognizedCommand
                )
                let record = DictationRecord(
                    rawText: result.rawText,
                    personalizedText: result.personalizedText,
                    finalText: flattened ?? deliveredText,
                    cleaner: runCleaner.rawValue,
                    mode: runMode.rawValue,
                    model: model,
                    latencySeconds: elapsed,
                    usedFallback: usedFallback,
                    fallbackReason: result.fallbackReason?.summary,
                    didAutoPaste: didAutoPaste
                )
                self.historyStore.append(record)
                self.saveHistory()
                self.rebuildHistoryMenu()
                self.controlWindow.updateRecentDictations(self.historyStore.records)

                self.controlWindow.updateRunTelemetry(
                    sttLatency: result.transcribeSeconds,
                    llmLatency: runCleaner == .literal ? nil : result.cleanupSeconds,
                    wpm: measuredWPM
                )
                self.controlWindow.updateTelemetry(targetApp: frontApp, targetBundleId: frontBundle)

                let actionVerb = didAutoPaste ? "Pasted" : "Copied"
                // Name which side refused. "safe fallback" alone described the guard
                // rejecting a cleanup and the provider never answering with the same
                // words, and those call for opposite responses: shorten the sentence,
                // or wait and try a local engine.
                if let reason = result.fallbackReason {
                    self.controlWindow.addLog(
                        "fallback · \(reason.summary) · the transcript was delivered instead",
                        isHighlight: true
                    )
                }
                let prefix = result.fallbackReason.map { "\(actionVerb) fallback · \($0.summary)" }
                    ?? actionVerb
                // Name the model that answered, not the one that was asked for, so a
                // capacity fallback is visible instead of silent.
                let modelNote = model.map { " · \($0)" } ?? ""
                let hasWarning = acceptanceError != nil || audioCleanupError != nil
                let warning = hasWarning ? " · warning" : ""
                if let acceptanceCount {
                    self.statusMenuItem.title = String(
                        format: "Acceptance %d · %@ in %.1f seconds%@",
                        acceptanceCount,
                        prefix,
                        elapsed,
                        warning
                    )
                } else {
                    self.statusMenuItem.title = String(
                        format: "%@ in %.1f seconds%@",
                        prefix,
                        elapsed,
                        warning
                    )
                }
                let acceptanceDetail = acceptanceCount.map { "Acceptance \($0) saved · " } ?? ""
                let failureDetail = acceptanceError.map {
                    "Acceptance evidence was not saved: \($0) · "
                } ?? ""
                let privacyDetail = audioCleanupError.map { "\($0) · " } ?? ""
                let pasteHint = didAutoPaste
                    ? "Pasted automatically"
                    : "Ready to paste with Command+V"
                self.controlWindow.update(
                    title: prefix,
                    detail: acceptanceDetail + failureDetail + privacyDetail
                        + String(format: "%@%@ · %.1f seconds", pasteHint, modelNote, elapsed)
                )
            }
        case .failed(let message):
            setRetryPermissionsAvailable(true)
            controlWindow.setProviderSelectionEnabled(true)
            showStatusMarker("!")
            statusMenuItem.title = message
            floatingHUD.showFailed(message: message)
            controlWindow.update(title: "VoiceFlow needs attention", detail: message)
        }
    }

    private func playCompletionSound() {
        if let sound = NSSound(named: NSSound.Name("Glass")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private func defaultProjectRoot() -> URL {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .standardizedFileURL
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .standardizedFileURL
    }

    private func validate(_ configuration: VoiceFlowConfiguration) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: configuration.whisperModel.path) else {
            throw ValidationError.missingWhisperModel(configuration.whisperModel.path)
        }
        let sourcePath = engineSourceRoot(for: configuration).path
        guard fileManager.fileExists(atPath: sourcePath) else {
            throw ValidationError.missingEngineSource(sourcePath)
        }
    }

    /// A packaged application executes the Python source sealed inside its own signed
    /// bundle. Development runs continue to use the project source tree.
    private func engineSourceRoot(for configuration: VoiceFlowConfiguration) -> URL {
        if Bundle.main.bundleURL.pathExtension == "app", let resources = Bundle.main.resourceURL {
            return resources
                .appendingPathComponent("python", isDirectory: true)
                .appendingPathComponent("src", isDirectory: true)
        }
        return configuration.projectRoot.appendingPathComponent("src", isDirectory: true)
    }
}

/// A visible fallback for people whose keyboard shortcut is unavailable. The API key
/// remains only in the system pasteboard, this secure field, and then the keychain; the
/// button never logs it or retains its own copy.
private final class ClipboardPasteButton: NSButton {
    private weak var destination: NSSecureTextField?

    init(destination: NSSecureTextField) {
        self.destination = destination
        super.init(frame: .zero)
        title = "Paste"
        bezelStyle = .rounded
        target = self
        action = #selector(pasteFromClipboard)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    @objc private func pasteFromClipboard() {
        guard let value = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !value.isEmpty else {
            NSSound.beep()
            return
        }
        destination?.stringValue = value
    }
}

private enum ValidationError: LocalizedError {
    case missingWhisperModel(String)
    case missingEngineSource(String)

    var errorDescription: String? {
        switch self {
        case .missingWhisperModel(let path): return "Whisper model not found: \(path)"
        case .missingEngineSource(let path): return "Engine source not found: \(path)"
        }
    }
}
