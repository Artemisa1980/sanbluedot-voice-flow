import AppKit
import SwiftUI
import VoiceFlowMacCore

final class FloatingHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: HUDLayout.panelWidth,
                height: HUDLayout.panelHeight
            ),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}

final class MicroduckHUDHostingView: NSHostingView<RetroMicHUDView> {
    var isBubbleVisible: Bool = false
    var isDuckVisible: Bool = true
    var onDuckClicked: (() -> Void)?
    var onWindowDragEnded: (() -> Void)?
    var onWindowDragged: ((NSPoint) -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?
    var onActivity: (() -> Void)?

    private var initialMouseLocation: NSPoint?
    private var initialWindowOrigin: NSPoint?
    private var isDraggingDuck: Bool = false

    private var mascotRect: NSRect {
        guard isDuckVisible else { return .zero }
        return NSRect(
            x: 0,
            y: HUDLayout.panelHeight - HUDLayout.duckHeight,
            width: HUDLayout.duckWidth,
            height: HUDLayout.duckHeight
        )
    }

    private var bubbleRect: NSRect {
        guard isBubbleVisible else { return .zero }
        let bubbleX = isDuckVisible ? HUDLayout.duckToBubble : 0
        return NSRect(
            x: bubbleX,
            y: HUDLayout.panelHeight - HUDLayout.capsuleFullSize.height - 20,
            width: HUDLayout.bubbleWidth,
            height: HUDLayout.capsuleFullSize.height + 20
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if mascotRect.contains(point) {
            return self
        }
        if bubbleRect.contains(point) {
            return self
        }
        // Clicks outside duck/bubble pass directly through to desktop & apps behind
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if mascotRect.contains(point) {
            onActivity?()
            if event.modifierFlags.contains(.control) {
                onContextMenu?(event)
                return
            }
            initialMouseLocation = NSEvent.mouseLocation
            initialWindowOrigin = window?.frame.origin
            isDraggingDuck = false
            return
        }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if mascotRect.contains(point) {
            onActivity?()
            onContextMenu?(event)
            return
        }
        super.rightMouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startMouse = initialMouseLocation, let startOrigin = initialWindowOrigin, let window else {
            super.mouseDragged(with: event)
            return
        }
        let currentMouse = NSEvent.mouseLocation
        let dx = currentMouse.x - startMouse.x
        let dy = currentMouse.y - startMouse.y
        if abs(dx) > 2 || abs(dy) > 2 {
            isDraggingDuck = true
            let rawOrigin = NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy)
            let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(currentMouse, $0.frame, false) }) ?? window.screen ?? NSScreen.main
            let finalOrigin: NSPoint
            if let screen = targetScreen {
                let screenRect = screen.visibleFrame
                let clampedX = min(max(rawOrigin.x, screenRect.minX), screenRect.maxX - HUDLayout.panelWidth)
                let clampedY = min(max(rawOrigin.y, screenRect.minY), screenRect.maxY - HUDLayout.panelHeight)
                finalOrigin = NSPoint(x: clampedX, y: clampedY)
            } else {
                finalOrigin = rawOrigin
            }
            window.setFrameOrigin(finalOrigin)
            onWindowDragged?(finalOrigin)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let _ = initialMouseLocation {
            if !isDraggingDuck {
                onDuckClicked?()
            } else {
                onWindowDragEnded?()
            }
            initialMouseLocation = nil
            initialWindowOrigin = nil
            isDraggingDuck = false
            return
        }
        super.mouseUp(with: event)
    }
}

final class FloatingHUDController {
    private let panel = FloatingHUDPanel()
    private let viewModel = HUDViewModel()
    private var hostingView: MicroduckHUDHostingView!
    private var meterTimer: Timer?
    private var processingTimer: Timer?
    private var dismissWorkItem: DispatchWorkItem?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var animationGeneration: Int = 0

    var menuProvider: (() -> NSMenu?)?

    var isStanding: Bool {
        viewModel.userPrefersStanding
    }

    func toggleStanding() {
        viewModel.toggleStanding()
    }

    var edition: MicroduckEdition {
        viewModel.edition
    }

    func setEdition(_ edition: MicroduckEdition) {
        viewModel.setEdition(edition)
    }

    var isSleeping: Bool {
        viewModel.forceSleeping || (ProcessInfo.processInfo.systemUptime - viewModel.lastActivityTime > 300.0)
    }

    func toggleSleep() {
        viewModel.toggleSleep()
    }

    private var isCompanionEnabled: Bool {
        UserDefaults.standard.object(forKey: "microduck.companionVisible") as? Bool ?? true
    }

    init() {
        let host = MicroduckHUDHostingView(rootView: RetroMicHUDView(viewModel: viewModel))
        host.frame = panel.contentRect(forFrameRect: panel.frame)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.onDuckClicked = { [weak self] in
            self?.viewModel.toggleStanding()
        }
        host.onContextMenu = { [weak self] event in
            guard let self, let menu = self.menuProvider?() else { return }
            let point = self.hostingView.convert(event.locationInWindow, from: nil)
            menu.popUp(positioning: nil, at: point, in: self.hostingView)
        }
        host.onWindowDragEnded = { [weak self] in
            self?.savePosition()
        }
        host.onWindowDragged = { [weak self] origin in
            self?.viewModel.panelOrigin = origin
        }
        host.onActivity = { [weak self] in
            self?.viewModel.recordActivity()
        }
        self.hostingView = host
        panel.contentView = host

        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.viewModel.isVisible = false
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.isCompanionEnabled {
                self.viewModel.isVisible = true
            }
        }

        positionPanel()
        viewModel.panelOrigin = panel.frame.origin
        if isCompanionEnabled {
            showIdle()
        }
    }

    deinit {
        meterTimer?.invalidate()
        processingTimer?.invalidate()
        dismissWorkItem?.cancel()
        if let obs = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    func setCompanionVisible(_ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: "microduck.companionVisible")
        if visible {
            showIdle()
        } else {
            fadeOut()
        }
    }

    func showIdle() {
        animationGeneration += 1
        meterTimer?.invalidate()
        meterTimer = nil
        processingTimer?.invalidate()
        processingTimer = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        viewModel.mode = .idle
        hostingView?.isBubbleVisible = false
        showAtFullOpacity()
    }

    func showRecording(
        cleanerName: String,
        mode: ProcessingMode = .clean,
        speechLabel: String = "WHISPER",
        runsModel: Bool = true,
        context: AppContext? = nil,
        levelProvider: @escaping () -> Float
    ) {
        animationGeneration += 1
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        processingTimer?.invalidate()
        processingTimer = nil

        viewModel.mode = .recording
        viewModel.voiceHeard = false
        hostingView?.isDuckVisible = isCompanionEnabled
        hostingView?.isBubbleVisible = true
        announceState()
        viewModel.cleanerName = cleanerName
        viewModel.speechLabel = speechLabel
        viewModel.runsModel = runsModel
        viewModel.processingMode = mode
        viewModel.targetContext = context
        viewModel.audioLevel = 0.0

        if !panel.isVisible { positionPanel() }
        showAtFullOpacity()

        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let level = levelProvider()
            self.viewModel.audioLevel = level
        }
    }

    func showProcessing() {
        animationGeneration += 1
        meterTimer?.invalidate()
        meterTimer = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        viewModel.mode = .processing
        hostingView?.isDuckVisible = isCompanionEnabled
        hostingView?.isBubbleVisible = true
        announceState()
        if !panel.isVisible { positionPanel(); showAtFullOpacity() }
        viewModel.processingStep = 0

        processingTimer?.invalidate()
        processingTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.viewModel.processingStep += 1
        }
    }

    func showCompleted(
        didAutoPaste: Bool,
        usedFallback: Bool,
        model: String? = nil,
        latencySeconds: Double? = nil,
        wpm: Int? = nil,
        targetContext: AppContext? = nil,
        unrecognizedCommand: Bool = false
    ) {
        animationGeneration += 1
        meterTimer?.invalidate()
        meterTimer = nil
        processingTimer?.invalidate()
        processingTimer = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        viewModel.answeredModel = model
        viewModel.measuredWPM = wpm
        viewModel.latencySeconds = latencySeconds
        if let targetContext {
            viewModel.targetContext = targetContext
        }
        viewModel.mode = .completed(
            didAutoPaste: didAutoPaste,
            usedFallback: usedFallback,
            unrecognizedCommand: unrecognizedCommand
        )
        hostingView?.isDuckVisible = isCompanionEnabled
        hostingView?.isBubbleVisible = true
        announceState()
        if !panel.isVisible { positionPanel(); showAtFullOpacity() }

        let telemetryHold: Double = (wpm != nil || latencySeconds != nil) ? 1.25 : 0.6
        let noticeHold: Double = unrecognizedCommand ? 1.4 : 0.0
        let holdDuration = max(telemetryHold, noticeHold)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isCompanionEnabled {
                self.showIdle()
            } else {
                self.fadeOut()
            }
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + holdDuration,
            execute: work
        )
    }

    func showActionExecuted(description: String) {
        animationGeneration += 1
        meterTimer?.invalidate()
        meterTimer = nil
        processingTimer?.invalidate()
        processingTimer = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        viewModel.mode = .actionExecuted(description: description)
        hostingView?.isDuckVisible = isCompanionEnabled
        hostingView?.isBubbleVisible = true
        announceState()
        if !panel.isVisible { positionPanel(); showAtFullOpacity() }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isCompanionEnabled {
                self.showIdle()
            } else {
                self.fadeOut()
            }
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func showModeChanged(_ mode: ProcessingMode) {
        animationGeneration += 1
        meterTimer?.invalidate()
        meterTimer = nil
        processingTimer?.invalidate()
        processingTimer = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        viewModel.processingMode = mode
        viewModel.mode = .modeChanged(mode)
        hostingView?.isDuckVisible = false
        hostingView?.isBubbleVisible = true
        announceState()

        if !panel.isVisible { positionPanel() }
        showAtFullOpacity()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isCompanionEnabled {
                self.showIdle()
            } else {
                self.fadeOut()
            }
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }

    func showCancelled() {
        animationGeneration += 1
        meterTimer?.invalidate()
        meterTimer = nil
        processingTimer?.invalidate()
        processingTimer = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        viewModel.mode = .cancelled
        hostingView?.isDuckVisible = isCompanionEnabled
        hostingView?.isBubbleVisible = true
        announceState()
        if !panel.isVisible { positionPanel() }
        showAtFullOpacity()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isCompanionEnabled {
                self.showIdle()
            } else {
                self.fadeOut()
            }
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    func showFailed(message: String) {
        animationGeneration += 1
        meterTimer?.invalidate()
        meterTimer = nil
        processingTimer?.invalidate()
        processingTimer = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        viewModel.mode = .failed(message)
        hostingView?.isDuckVisible = isCompanionEnabled
        hostingView?.isBubbleVisible = true
        announceState()
        if !panel.isVisible { positionPanel() }
        showAtFullOpacity()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isCompanionEnabled {
                self.showIdle()
            } else {
                self.fadeOut()
            }
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    func hideImmediately() {
        animationGeneration += 1
        meterTimer?.invalidate()
        meterTimer = nil
        processingTimer?.invalidate()
        processingTimer = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        if isCompanionEnabled {
            showIdle()
        } else {
            panel.orderOut(nil)
            viewModel.isVisible = false
        }
    }

    private func announceState() {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: viewModel.mode.accessibilityStatus,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    private func showAtFullOpacity() {
        viewModel.isVisible = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1.0
        }
        panel.alphaValue = 1.0
        panel.orderFrontRegardless()
    }

    private func fadeOut() {
        let currentGen = animationGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard let self, self.animationGeneration == currentGen else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1.0
            self.viewModel.isVisible = false
        })
    }

    private func savePosition() {
        let origin = panel.frame.origin
        UserDefaults.standard.set(Double(origin.x), forKey: "microduck.screenPosition.x")
        UserDefaults.standard.set(Double(origin.y), forKey: "microduck.screenPosition.y")
    }

    private func positionPanel() {
        let panelWidth = HUDLayout.panelWidth
        let panelHeight = HUDLayout.panelHeight

        if let savedX = UserDefaults.standard.object(forKey: "microduck.screenPosition.x") as? Double,
           let savedY = UserDefaults.standard.object(forKey: "microduck.screenPosition.y") as? Double {
            let savedPoint = NSPoint(x: savedX, y: savedY)
            let panelRect = NSRect(origin: savedPoint, size: NSSize(width: panelWidth, height: panelHeight))
            let isVisibleOnAnyScreen = NSScreen.screens.contains { screen in
                screen.visibleFrame.intersects(panelRect)
            }
            if isVisibleOnAnyScreen {
                panel.setFrame(panelRect, display: true)
                viewModel.panelOrigin = panel.frame.origin
                return
            }
        }

        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
        guard let screen = targetScreen else { return }
        let screenRect = screen.visibleFrame
        let x = screenRect.minX + 24.0
        let y = screenRect.minY + 24.0

        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        viewModel.panelOrigin = panel.frame.origin
    }
}
