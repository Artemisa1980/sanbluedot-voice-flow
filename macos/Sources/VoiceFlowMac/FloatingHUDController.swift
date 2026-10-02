import AppKit
import SwiftUI
import VoiceFlowMacCore

final class FloatingHUDPanel: NSPanel {
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
        // The panel asks for transparency; the view that fills it has to agree. Its layer
        // takes a background from the effective appearance otherwise, and that background
        // is the whole window rectangle — square corners around a rounded capsule.
        //
        // This was invisible until the window was corrected to `330 × 88`: while it was
        // being resized to `295 × 74`, the capsule was wider than the window it sat in and
        // covered every pixel of it. Fixing the clipping is what exposed the ground behind.
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
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
        context: AppContext? = nil,
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
        viewModel.targetContext = context
        viewModel.audioLevel = 0.0

        positionPanel()
        showAtFullOpacity()

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

    func showCompleted(
        didAutoPaste: Bool,
        usedFallback: Bool,
        model: String? = nil,
        latencySeconds: Double? = nil,
        wpm: Int? = nil,
        targetContext: AppContext? = nil,
        unrecognizedCommand: Bool = false
    ) {
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

        // Two reasons to hold the capsule, and the longer one wins. Telemetry needs time
        // to be read; a notice needs longer than a confirmation the speaker already
        // expects. Written as a single ternary chain, the telemetry branch matched first
        // and always — `latencySeconds` is passed on every completion — so the notice
        // silently lost the extra time that was given to it on purpose.
        let telemetryHold: Double = (wpm != nil || latencySeconds != nil) ? 1.25 : 0.6
        let noticeHold: Double = unrecognizedCommand ? 1.4 : 0.0
        let holdDuration = max(telemetryHold, noticeHold)
        let work = DispatchWorkItem { [weak self] in
            self?.fadeOut()
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + holdDuration,
            execute: work
        )
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

    /// Confirm a mode change while nothing is being dictated.
    ///
    /// The capsule is summoned by the switch itself, so it raises the generation and
    /// resets the alpha: without that, a fade already running from the last dictation
    /// would carry on and order the panel out a moment after it appeared.
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

        positionPanel()
        showAtFullOpacity()

        let work = DispatchWorkItem { [weak self] in
            self?.fadeOut()
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }

    /// Say the recording was taken back, briefly. Silence here would read the same as a
    /// trigger that failed.
    func showCancelled() {
        animationGeneration += 1
        meterTimer?.invalidate()
        meterTimer = nil
        processingTimer?.invalidate()
        processingTimer = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        viewModel.mode = .cancelled
        positionPanel()
        showAtFullOpacity()

        let work = DispatchWorkItem { [weak self] in
            self?.fadeOut()
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    /// Say a run failed or was refused. Like a mode change, the capsule may be summoned
    /// with nothing on screen — the microphone refusing to start, a refused pairing — so
    /// it raises the generation, positions the panel and shows it (D-04).
    func showFailed(message: String) {
        animationGeneration += 1
        meterTimer?.invalidate()
        meterTimer = nil
        processingTimer?.invalidate()
        processingTimer = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        viewModel.mode = .failed(message)
        positionPanel()
        showAtFullOpacity()

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

    /// Bring the panel back to full opacity, cancelling a fade that is still running.
    ///
    /// Setting `alphaValue` directly does not stop an animation already interpolating
    /// toward zero, so a mode switch pressed during the last fade kept dimming for a
    /// moment before snapping back. A zero-duration group through the same animator
    /// replaces that animation instead of racing it.
    private func showAtFullOpacity() {
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
        })
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        // From `HUDLayout`, the same values the panel is created with. Written out here
        // as literals, this method quietly resized the capsule back to the previous
        // design on every show and clipped the new one.
        let panelWidth = HUDLayout.panelWidth
        let panelHeight = HUDLayout.panelHeight

        // Position at bottom center of the screen, floating nicely above the dock
        let x = screenRect.midX - (panelWidth / 2.0)
        let y = screenRect.minY + 60.0
        
        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }
}
