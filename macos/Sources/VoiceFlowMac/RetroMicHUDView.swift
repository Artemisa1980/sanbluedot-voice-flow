import SwiftUI
import VoiceFlowMacCore

enum HUDMode {
    case recording
    case processing
    case completed(didAutoPaste: Bool, usedFallback: Bool)
    case actionExecuted(description: String)
    case failed(String)
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
}

struct RetroMicHUDView: View {
    @ObservedObject var viewModel: HUDViewModel
    
    // sanblue brand colors
    private let skyBlue = Color(red: 0x7C / 255.0, green: 0xB3 / 255.0, blue: 0xE8 / 255.0)
    private let retroNavy = Color(red: 0x16 / 255.0, green: 0x21 / 255.0, blue: 0x3E / 255.0)
    private let vintageGold = Color(red: 0xEF / 255.0, green: 0xC1 / 255.0, blue: 0x5E / 255.0)
    private let onAirRed = Color(red: 1.0, green: 0.27, blue: 0.23)

    var body: some View {
        HStack(spacing: 16) {
            // Vintage Microphone Graphic
            ZStack {
                Circle()
                    .fill(retroNavy.opacity(0.8))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .stroke(LinearGradient(
                                colors: [.white.opacity(0.4), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ), lineWidth: 1.5)
                    )
                
                Image(systemName: "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            .shadow(color: iconGlowColor, radius: 6)

            VStack(alignment: .leading, spacing: 6) {
                // Status header (ON AIR + Mode)
                HStack(spacing: 8) {
                    statusBadge
                    
                    Spacer()
                    
                    // brand.md: the dot is ALWAYS #7CB3E8 and `sanblue` is gold on a
                    // dark surface. A single-colour lockup loses the one contrast that
                    // identifies the mark, so the two words are drawn separately here
                    // exactly as they are in the station window header and footer.
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("sanblue")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(vintageGold.opacity(0.9))
                        Text("dot")
                            .font(.system(size: 7, weight: .heavy, design: .monospaced))
                            .foregroundColor(skyBlue)
                            .baselineOffset(5)
                    }
                }
                
                // LED VU-Meter equalizer or processing wave
                vuMeterView
            }
            .frame(width: 195)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.75))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(retroNavy.opacity(0.35))
                        .blur(radius: 20)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.25),
                                    skyBlue.opacity(0.3),
                                    .white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 15, x: 0, y: 8)
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
        }
    }

    private var recordingBadgeText: String {
        switch viewModel.processingMode {
        case .translate:
            return "ON AIR • ES➔EN"
        case .meeting:
            return "ON AIR • MEETING"
        case .actions:
            return "ON AIR • ACTION"
        case .clean:
            return "ON AIR"
        }
    }

    private var processingBadgeText: String {
        let provider = viewModel.cleanerName.uppercased()
        switch viewModel.processingMode {
        case .translate:
            return "TRANSLATING (\(provider))"
        case .meeting:
            return "STRUCTURING (\(provider))"
        case .actions:
            return "PARSING ACTION"
        case .clean:
            return "CLEANING (\(provider))"
        }
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
        case .completed(let didAutoPaste, _):
            HStack(spacing: 5) {
                Image(systemName: didAutoPaste ? "checkmark.circle.fill" : "doc.on.clipboard.fill")
                    .font(.system(size: 10))
                    .foregroundColor(VoiceStationTokens.ok)
                Text(didAutoPaste ? "PASTED" : "COPIED")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(VoiceStationTokens.ok)
                if let model = viewModel.answeredModel {
                    Text(Self.shortModelName(model))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(vintageGold.opacity(0.85))
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
        }
    }

    /// `gemini-3.6-flash` reads as `3.6` in a HUD this narrow. The full identifier
    /// stays in the control window's activity log.
    static func shortModelName(_ model: String) -> String {
        model
            .replacingOccurrences(of: "gemini-", with: "")
            .replacingOccurrences(of: "-flash", with: "")
    }

    private var vuMeterView: some View {
        HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { index in
                vuBar(for: index)
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
