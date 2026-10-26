import SwiftUI
import VoiceFlowMacCore

public enum HUDMode: Equatable {
    case recording
    case processing
    case completed(didAutoPaste: Bool, usedFallback: Bool, unrecognizedCommand: Bool = false)
    case actionExecuted(description: String)
    case failed(String)
    case modeChanged(ProcessingMode)
    case cancelled

    public var stateKey: String {
        switch self {
        case .recording: return "recording"
        case .processing: return "processing"
        case .completed: return "completed"
        case .actionExecuted: return "actionExecuted"
        case .failed: return "failed"
        case .modeChanged(let mode): return "modeChanged.\(mode.rawValue)"
        case .cancelled: return "cancelled"
        }
    }

    public var accessibilityStatus: String {
        switch self {
        case .recording: return "VoiceFlow recording"
        case .processing: return "VoiceFlow processing"
        case .completed(let didAutoPaste, let usedFallback, _):
            let delivered = didAutoPaste ? "pasted" : "copied"
            return usedFallback ? "VoiceFlow \(delivered) the plain transcript" : "VoiceFlow \(delivered)"
        case .actionExecuted(let description): return "VoiceFlow ran \(description)"
        case .failed(let message): return "VoiceFlow failed: \(message)"
        case .modeChanged(let mode): return "VoiceFlow mode \(mode.rawValue)"
        case .cancelled: return "VoiceFlow recording cancelled"
        }
    }
}

public final class HUDViewModel: ObservableObject {
    @Published public var mode: HUDMode = .recording
    @Published public var audioLevel: Float = 0.0
    @Published public var cleanerName: String = "gemini"
    @Published public var speechLabel: String = "WHISPER"
    @Published public var runsModel: Bool = true
    @Published public var processingMode: ProcessingMode = .clean
    @Published public var processingStep: Int = 0
    @Published public var answeredModel: String? = nil
    @Published public var targetContext: AppContext? = nil
    @Published public var measuredWPM: Int? = nil
    @Published public var latencySeconds: Double? = nil

    /// Whether voice speech has been detected since key down (level > 0.2).
    /// If false during recording, only the minimal capsule shows.
    @Published public var voiceHeard: Bool = false

    public init() {}
}

// MARK: - Microduck HUD View (I-82)
/// Articulated mascot and thought bubble capsule beside the duck.
public struct RetroMicHUDView: View {
    @ObservedObject public var viewModel: HUDViewModel
    @State private var modeChangeTime: TimeInterval = ProcessInfo.processInfo.systemUptime

    public init(viewModel: HUDViewModel) {
        self.viewModel = viewModel
    }

    private var isRecording: Bool { viewModel.mode == .recording }
    private var isProcessing: Bool { viewModel.mode == .processing }

    private var shouldShowDuck: Bool {
        switch viewModel.mode {
        case .recording, .processing, .completed, .actionExecuted, .failed, .cancelled:
            return true
        case .modeChanged:
            return false
        }
    }

    private var bubbleSize: (width: CGFloat, height: CGFloat) {
        switch viewModel.mode {
        case .recording, .processing, .completed, .actionExecuted:
            return (HUDLayout.capsuleFullSize.width, HUDLayout.capsuleFullSize.height)
        case .failed, .cancelled, .modeChanged:
            return (HUDLayout.capsuleShortSize.width, HUDLayout.capsuleShortSize.height)
        }
    }

    private func currentPose(time: TimeInterval, uptime: TimeInterval) -> DuckPose {
        let breathingPhase = time * 2.8
        let wigglePhase = time * 3.8

        switch viewModel.mode {
        case .recording:
            // Sits down when recording (knees folded in front, settling in to listen)
            var base: DuckPose = .recordingSitting
            let lvl = viewModel.audioLevel
            if lvl > 0.65 {
                base = .stretchSitting
                base.jaw = Double(min(1.0, lvl * 1.35))
            } else if lvl < 0.12 {
                base = .recordingSitting
                base.jaw = 0.0
            } else {
                base = .recordingSitting
                base.jaw = Double(min(1.0, lvl * 1.25))
            }
            // Gentle breathing keeping head high & playful kid-like foot swinging
            let breath = sin(breathingPhase)
            base.body += breath * 0.6
            base.n = base.n.map { $0 + breath * 1.0 }
            base.footWiggle = wigglePhase
            return base

        case .processing:
            // Thoughtful listening posture, sitting with feet still swaying
            var base: DuckPose = .recordingSitting
            base.head = -8.0 + sin(breathingPhase * 0.8) * 5.0
            base.footWiggle = wigglePhase * 0.8
            return base

        case .completed, .actionExecuted:
            // Stands upright, nodding head happily with joy!
            var base: DuckPose = .standFront
            let elapsed = uptime - modeChangeTime
            if elapsed < 1.4 {
                let decay = max(0.0, 1.0 - elapsed / 1.4)
                base.head = -4.0 + sin(elapsed * .pi * 4.5) * 12.0 * decay
            }
            return base

        case .failed, .cancelled:
            // Stands upright, shaking head in error / cancellation!
            var base: DuckPose = .standFront
            let elapsed = uptime - modeChangeTime
            if elapsed < 1.2 {
                let decay = max(0.0, 1.0 - elapsed / 1.2)
                base.head = -4.0 + sin(elapsed * .pi * 6.0) * 14.0 * decay
            }
            return base

        case .modeChanged:
            // Stands upright when ready / mode changed
            return .standFront
        }
    }

    private var ledColor: Color {
        switch viewModel.mode {
        case .recording:
            return VoiceStationTokens.rec
        case .processing:
            return VoiceStationTokens.dotBlue
        case .completed, .actionExecuted:
            return VoiceStationTokens.okOnDark
        case .failed, .cancelled:
            return VoiceStationTokens.onAir
        case .modeChanged:
            return VoiceStationTokens.gold
        }
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let uptime = ProcessInfo.processInfo.systemUptime
            let pose = currentPose(time: time, uptime: uptime)
            let isSitting = pose.isSitting

            ZStack(alignment: .bottomLeading) {
                // 1. Duck Articulated Mascot (at bottom left, facing front)
                if shouldShowDuck {
                    MicroduckView(pose: pose, audioLevel: viewModel.audioLevel, ledColor: ledColor)
                        .frame(width: HUDLayout.duckWidth, height: HUDLayout.duckHeight)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.5, anchor: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .id("microduck-actor")

                    // 2. Thought Trail Dots connecting duck's head to the bubble
                    Circle()
                        .fill(Color.black.opacity(0.85))
                        .overlay(Circle().stroke(VoiceStationTokens.dotBlue.opacity(0.45), lineWidth: 0.8))
                        .frame(width: 3.5, height: 3.5)
                        .offset(x: isSitting ? 46 : 48, y: isSitting ? -39 : -48)
                        .animation(.spring(response: 0.36, dampingFraction: 0.75), value: isSitting)

                    Circle()
                        .fill(Color.black.opacity(0.85))
                        .overlay(Circle().stroke(VoiceStationTokens.dotBlue.opacity(0.45), lineWidth: 0.8))
                        .frame(width: 5.5, height: 5.5)
                        .offset(x: isSitting ? 53 : 55, y: isSitting ? -37 : -44)
                        .animation(.spring(response: 0.36, dampingFraction: 0.75), value: isSitting)
                }

                // 3. Bubble Capsule (beside duck's head)
                capsuleBubble
                    .offset(
                        x: shouldShowDuck ? HUDLayout.duckToBubble : 0,
                        y: shouldShowDuck ? (isSitting ? -36 : -44) : -10
                    )
                    .animation(.spring(response: 0.36, dampingFraction: 0.75), value: shouldShowDuck)
                    .animation(.spring(response: 0.36, dampingFraction: 0.75), value: isSitting)
                    .animation(.spring(response: 0.36, dampingFraction: 0.75), value: bubbleSize.width)
            }
            .frame(width: HUDLayout.panelWidth, height: HUDLayout.panelHeight, alignment: .bottomLeading)
        }
        .onChange(of: viewModel.mode) { _, _ in
            modeChangeTime = ProcessInfo.processInfo.systemUptime
        }
        .onChange(of: viewModel.audioLevel) { _, lvl in
            if lvl > 0.20 && !viewModel.voiceHeard {
                viewModel.voiceHeard = true
            }
        }
    }

    // MARK: - Capsule Bubble Component
    private var capsuleBubble: some View {
        let size = bubbleSize
        return ZStack {
            Capsule()
                .fill(Color.black.opacity(0.85))
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.28),
                                    VoiceStationTokens.dotBlue.opacity(0.40),
                                    Color.white.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.55), radius: 6, x: 0, y: 3)

            // Content inside the capsule
            Group {
                if size.height <= 18 {
                    minimalBubbleContent
                } else if size.height <= 24 {
                    shortBubbleContent
                } else {
                    fullBubbleContent
                }
            }
            .padding(.horizontal, HUDLayout.horizontalPadding)
            .padding(.vertical, HUDLayout.verticalPadding)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Minimal Capsule (Key down by accident, no voice yet)
    private var minimalBubbleContent: some View {
        HStack(spacing: 4.5) {
            Circle()
                .fill(VoiceStationTokens.onAir)
                .frame(width: 5.0, height: 5.0)
                .shadow(color: VoiceStationTokens.onAir, radius: 2.5)

            HStack(spacing: 2.2) {
                ForEach(0..<3) { _ in
                    Circle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 2.5, height: 2.5)
                }
            }
        }
    }

    // MARK: - Short Capsule (Mode change, error, cancelled)
    private var shortBubbleContent: some View {
        HStack(alignment: .center, spacing: 5) {
            switch viewModel.mode {
            case .modeChanged(let mode):
                Text("MODE")
                    .font(VoiceStationTokens.mono(size: 5.4, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.55))
                Text(mode.shortTitle)
                    .font(VoiceStationTokens.mono(size: 5.4, weight: .heavy))
                    .foregroundColor(VoiceStationTokens.gold)
                Spacer(minLength: 0)
                HStack(spacing: 2.0) {
                    ForEach(ProcessingMode.allCases, id: \.self) { m in
                        RoundedRectangle(cornerRadius: 1.0)
                            .fill(m == mode ? VoiceStationTokens.gold : Color.white.opacity(0.18))
                            .frame(width: 10, height: 3.5)
                    }
                }
            case .failed(let msg):
                Circle()
                    .fill(VoiceStationTokens.onAir)
                    .frame(width: 5.0, height: 5.0)
                Text("ERROR")
                    .font(VoiceStationTokens.mono(size: 5.0, weight: .heavy))
                    .foregroundColor(VoiceStationTokens.onAir)
                Spacer(minLength: 0)
                Text(msg.isEmpty ? "NOTHING PASTED" : msg)
                    .font(VoiceStationTokens.mono(size: 4.0, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.65))
                    .lineLimit(1)
            case .cancelled:
                Circle()
                    .fill(VoiceStationTokens.rec)
                    .frame(width: 5.0, height: 5.0)
                Text("CANCELLED")
                    .font(VoiceStationTokens.mono(size: 5.0, weight: .heavy))
                    .foregroundColor(VoiceStationTokens.rec)
                Spacer(minLength: 0)
                Text("ESC")
                    .font(VoiceStationTokens.mono(size: 4.0, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.65))
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Full 3-Row Capsule (Recording, Processing, Pasted, Action)
    private var fullBubbleContent: some View {
        VStack(alignment: .leading, spacing: 2.0) {
            // Row 1: Status lamp + status title + target app chip + ESC
            HStack(alignment: .center, spacing: 3.5) {
                statusLampView

                Text(statusTitleText)
                    .font(VoiceStationTokens.mono(size: 5.2, weight: .heavy))
                    .foregroundColor(statusTitleColor)

                if let ctx = viewModel.targetContext {
                    Text(ctx.shortName.uppercased())
                        .font(VoiceStationTokens.mono(size: 3.8, weight: .heavy))
                        .padding(.horizontal, 3.5)
                        .padding(.vertical, 1.0)
                        .background(VoiceStationTokens.dotBlue.opacity(0.12))
                        .foregroundColor(VoiceStationTokens.accentHover)
                        .clipShape(RoundedRectangle(cornerRadius: 2.0))
                        .overlay(RoundedRectangle(cornerRadius: 2.0).stroke(VoiceStationTokens.dotBlue.opacity(0.55), lineWidth: 0.7))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isRecording {
                    Text("ESC ✕")
                        .font(VoiceStationTokens.mono(size: 3.8, weight: .heavy))
                        .foregroundColor(Color.white.opacity(0.6))
                }
            }

            // Row 2: 12-bar equalizer / processing wave (fills width evenly)
            HStack(spacing: 2.0) {
                ForEach(0..<12) { i in
                    RoundedRectangle(cornerRadius: 1.0)
                        .fill(barColor(for: i))
                        .frame(width: 6.0, height: 3.6)
                }
            }

            // Row 3: Telemetry details
            HStack(alignment: .center, spacing: 3.0) {
                telemetryLeftView
                Spacer(minLength: 0)
                telemetryRightView
            }
        }
    }

    private var statusLampView: some View {
        Circle()
            .fill(ledColor)
            .frame(width: 5.0, height: 5.0)
            .shadow(color: ledColor, radius: 2.5)
    }

    private var statusTitleText: String {
        switch viewModel.mode {
        case .recording:
            return "ON AIR"
        case .processing:
            return "PROCESSING"
        case .completed(let didAutoPaste, _, _):
            return didAutoPaste ? "PASTED" : "COPIED"
        case .actionExecuted:
            return "ACTION"
        case .failed:
            return "ERROR"
        case .cancelled:
            return "CANCELLED"
        case .modeChanged:
            return "MODE"
        }
    }

    private var statusTitleColor: Color {
        switch viewModel.mode {
        case .recording:
            return VoiceStationTokens.onAir
        case .processing:
            return VoiceStationTokens.inputCream
        case .completed:
            return VoiceStationTokens.okOnDark
        case .actionExecuted:
            return VoiceStationTokens.gold
        case .failed:
            return VoiceStationTokens.onAir
        case .cancelled:
            return VoiceStationTokens.rec
        case .modeChanged:
            return VoiceStationTokens.gold
        }
    }

    private func barColor(for index: Int) -> Color {
        let defaultColor: Color
        if index < 7 {
            defaultColor = VoiceStationTokens.dotBlue
        } else if index < 10 {
            defaultColor = VoiceStationTokens.gold
        } else {
            defaultColor = VoiceStationTokens.onAir
        }

        switch viewModel.mode {
        case .recording:
            let litCount = max(1, Int(viewModel.audioLevel * 12.0))
            return index < litCount ? defaultColor : Color.white.opacity(0.12)
        case .processing:
            let waveCenter = (viewModel.processingStep % 16) - 2
            let dist = abs(index - waveCenter)
            return dist <= 2 ? VoiceStationTokens.dotBlue : Color.white.opacity(0.12)
        case .completed, .actionExecuted:
            return defaultColor
        case .failed, .cancelled, .modeChanged:
            return Color.white.opacity(0.12)
        }
    }

    @ViewBuilder
    private var telemetryLeftView: some View {
        switch viewModel.mode {
        case .recording:
            Text("⚡ LIVE")
                .font(VoiceStationTokens.mono(size: 3.8, weight: .heavy))
                .foregroundColor(VoiceStationTokens.gold)
        case .processing:
            let stage: String = {
                switch viewModel.processingMode {
                case .clean: return "CLEANING"
                case .translate: return "TRANSLATING"
                case .meeting: return "STRUCTURING"
                case .actions: return "PARSING ACTION"
                }
            }()
            Text(stage)
                .font(VoiceStationTokens.mono(size: 3.8, weight: .heavy))
                .foregroundColor(VoiceStationTokens.dotBlue)
        case .completed:
            HStack(spacing: 2) {
                if let wpm = viewModel.measuredWPM {
                    Text("⚡ \(wpm) WPM")
                        .font(VoiceStationTokens.mono(size: 3.8, weight: .heavy))
                        .foregroundColor(VoiceStationTokens.gold)
                }
                if let lat = viewModel.latencySeconds {
                    Text("· \(String(format: "%.1fs", lat))")
                        .font(VoiceStationTokens.mono(size: 3.8, weight: .heavy))
                        .foregroundColor(VoiceStationTokens.dotBlue)
                }
            }
        case .actionExecuted:
            Text("⚡ DONE")
                .font(VoiceStationTokens.mono(size: 3.8, weight: .heavy))
                .foregroundColor(VoiceStationTokens.gold)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var telemetryRightView: some View {
        switch viewModel.mode {
        case .recording:
            Text("• \(viewModel.speechLabel) · LOCAL")
                .font(VoiceStationTokens.mono(size: 3.8, weight: .bold))
                .foregroundColor(Color.white.opacity(0.6))
        case .processing:
            let privacy = viewModel.runsModel ? "CLOUD" : "LOCAL"
            Text("• \(viewModel.cleanerName.uppercased()) · \(privacy)")
                .font(VoiceStationTokens.mono(size: 3.8, weight: .bold))
                .foregroundColor(Color.white.opacity(0.6))
        case .completed:
            let model = viewModel.answeredModel ?? viewModel.cleanerName.uppercased()
            let privacy = viewModel.runsModel ? "CLOUD" : "LOCAL"
            Text("• \(model) · \(privacy)")
                .font(VoiceStationTokens.mono(size: 3.8, weight: .bold))
                .foregroundColor(Color.white.opacity(0.6))
        case .actionExecuted(let desc):
            Text(desc)
                .font(VoiceStationTokens.mono(size: 3.6, weight: .heavy))
                .foregroundColor(Color.white.opacity(0.7))
                .lineLimit(1)
        default:
            EmptyView()
        }
    }
}
