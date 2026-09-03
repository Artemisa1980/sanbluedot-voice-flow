import SwiftUI
import VoiceFlowMacCore

enum HUDMode {
    case recording
    case processing
    case completed(didAutoPaste: Bool, usedFallback: Bool, unrecognizedCommand: Bool = false)
    case actionExecuted(description: String)
    case failed(String)
    /// The mode switch was used while nothing was being dictated. The capsule appears
    /// on its own to confirm the new mode, then leaves.
    case modeChanged(ProcessingMode)
    /// The speaker took the recording back with Escape. Nothing was pasted or kept.
    case cancelled

    /// A stable name for the current state, used as the animation value so the capsule
    /// morphs between states instead of cutting.
    var stateKey: String {
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

    var showsTelemetry: Bool {
        switch self {
        case .recording, .processing, .completed, .actionExecuted:
            return true
        case .failed, .modeChanged, .cancelled:
            return false
        }
    }
}

final class HUDViewModel: ObservableObject {
    @Published var mode: HUDMode = .recording
    @Published var audioLevel: Float = 0.0
    @Published var cleanerName: String = "gemini"
    @Published var processingMode: ProcessingMode = .clean
    @Published var processingStep: Int = 0
    /// The cloud model that answered, shown on completion so a capacity fallback to a
    /// different model is visible rather than silent.
    @Published var answeredModel: String? = nil
    /// The target application context detected when recording began.
    @Published var targetContext: AppContext? = nil
    /// Measured speaking rate in words per minute.
    @Published var measuredWPM: Int? = nil
    /// Total turnaround latency in seconds.
    @Published var latencySeconds: Double? = nil
    /// Characters captured from the screen for a transform run, `nil` when none.
    @Published var selectionCharacters: Int? = nil
}

struct RetroMicHUDView: View {
    @ObservedObject var viewModel: HUDViewModel
    
    // sanblue brand colors
    private let skyBlue = VoiceStationTokens.dotBlue
    private let retroNavy = VoiceStationTokens.navy
    // The brand gold, from the token rather than repeated as a literal. The values
    // matched, which is exactly why a copy is dangerous: the day the token moves, this
    // one stays behind and nothing fails.
    private let vintageGold = VoiceStationTokens.gold
    // The same #FF453B the station's meter uses, from the one token. It was written
    // here as 1.0/0.27/0.23 and there as hex — two spellings of one colour, which is
    // how a palette drifts without anything failing.
    private let onAirRed = VoiceStationTokens.onAir

    var body: some View {
        HStack(spacing: HUDLayout.discToColumn) {
            // Vintage Microphone Graphic
            ZStack {
                Circle()
                    .fill(retroNavy.opacity(0.85))
                    .frame(width: HUDLayout.micDisc, height: HUDLayout.micDisc)
                    .overlay(
                        Circle()
                            .stroke(LinearGradient(
                                colors: [.white.opacity(0.4), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ), lineWidth: 1.5)
                    )
                
                if glyphName == "mic.fill" {
                    VintageMicIcon(color: iconColor)
                        .transition(.scale.combined(with: .opacity))
                        .id("vintage-mic")
                } else {
                    Image(systemName: glyphName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(iconColor)
                        .transition(.scale.combined(with: .opacity))
                        .id(glyphName)
                }
            }
            .shadow(color: iconGlowColor, radius: 8)

            VStack(alignment: .leading, spacing: HUDLayout.rowSpacing) {
                // Row 1: Status header (Left) + sanbluedot (Right)
                HStack(alignment: .center, spacing: 6) {
                    statusBadge
                        .id("status-\(viewModel.mode.stateKey)")
                    
                    Spacer(minLength: 4)
                    
                    // sanblueᵈᵒᵗ Wordmark: gold word, dot-blue elevated superscript
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("sanblue")
                            .font(VoiceStationTokens.mono(size: 10, weight: .bold))
                            .foregroundColor(vintageGold)

                        Text("dot")
                            .font(VoiceStationTokens.mono(size: 7, weight: .heavy))
                            .foregroundColor(skyBlue)
                            .baselineOffset(5)
                    }
                    .fixedSize()
                    .lineLimit(1)
                }
                
                // Row 2: LED VU-Meter equalizer, processing wave, or mode switcher
                if case .modeChanged(let mode) = viewModel.mode {
                    modeStripView(active: mode)
                        .id("mode-\(mode.rawValue)")
                } else {
                    vuMeterView
                        .id("meter-\(viewModel.mode.stateKey)")
                }

                // Row 3: Live Telemetry Speed Pill (Sandy's unified choice)
                if viewModel.mode.showsTelemetry {
                    telemetryStripView
                        .id("telemetry-\(viewModel.mode.stateKey)")
                }
            }
            .frame(width: HUDLayout.contentColumn)
        }
        .padding(.horizontal, HUDLayout.horizontalPadding)
        .padding(.vertical, HUDLayout.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(retroNavy.opacity(0.4))
                        .blur(radius: 20)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.25),
                                    skyBlue.opacity(0.35),
                                    .white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.6), radius: 16, x: 0, y: 8)
        .animation(
            .spring(response: 0.30, dampingFraction: 0.82),
            value: viewModel.mode.stateKey
        )
    }

    /// The mode's own accent. One rule, so the strip cannot drift into a palette of its
    /// own: every mode lights the brand gold, except the one that can act on the
    /// machine, which lights the approved coral the station already uses for live state.
    static func accent(for mode: ProcessingMode) -> Color {
        switch mode {
        case .clean, .translate, .meeting:
            return VoiceStationTokens.gold
        case .actions:
            return VoiceStationTokens.rec
        case .transform:
            return VoiceStationTokens.dotBlue
        }
    }

    /// One glyph per mode, so the confirmation reads before the word does.
    static func glyph(for mode: ProcessingMode) -> String {
        switch mode {
        case .clean: return "sparkles"
        case .translate: return "character.bubble.fill"
        case .meeting: return "list.bullet.rectangle.fill"
        case .actions: return "bolt.fill"
        case .transform: return "wand.and.stars"
        }
    }

    private var isRecording: Bool {
        if case .recording = viewModel.mode { return true }
        return false
    }

    private var glyphName: String {
        if case .modeChanged(let mode) = viewModel.mode {
            return Self.glyph(for: mode)
        }
        if case .cancelled = viewModel.mode {
            return "mic.slash.fill"
        }
        return "mic.fill"
    }

    private var iconColor: Color {
        switch viewModel.mode {
        case .recording:
            return .white
        case .processing:
            return skyBlue
        case .completed:
            return VoiceStationTokens.ok
        case .actionExecuted:
            return vintageGold
        case .failed:
            return onAirRed
        case .modeChanged(let mode):
            return Self.accent(for: mode)
        case .cancelled:
            return VoiceStationTokens.rec
        }
    }

    private var iconGlowColor: Color {
        switch viewModel.mode {
        case .recording:
            return onAirRed.opacity(0.6)
        case .processing:
            return skyBlue.opacity(0.6)
        case .completed:
            return VoiceStationTokens.ok.opacity(0.6)
        case .actionExecuted:
            return vintageGold.opacity(0.8)
        case .failed:
            return onAirRed.opacity(0.8)
        case .modeChanged(let mode):
            return Self.accent(for: mode).opacity(0.7)
        case .cancelled:
            return VoiceStationTokens.rec.opacity(0.6)
        }
    }

    // The text itself lives in `HUDBadge`, in the core module, so a check can read what
    // the speaker reads. This view only places it.
    private var recordingBadgeText: String {
        HUDBadge.recording(mode: viewModel.processingMode, context: viewModel.targetContext)
    }

    private var processingBadgeText: String {
        HUDBadge.processing(mode: viewModel.processingMode, cleanerName: viewModel.cleanerName)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch viewModel.mode {
        case .recording:
            HStack(spacing: 5) {
                Circle()
                    .fill(onAirRed)
                    .frame(width: 7, height: 7)
                    .shadow(color: onAirRed, radius: 4)
                Text(recordingBadgeText)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(onAirRed)
                    .fixedSize()
            }
        case .processing:
            HStack(spacing: 5) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
                Text(processingBadgeText)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(skyBlue)
            }
        case .actionExecuted(let desc):
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                    .foregroundColor(vintageGold)
                Text("ACTION")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(vintageGold)
                Text(desc)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }
        case .completed(let didAutoPaste, _, let unrecognizedCommand):
            HStack(spacing: 5) {
                Image(systemName: didAutoPaste ? "checkmark.circle.fill" : "doc.on.clipboard.fill")
                    .font(.system(size: 10))
                    .foregroundColor(VoiceStationTokens.ok)
                if let target = viewModel.targetContext, target.category != .general {
                    Text(didAutoPaste ? "PASTED ➔ \(target.shortName)" : "COPIED")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(VoiceStationTokens.ok)
                } else {
                    Text(didAutoPaste ? "PASTED" : "COPIED")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(VoiceStationTokens.ok)
                }
                if unrecognizedCommand {
                    Text("NO CMD")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundColor(VoiceStationTokens.rec)
                }
            }
        case .failed:
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(onAirRed)
                Text("ERROR")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(onAirRed)
            }
        case .cancelled:
            HStack(spacing: 5) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(VoiceStationTokens.rec)
                Text("CANCELLED")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(VoiceStationTokens.rec)
            }
        case .modeChanged(let mode):
            HStack(spacing: 5) {
                Text("MODE")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                Text(mode.badgeName)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(Self.accent(for: mode))
            }
        }
    }

    /// The mode switch as it appears in the HUD: every mode at once, so the
    /// confirmation also says what the others are and which way the toggle runs.
    private func modeStripView(active: ProcessingMode) -> some View {
        HStack(spacing: 3) {
            ForEach(ProcessingMode.allCases, id: \.self) { mode in
                let isOn = mode == active
                Text(mode.badgeName)
                    .font(.system(size: 7, weight: .heavy, design: .monospaced))
                    .foregroundColor(isOn ? .black.opacity(0.85) : .white.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .frame(height: 14)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isOn ? Self.accent(for: mode) : Color.white.opacity(0.1))
                    )
                    .shadow(
                        color: isOn ? Self.accent(for: mode).opacity(0.8) : .clear,
                        radius: 3
                    )
            }
        }
        .frame(height: 14)
    }

    @ViewBuilder
    private var telemetryStripView: some View {
        HStack(spacing: 5) {
            switch viewModel.mode {
            case .recording:
                HStack(spacing: 2) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7))
                        .foregroundColor(vintageGold)
                    Text("LIVE")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundColor(vintageGold)
                }
                // How much of the screen this run is about to send. Transform is the one
                // mode whose payload the speaker did not dictate, so the size is the only
                // thing on the capsule that can tell her the selection is the sentence
                // she highlighted and not the whole file — while Escape still works.
                if let characters = viewModel.selectionCharacters {
                    Text("·")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                    Text("\(characters) CHARS")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundColor(HUDBadge.selectionIsLarge(characters) ? onAirRed : skyBlue)
                }

                // R9: the capsule showed "44.1 kHz" while `AudioRecorder` opens the
                // microphone at 16 kHz mono. It was a decoration in the shape of a
                // reading, and a wrong one. Nothing measures a sample rate per run, so
                // the row names the stage instead of inventing a figure for it.
                Text("·")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                Text("WHISPER")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))

            case .processing:
                HStack(spacing: 2) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 7))
                        .foregroundColor(skyBlue)
                    Text("CLEANING")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundColor(skyBlue)
                }
                Text("·")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                Text("INFERENCE...")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(vintageGold)
                Text("·")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                Text(viewModel.cleanerName.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))

            case .completed:
                if let wpm = viewModel.measuredWPM {
                    HStack(spacing: 2) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 7))
                            .foregroundColor(vintageGold)
                        Text("\(wpm) WPM")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .foregroundColor(vintageGold)
                    }
                    Text("·")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }

                if let latency = viewModel.latencySeconds {
                    Text(String(format: "%.1fs LATENCY", latency))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(skyBlue)
                    Text("·")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }

                if let model = viewModel.answeredModel {
                    Text(HUDBadge.shortModelName(model))
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                } else if viewModel.cleanerName == "literal" {
                    Text("LITERAL")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                }

            case .actionExecuted(let desc):
                HStack(spacing: 2) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7))
                        .foregroundColor(vintageGold)
                    Text("ACTION")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundColor(vintageGold)
                }
                Text("·")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                Text(desc)
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)

            case .failed, .cancelled, .modeChanged:
                EmptyView()
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 14)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.black.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private var vuMeterView: some View {
        HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { index in
                vuBar(for: index)
            }

            // The way out, shown only while there is something to take back. It used to
            // share the header with the wordmark, which could hold one or the other; the
            // meter is twelve 9pt bars in a 226pt row, so the 85pt it never used is where
            // the reminder belongs. Escape worked the whole time it was missing — an
            // undiscoverable way out is still a way out, which is why nothing failed.
            if isRecording {
                Spacer(minLength: 4)
                Text("ESC ✕")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize()
            }
        }
        .frame(height: 14)
    }

    private func vuBar(for index: Int) -> some View {
        let activeCount: Int
        switch viewModel.mode {
        case .recording:
            let scaledLevel = Int(viewModel.audioLevel * 12.0)
            activeCount = max(1, scaledLevel)
        case .processing:
            // Moving wave effect during AI inference
            let wavePos = viewModel.processingStep % 12
            let dist = abs(index - wavePos)
            activeCount = dist <= 2 ? 12 : 0
        case .completed, .actionExecuted:
            activeCount = 12
        case .failed:
            activeCount = 0
        case .modeChanged:
            // The strip replaces the meter in this state; the bars are never drawn.
            activeCount = 0
        case .cancelled:
            activeCount = 0
        }

        let isActive = index < activeCount
        let barColor: Color
        if index < 7 {
            barColor = skyBlue
        } else if index < 10 {
            barColor = vintageGold
        } else {
            barColor = onAirRed
        }

        let isProcessing: Bool
        if case .processing = viewModel.mode {
            isProcessing = true
        } else {
            isProcessing = false
        }
        let animValue = isProcessing ? Double(viewModel.processingStep) : Double(viewModel.audioLevel)
        return RoundedRectangle(cornerRadius: 1.5)
            .fill(isActive ? barColor : Color.white.opacity(0.1))
            .frame(width: 9, height: 12)
            .shadow(color: isActive ? barColor.opacity(0.8) : .clear, radius: 3)
            .animation(.easeOut(duration: 0.08), value: animValue)
    }
}

/// A vintage chrome condenser microphone with horizontal ribs (Shure 55 style).
struct VintageMicIcon: View {
    let color: Color

    var body: some View {
        ZStack {
            // U-shaped metal cradle
            Path { path in
                path.addArc(
                    center: CGPoint(x: 13, y: 13),
                    radius: 9,
                    startAngle: .degrees(15),
                    endAngle: .degrees(165),
                    clockwise: false
                )
            }
            .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: 26, height: 26)

            // Stem and pedestal base
            Path { path in
                path.move(to: CGPoint(x: 13, y: 22))
                path.addLine(to: CGPoint(x: 13, y: 24.5))
                path.move(to: CGPoint(x: 9, y: 24.5))
                path.addLine(to: CGPoint(x: 17, y: 24.5))
            }
            .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: 26, height: 26)

            // Chrome Capsule Body
            RoundedRectangle(cornerRadius: 4.5)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.95),
                            color.opacity(0.85),
                            color.opacity(0.65)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 11, height: 15)
                .offset(y: -2.5)

            // Horizontal Chrome Grille Slits / Ribs
            VStack(spacing: 1.5) {
                ForEach(0..<4, id: \.self) { _ in
                    Rectangle()
                        .fill(VoiceStationTokens.navy.opacity(0.95))
                        .frame(width: 9, height: 1.2)
                }
            }
            .offset(y: -2.5)
        }
        .frame(width: 26, height: 26)
    }
}
