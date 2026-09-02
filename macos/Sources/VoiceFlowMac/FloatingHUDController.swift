import AppKit
import SwiftUI
import VoiceFlowMacCore

final class FloatingHUDPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 74),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}

final class FloatingHUDController {
    private let panel = FloatingHUDPanel()
    private let viewModel = HUDViewModel()
    private var meterTimer: Timer?
    private var processingTimer: Timer?
    private var dismissWorkItem: DispatchWorkItem?
    private var animationGeneration: Int = 0

    init() {
        let hostingView = NSHostingView(rootView: RetroMicHUDView(viewModel: viewModel))
        hostingView.frame = panel.contentRect(forFrameRect: panel.frame)
        panel.contentView = hostingView
    }

    deinit {
        meterTimer?.invalidate()
        processingTimer?.invalidate()
        dismissWorkItem?.cancel()
    }

    func showRecording(
        cleanerName: String,
        mode: ProcessingMode = .clean,
        levelProvider: @escaping () -> Float
    ) {
        animationGeneration += 1
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        processingTimer?.invalidate()
        processingTimer = nil

        viewModel.mode = .recording
        viewModel.cleanerName = cleanerName
        viewModel.processingMode = mode
        viewModel.audioLevel = 0.0

        positionPanel()
        panel.alphaValue = 1.0
        panel.orderFrontRegardless()

        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let level = levelProvider()
            self.viewModel.audioLevel = level
        }
    }

    func showProcessing() {
        meterTimer?.invalidate()
        meterTimer = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        viewModel.mode = .processing
        viewModel.processingStep = 0

        processingTimer?.invalidate()
        processingTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.viewModel.processingStep += 1
        }
    }

    func showCompleted(didAutoPaste: Bool, usedFallback: Bool, model: String? = nil) {
        meterTimer?.invalidate()
        meterTimer = nil
        processingTimer?.invalidate()
        processingTimer = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        viewModel.answeredModel = model
        viewModel.mode = .completed(didAutoPaste: didAutoPaste, usedFallback: usedFallback)

        // Schedule auto-dismiss with smooth fade
        let work = DispatchWorkItem { [weak self] in
            self?.fadeOut()
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func showActionExecuted(description: String) {
        meterTimer?.invalidate()
        meterTimer = nil
        processingTimer?.invalidate()
        processingTimer = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        viewModel.mode = .actionExecuted(description: description)

        let work = DispatchWorkItem { [weak self] in
            self?.fadeOut()
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func showFailed(message: String) {
        meterTimer?.invalidate()
        meterTimer = nil
        processingTimer?.invalidate()
        processingTimer = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        viewModel.mode = .failed(message)

        let work = DispatchWorkItem { [weak self] in
            self?.fadeOut()
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
        panel.orderOut(nil)
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
        })
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let panelWidth: CGFloat = 295
        let panelHeight: CGFloat = 74
        
        // Position at bottom center of the screen, floating nicely above the dock
        let x = screenRect.midX - (panelWidth / 2.0)
        let y = screenRect.minY + 60.0
        
        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }
}
