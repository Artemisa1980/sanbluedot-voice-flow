import AppKit
import CoreGraphics
import Foundation
import VoiceFlowMacCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var shortcutMenuItem: NSMenuItem!
    private var retryMenuItem: NSMenuItem!
    private var controlWindow: ControlWindowController!
    private var configuration: VoiceFlowConfiguration?
    private var controller: VoiceFlowController?
    private var hotkeyMonitor: HotkeyMonitor?
    private var globalHotkeyAvailable = false
    private var selectedCleaner = CleanerMode.literal
    private var selectedMode = ProcessingMode.clean

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
    private var historyStore: DictationHistoryStore = {
        if let data = UserDefaults.standard.data(forKey: DictationHistoryStore.defaultsKey),
           let store = DictationHistoryStore.load(from: data) {
            return store
        }
        return DictationHistoryStore()
    }()
    private var snippetStore: VoiceSnippetStore = VoiceSnippetStore.load()
    private var historyMenuItem: NSMenuItem!
    private var historyMenu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureApplicationMenu()

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
            selectedCleaner = configuration.cleaner
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
            authorizeAndStart()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
        controlWindow.configureRecording(
            onPress: { [weak self] in self?.controller?.shortcutPressed() },
            onRelease: { [weak self] in self?.controller?.shortcutReleased() }
        )
        controlWindow.configureProviders(
            available: CleanerMode.allCases,
            selected: selectedCleaner
        )
        controlWindow.configureMode(selected: selectedMode)
        controlWindow.configureGeminiModel(selected: selectedGeminiModel)
        controlWindow.onCleanerChange = { [weak self] cleaner in
            self?.selectedCleaner = cleaner
            self?.controller?.selectCleaner(cleaner)
            self?.refreshProvider(cleaner)
        }
        controlWindow.onModeChange = { [weak self] mode in
            guard let self else { return }
            self.selectedMode = mode
            self.controller?.selectMode(mode)
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
            pasteboard.setString(record.finalText, forType: .string)
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
            pasteboard.setString(record.finalText, forType: .string)
            self?.playCompletionSound()
            NSApplication.shared.hide(nil)
            AutoPaste.paste(after: 0.15) { [weak self] didAutoPaste in
                let action = didAutoPaste ? "re-pasted" : "copied"
                self?.controlWindow?.addLog("\(action) from history: \"\(record.menuPreview())\"", isHighlight: true)
            }
        }
        controlWindow.onClearHistory = { [weak self] in
            self?.clearDictationHistory()
        }
        controlWindow.updateSnippets(snippetStore.snippets)
        controlWindow.onAddSnippet = { [weak self] trigger, expansion, description in
            guard let self else { return }
            if let snip = self.snippetStore.add(trigger: trigger, expansion: expansion, description: description) {
                self.snippetStore.save()
                self.controlWindow.updateSnippets(self.snippetStore.snippets)
                self.controlWindow.addLog("added voice snippet [\(snip.trigger)]", isHighlight: true)
            }
        }
        controlWindow.onDeleteSnippet = { [weak self] id in
            guard let self else { return }
            if self.snippetStore.delete(id: id) {
                self.snippetStore.save()
                self.controlWindow.updateSnippets(self.snippetStore.snippets)
                self.controlWindow.addLog("deleted voice snippet", isHighlight: true)
            }
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
        statusItem.button?.title = "VF"

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        shortcutMenuItem = NSMenuItem(title: "Shortcut", action: nil, keyEquivalent: "")
        shortcutMenuItem.isEnabled = false
        menu.addItem(shortcutMenuItem)
        menu.addItem(.separator())

        historyMenuItem = NSMenuItem(title: "Recent Dictations (0)", action: nil, keyEquivalent: "")
        historyMenu = NSMenu(title: "Recent Dictations")
        historyMenuItem.submenu = historyMenu
        menu.addItem(historyMenuItem)
        rebuildHistoryMenu()
        menu.addItem(.separator())

        let showItem = NSMenuItem(
            title: "Show VoiceFlow",
            action: #selector(showControlWindow),
            keyEquivalent: "s"
        )
        showItem.target = self
        menu.addItem(showItem)

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
        statusItem.menu = menu
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
        pasteboard.setString(record.finalText, forType: .string)
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
        pasteboard.setString(record.finalText, forType: .string)
        playCompletionSound()
        AutoPaste.paste(after: 0.15) { [weak self] didAutoPaste in
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

    private func saveHistory() {
        if let data = historyStore.encode() {
            UserDefaults.standard.set(data, forKey: DictationHistoryStore.defaultsKey)
        }
    }

    @objc private func retryPermissions() {
        guard retryPermissionsAvailable else {
            NSSound.beep()
            return
        }
        authorizeAndStart()
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
        controller.recordDistillationPairs = recordDistillationPairs
        controller.onStatusChange = { [weak self] status in
            self?.updateStatus(status)
        }

        self.controller = controller
        controlWindow.setRecordingEnabled(true)

        if CGPreflightListenEventAccess() {
            let monitor = HotkeyMonitor(
                shortcut: configuration.shortcut,
                onPressed: { [weak controller] in controller?.shortcutPressed() },
                onReleased: { [weak controller] in controller?.shortcutReleased() }
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

    private func updateStatus(_ status: VoiceFlowStatus) {
        switch status {
        case .idle:
            setRetryPermissionsAvailable(true)
            controlWindow.setProviderSelectionEnabled(true)
            statusItem.button?.title = "VF"
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
        case .recording:
            setRetryPermissionsAvailable(false)
            controlWindow.setProviderSelectionEnabled(false)
            statusItem.button?.title = "●"
            statusMenuItem.title = "Recording… release to transcribe"
            let shortcut = configuration?.shortcut.displayName ?? "Fn/Globe"
            let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Desktop"
            let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            controlWindow.updateTelemetry(targetApp: frontApp, targetBundleId: frontBundle)
            controlWindow.update(
                title: "Recording…",
                detail: "Release \(shortcut) or the button to transcribe the audio locally."
            )
            floatingHUD.showRecording(
                cleanerName: selectedCleaner.rawValue,
                mode: selectedMode
            ) { [weak self] in
                let level = self?.controller?.currentAudioLevel ?? 0.0
                self?.controlWindow.updateAudioLevel(Double(level))
                return level
            }
        case .processing:
            setRetryPermissionsAvailable(false)
            controlWindow.setProviderSelectionEnabled(false)
            statusItem.button?.title = "…"
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
            let result,
            let spokenSeconds
        ):
            setRetryPermissionsAvailable(true)
            controlWindow.setProviderSelectionEnabled(true)
            statusItem.button?.title = "✓"
            playCompletionSound()

            // Check if spoken text matches a Voice Action
            let detectedAction = VoiceActionParser.parse(text: result.finalText) ?? VoiceActionParser.parse(text: result.rawText)
            if let action = detectedAction {
                let execution = VoiceActionExecutor.execute(action)
                if execution.isSuccess {
                    floatingHUD.showActionExecuted(description: action.displayDescription)

                    let record = DictationRecord(
                        rawText: result.rawText,
                        personalizedText: result.personalizedText,
                        finalText: action.displayDescription,
                        cleaner: self.selectedCleaner.rawValue,
                        mode: "action",
                        model: model,
                        latencySeconds: elapsed,
                        usedFallback: usedFallback,
                        didAutoPaste: false
                    )
                    self.historyStore.append(record)
                    self.saveHistory()
                    self.rebuildHistoryMenu()
                    self.controlWindow.updateRecentDictations(self.historyStore.records)

                    let resultMsg = "⚡ action: \(action.displayDescription)"
                    self.statusMenuItem.title = String(format: "%@ · in %.1f seconds", resultMsg, elapsed)
                    self.controlWindow.addLog("\(resultMsg) (from: \"\(result.finalText)\")", isHighlight: true)
                    self.controlWindow.update(
                        title: "Executed: \(action.displayDescription)",
                        detail: String(format: "Matched \"\(result.finalText)\" · %.1fs", elapsed)
                    )
                    return
                }
                self.controlWindow.addLog("action not executed: \(action.displayDescription) · continuing dictation")
            }

            // Expand voice snippets if registered
            let deliveredText = self.snippetStore.expand(text: result.finalText)
            if deliveredText != result.finalText {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(deliveredText, forType: .string)
            }

            // The paste outcome is only known once the deferred keystroke has run its
            // decisive target check, so every label that depends on it is written from
            // inside the completion rather than guessed beforehand.
            AutoPaste.paste { [weak self] didAutoPaste in
                guard let self else { return }
                self.floatingHUD.showCompleted(
                    didAutoPaste: didAutoPaste,
                    usedFallback: usedFallback,
                    model: model
                )
                let record = DictationRecord(
                    rawText: result.rawText,
                    personalizedText: result.personalizedText,
                    finalText: deliveredText,
                    cleaner: self.selectedCleaner.rawValue,
                    mode: self.selectedMode.rawValue,
                    model: model,
                    latencySeconds: elapsed,
                    usedFallback: usedFallback,
                    didAutoPaste: didAutoPaste
                )
                self.historyStore.append(record)
                self.saveHistory()
                self.rebuildHistoryMenu()
                self.controlWindow.updateRecentDictations(self.historyStore.records)

                // Telemetry carries only what was measured. The engine reports the
                // seconds each stage actually spent; when it reports none the chip is
                // left empty rather than filled with a plausible number, and the rate
                // is words over the time the speaker spoke, not over processing time.
                let wordCount = deliveredText.split(whereSeparator: \.isWhitespace).count
                let measuredWPM: Int? = spokenSeconds >= 0.5 && wordCount > 0
                    ? Int((Double(wordCount) / spokenSeconds) * 60.0)
                    : nil
                let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Desktop"
                let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                self.controlWindow.updateTelemetry(
                    sttLatency: result.transcribeSeconds,
                    llmLatency: self.selectedCleaner == .literal ? nil : result.cleanupSeconds,
                    wpm: measuredWPM,
                    targetApp: frontApp,
                    targetBundleId: frontBundle
                )

                let actionVerb = didAutoPaste ? "Pasted" : "Copied"
                let prefix = usedFallback ? "\(actionVerb) safe fallback" : actionVerb
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
            statusItem.button?.title = "!"
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
