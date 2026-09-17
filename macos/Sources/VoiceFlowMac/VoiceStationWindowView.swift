import SwiftUI
import CoreText
import VoiceFlowMacCore

// MARK: - Design System Tokens (from design-system.md)
public enum VoiceStationTokens {
    // Approved Light Palette
    public static let appBg = Color(red: 0xA9 / 255.0, green: 0xD3 / 255.0, blue: 0xC0 / 255.0) // #A9D3C0 Mint-green soft
    public static let panelBg = Color(red: 0xF8 / 255.0, green: 0xEC / 255.0, blue: 0xCF / 255.0) // #F8ECCF Light amber/paper
    public static let panelHeader = Color(red: 0x98 / 255.0, green: 0xAA / 255.0, blue: 0xB2 / 255.0) // #98AAB2 Dusty blue
    public static let controlBg = Color(red: 0x90 / 255.0, green: 0x69 / 255.0, blue: 0x61 / 255.0) // #906961 Deep clay
    public static let controlDangerBg = Color(red: 0x8A / 255.0, green: 0x61 / 255.0, blue: 0x5A / 255.0) // #8A615A Dark clay
    public static let gold = Color(red: 0xEF / 255.0, green: 0xC1 / 255.0, blue: 0x5E / 255.0) // #EFC15E Amber/gold
    public static let navy = Color(red: 0x16 / 255.0, green: 0x21 / 255.0, blue: 0x3E / 255.0) // #16213E Navy/border/text
    public static let dotBlue = Color(red: 0x7C / 255.0, green: 0xB3 / 255.0, blue: 0xE8 / 255.0) // #7CB3E8 Dot blue
    public static let accentHover = Color(red: 0x93 / 255.0, green: 0xC4 / 255.0, blue: 0xF0 / 255.0) // #93C4F0 Accent hover
    public static let textMuted = Color(red: 0x40 / 255.0, green: 0x51 / 255.0, blue: 0x47 / 255.0) // #405147 Muted ink
    public static let inputCream = Color(red: 0xFF / 255.0, green: 0xF9 / 255.0, blue: 0xE9 / 255.0) // #FFF9E9 Input cream
    public static let controlText = Color(red: 0xFF / 255.0, green: 0xF7 / 255.0, blue: 0xEF / 255.0) // #FFF7EF Clay control text
    public static let footerMuted = Color(red: 0xAA / 255.0, green: 0xB1 / 255.0, blue: 0xC1 / 255.0) // #AAB1C1 Footer muted copy
    public static let danger = Color(red: 0xC0 / 255.0, green: 0x39 / 255.0, blue: 0x2B / 255.0) // #C0392B Semantic danger
    public static let consoleBg = Color(red: 0x26 / 255.0, green: 0x23 / 255.0, blue: 0x19 / 255.0) // #262319 Dark olive
    public static let headerBtnAmber = Color(red: 0xF4 / 255.0, green: 0xE3 / 255.0, blue: 0xBC / 255.0) // #F4E3BC Header control amber

    // Status palette. Taken from the brand's photo-derived family, never from the
    // system: `Color.green` is adaptive, so it changed the app's ready state with the
    // viewer's macOS settings. See design-system.md §Status palette.
    public static let ok = Color(red: 0x5F / 255.0, green: 0x70 / 255.0, blue: 0x50 / 255.0) // #5F7050 Sage-deep
    public static let working = Color(red: 0xD9 / 255.0, green: 0x8A / 255.0, blue: 0x2B / 255.0) // #D98A2B Amber-deep
    public static let rec = Color(red: 0xFF / 255.0, green: 0x7B / 255.0, blue: 0x6B / 255.0) // #FF7B6B Coral

    // Console badge palette. These are not brand colours and are not used on the mint
    // canvas: they exist to tell eight log categories apart at 7pt on the dark olive
    // console ground, where the brand's own family collapses into two readable hues.
    // Approved by the owner on 2026-09-02, after they had already shipped as literals.
    public static let logAction = Color(red: 0xF3 / 255.0, green: 0x9C / 255.0, blue: 0x12 / 255.0) // #F39C12 Amber-orange
    public static let logSnippet = Color(red: 0xA7 / 255.0, green: 0x8B / 255.0, blue: 0xFA / 255.0) // #A78BFA Violet
    public static let logPaste = Color(red: 0x2E / 255.0, green: 0xCC / 255.0, blue: 0x71 / 255.0) // #2ECC71 Emerald

    /// The lit half of the microphone's radial gradient, one step above navy.
    public static let micHighlight = Color(red: 0x2C / 255.0, green: 0x3A / 255.0, blue: 0x63 / 255.0) // #2C3A63

    /// On-air red. Hotter than the coral `rec`, and used only where a recording is
    /// live: the meter's last bars and the floating capsule's badge.
    public static let onAir = Color(red: 0xFF / 255.0, green: 0x45 / 255.0, blue: 0x3B / 255.0) // #FF453B

    /// The version the badge shows, read from the bundle so the badge and
    /// `CFBundleShortVersionString` cannot drift apart again. A `swift run` of the
    /// target has no bundle version, and falls back to the unpackaged label.
    public static let displayedVersion: String = {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let short, !short.isEmpty else { return "dev" }
        return "v\(short)"
    }()

    // Typography
    public static func pixel(_ size: CGFloat) -> Font {
        .custom("Press Start 2P", size: size)
    }

    public static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Log Category
// `LogCategory` itself lives in `VoiceFlowMacCore`, where a check can reach the rule
// that assigns it. Only its colour belongs to the view.
extension LogCategory {
    public var badgeColor: Color {
        switch self {
        case .stt: return VoiceStationTokens.dotBlue
        case .gemini: return VoiceStationTokens.gold
        case .ollama: return VoiceStationTokens.appBg
        case .action: return VoiceStationTokens.logAction
        case .snippet: return VoiceStationTokens.logSnippet
        case .paste: return VoiceStationTokens.logPaste
        case .system: return VoiceStationTokens.panelHeader
        case .warn: return VoiceStationTokens.danger
        }
    }
}

// MARK: - Console Filter Mode
public enum ConsoleFilterMode: String, CaseIterable, Sendable {
    case all = "ALL"
    case audio = "MIC/STT"
    case ai = "AI CLEAN"
    case actions = "ACTIONS"
    case snippets = "SNIPPETS"
    case system = "SYSTEM"
    /// Warnings and failures, which used to sit inside SYSTEM among the routine lines.
    /// One failure among thirty "recording started…" entries is a failure nobody sees.
    case errors = "ERRORS"
}

// MARK: - Activity Log Item
public struct ActivityLogItem: Identifiable, Equatable {
    public let id = UUID()
    public let timestamp: String
    public let category: LogCategory
    public let message: String
    public let latency: Double?
    public let tags: [String]
    public let isHighlight: Bool

    public init(
        message: String,
        category: LogCategory = .system,
        latency: Double? = nil,
        tags: [String] = [],
        isHighlight: Bool = false
    ) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        self.timestamp = formatter.string(from: Date())
        self.category = category
        self.message = message
        self.latency = latency
        self.tags = tags
        self.isHighlight = isHighlight
    }
}

extension View {
    /// The retro extrusion: the side of the control, drawn as one solid slab behind the
    /// face and offset down and right.
    ///
    /// `shadow(radius: 0)` cannot do this. It projects a copy of the whole view, border
    /// included, so the copy's own outline shows above and to the left and the control
    /// reads as two buttons stacked. A slab has no outline and only its bottom and right
    /// can ever be seen.
    func retroExtrusion(
        radius: CGFloat,
        offset: CGFloat,
        color: Color = VoiceStationTokens.navy
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(color)
                .offset(x: offset, y: offset)
        )
    }
}

/// A block cursor blinking after the last console entry: the machine is still listening.
private struct ConsoleCursorView: View {
    let paused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: paused)) { context in
            let on = Int(context.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
            HStack(spacing: 6) {
                Text("listening")
                    .font(VoiceStationTokens.mono(size: 8.5))
                    .foregroundColor(VoiceStationTokens.gold.opacity(0.45))
                Rectangle()
                    .fill(VoiceStationTokens.appBg)
                    .frame(width: 7, height: 11)
                    .opacity(on ? 1 : 0.1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 2)
            .padding(.top, 2)
        }
        .frame(height: 14)
    }
}

/// The arrowhead on a chain connector.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Focus ring

extension View {
    /// Suppress the system keyboard focus ring. The station shows selection with its own
    /// fill and lamp; the macOS ring is a second, foreign selection language on top.
    /// `focusEffectDisabled` is macOS 14, and this app supports 13, so it is guarded.
    @ViewBuilder
    func voiceFlowNoFocusRing() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
    }
}

// MARK: - Right Card Tab
public enum RightCardTab: String, CaseIterable, Sendable {
    case activityLog = "TELEMETRY LOG"
    case historyTray = "HISTORY TRAY"
    case snippets = "SNIPPETS"
}

// MARK: - View Model
@MainActor
public final class VoiceStationViewModel: ObservableObject {
    @Published public var statusTitle: String = "Ready"
    @Published public var statusDetail: String = "Hold Fn/Globe anywhere, or hold the button below."
    @Published public var shortcutName: String = "Fn/Globe"
    @Published public var selectedCleaner: CleanerMode = .literal
    @Published public var selectedMode: ProcessingMode = .clean
    /// A way out that does not need a keyboard permission.
    ///
    /// Escape reaches the controller through the global event tap, which requires Input
    /// Monitoring. The app supports a speaker who never granted it and dictates with the
    /// button below, and that speaker had no way to take a recording back anywhere.
    public var onCancelRecording: (() -> Void)?

    /// Which engine's information sheet is open, if any. One at a time.
    @Published public var engineInfoShown: CleanerMode? = nil
    /// A cleanup the guard refused, kept until the speaker decides. The guard cannot
    /// prove a restructured sentence still means the same thing, but the speaker can
    /// read it, so the choice is offered instead of made for them.
    @Published public var rejectedCleanup: String? = nil
    public var onAcceptRejectedCleanup: ((String) -> Void)?
    public var onDismissRejectedCleanup: (() -> Void)?
    @Published public var selectedGeminiModel: GeminiModel = .preferredDefault
    @Published public var hasKey: Bool = false
    @Published public var isRecording: Bool = false
    @Published public var isRecordingEnabled: Bool = true
    @Published public var isSelectionEnabled: Bool = true
    /// The last refusal, for the surface the speaker is looking at.
    ///
    /// A control a run has locked used to be `.disabled`, which reports nothing: the
    /// press produced no switch and no reason, and a refusal indistinguishable from a
    /// dead button is the defect R3c names. The control now stays live, the press lands
    /// here, and the sentence is drawn where the press happened.
    @Published public var refusalNotice: String?
    @Published public var globalHotkeyAvailable: Bool = true
    @Published public var needsInputMonitoring: Bool = false
    @Published public var needsAccessibility: Bool = false
    @Published public var activeRightTab: RightCardTab = .activityLog
    @Published public var selectedFilter: ConsoleFilterMode = .all
    @Published public var audioLevel: Double = 0.0
    /// False while the window is minimised or fully covered. The idle animations read
    /// this and stop: a meter nobody can see should not keep waking the CPU.
    @Published public var isWindowVisible: Bool = true
    // No seeded values. Before the first dictation there is nothing to report, and a
    // plausible placeholder in a diagnostics bar is indistinguishable from a reading.
    @Published public var lastSTTLatency: Double?
    @Published public var lastLLMLatency: Double?
    @Published public var lastWPM: Int?
    @Published public var targetAppName: String = "Desktop"
    @Published public var targetAppProfile: String = "Direct Auto-Paste"
    @Published public var recentDictations: [DictationRecord] = []
    @Published public var snippets: [VoiceSnippet] = []
    @Published public var activityLogs: [ActivityLogItem] = [
        ActivityLogItem(message: "voice-station initialized · whisper local engine ready.", category: .system, tags: ["ggml-large-v3-turbo"], isHighlight: true),
        ActivityLogItem(message: "whisper: local engine, no dictation processed yet.", category: .stt, tags: ["local"]),
        ActivityLogItem(message: "shortcut: Fn/Globe global push-to-talk ready.", category: .system)
    ]

    public var onRecordPress: (() -> Void)?
    public var onRecordRelease: (() -> Void)?
    public var onCleanerSelect: ((CleanerMode) -> Void)?
    public var onModeSelect: ((ProcessingMode) -> Void)?
    public var onGeminiModelSelect: ((GeminiModel) -> Void)?
    public var onSetAPIKey: ((CleanerMode) -> Void)?
    public var onForgetAPIKey: ((CleanerMode) -> Void)?
    public var onOpenInputMonitoring: (() -> Void)?
    public var onOpenAccessibility: (() -> Void)?
    public var onRetryPermissions: (() -> Void)?
    public var onCopyHistoryRecord: ((DictationRecord) -> Void)?
    public var onCopyRawRecord: ((DictationRecord) -> Void)?
    public var onRepasteHistoryRecord: ((DictationRecord) -> Void)?
    public var onClearHistory: (() -> Void)?
    public var onAddSnippet: ((String, String, String?) -> Void)?
    public var onDeleteSnippet: ((UUID) -> Void)?

    public init() {
        registerCustomFonts()
    }

    private func registerCustomFonts() {
        let candidates = [
            Bundle.main.url(forResource: "PressStart2P-Regular", withExtension: "ttf", subdirectory: "Fonts"),
            Bundle.main.url(forResource: "PressStart2P-Regular", withExtension: "ttf"),
            Bundle.main.resourceURL?.appendingPathComponent("Fonts/PressStart2P-Regular.ttf")
        ]
        for url in candidates.compactMap({ $0 }) {
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                break
            }
        }
    }

    /// Refuse out loud. The notice clears itself so it cannot outlive the run that
    /// caused it, and a later refusal replaces an earlier one rather than queueing.
    public func reportRefusal(_ message: String) {
        refusalNotice = message
        addLog(message, isHighlight: true)
        let token = UUID()
        refusalToken = token
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, self.refusalToken == token else { return }
            self.refusalNotice = nil
        }
    }

    private var refusalToken = UUID()

    public func addLog(
        _ message: String,
        category: LogCategory = .system,
        latency: Double? = nil,
        tags: [String] = [],
        isHighlight: Bool = false
    ) {
        let autoCategory = category != .system
            ? category
            : LogCategory.inferred(from: message)

        activityLogs.append(ActivityLogItem(
            message: message,
            category: autoCategory,
            latency: latency,
            tags: tags,
            isHighlight: isHighlight
        ))
        if activityLogs.count > 50 {
            activityLogs.removeFirst(activityLogs.count - 50)
        }
    }
}

// MARK: - Main Voice Station Window View
public struct VoiceStationWindowView: View {
    @ObservedObject public var viewModel: VoiceStationViewModel
    @State private var haloOpen = false

    public init(viewModel: VoiceStationViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar

            FocusHomeView(
                viewModel: viewModel,
                signalChain: AnyView(signalChainBar),
                controlCard: AnyView(leftControlCard),
                providers: AnyView(patchBay),
                console: AnyView(rightActivityCard(showsTabs: true)),
                snippetsPanel: AnyView(snippetsPaperPanel),
                historyPanel: AnyView(historyPaperPanel),
                diagnosticsPanel: AnyView(diagnosticsPaperPanel)
            )

            footerBar
        }
        // No minimum height here. The header and the footer carry fixed heights and the
        // middle section is elastic, so whatever the container gives is absorbed there.
        // A root minimum taller than the container makes the view overflow, and an
        // overflowing VStack loses its first and last children first — which is exactly
        // the chrome the speaker needs to keep.
        .frame(minWidth: 760, maxWidth: .infinity, maxHeight: .infinity)
        .background(VoiceStationTokens.navy)
        .edgesIgnoringSafeArea(.all)
    }

    // MARK: - Header Bar (Strict Design System Contract §Header)
    private var headerBar: some View {
        ZStack {
            VoiceStationTokens.navy

            // Centered against the header itself. Two equal spacers between the side
            // groups centered it in the leftover space instead, so the wider left group
            // pushed it right by half its own width — measured at 150pt on an 840pt
            // window. It hides rather than collides when the header runs out of room;
            // the window's own title bar already carries the same name.
            GeometryReader { headerGeometry in
                if headerGeometry.size.width >= 600 {
                    Text("retro voice-station")
                        .font(VoiceStationTokens.pixel(9))
                        .foregroundColor(VoiceStationTokens.panelBg)
                        .tracking(0.4)
                        .lineLimit(1)
                        .frame(
                            width: headerGeometry.size.width,
                            height: headerGeometry.size.height
                        )
                }
            }
            .allowsHitTesting(false)

            HStack(alignment: .center, spacing: 12) {
                // SANDY.SYSDEV opens the header at the left edge. The circular badge
                // that sat here was removed on 2026-09-01: the header keeps the brand
                // through the wordmark at its right and the footer lockup, which is
                // where `brand.md` actually requires the mark. The badge remains the
                // master for the application icon.
                // SANDY.SYSDEV: Press Start 2P, 12px
                Text("SANDY.SYSDEV")
                    .font(VoiceStationTokens.pixel(12))
                    .foregroundColor(VoiceStationTokens.panelBg)
                    .tracking(0.6)
                    .lineLimit(1)

                // Version Badge: Press Start 2P, 8px, gold surface and navy text
                Text(VoiceStationTokens.displayedVersion)
                    .font(VoiceStationTokens.pixel(8))
                    .foregroundColor(VoiceStationTokens.navy)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(VoiceStationTokens.gold)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .lineLimit(1)

                Spacer(minLength: 24)

                // sanblueᵈᵒᵗ Wordmark: system monospaced bold, 12px; gold word, dot-blue superscript
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("sanblue")
                        .font(VoiceStationTokens.mono(size: 12, weight: .bold))
                        .foregroundColor(VoiceStationTokens.gold)

                    Text("dot")
                        .font(VoiceStationTokens.mono(size: 8, weight: .heavy))
                        .foregroundColor(VoiceStationTokens.dotBlue)
                        .baselineOffset(5)
                }
                .lineLimit(1)
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 72)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(VoiceStationTokens.gold)
                .frame(height: 2)
        }
    }

    // MARK: - Mode Selector Bar (Tags from Proposal)
    /// The switch shows the mode, not its description. The long name belongs to the
    /// announcement, not to a tile the eye has to scan four of.
    private func shortTitle(for mode: ProcessingMode) -> String {
        switch mode {
        case .clean: return "CLEAN"
        case .translate: return "ES ➔ EN"
        case .meeting: return "NOTES"
        case .actions: return "ACTIONS"
        case .transform: return "TRANSFORM"
        }
    }

    // MARK: - Microphone hero

    /// ON AIR while recording, READY otherwise. A filled pill with a navy hairline,
    /// because no status colour reaches 4.5 as bare ink on the mint canvas.
    /// Take back the recording. Beside the badge, and only while there is something to
    /// take back — Escape does the same thing but only for a speaker who granted Input
    /// Monitoring, and that is not everyone.
    private var cancelRecordingButton: some View {
        Button(action: { viewModel.onCancelRecording?() }) {
            HStack(spacing: 4) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .heavy))
                Text("CANCEL")
                    .font(VoiceStationTokens.mono(size: 9, weight: .bold))
                    .tracking(1.0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(VoiceStationTokens.panelBg)
            .foregroundColor(VoiceStationTokens.navy)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(VoiceStationTokens.navy, lineWidth: 2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .voiceFlowNoFocusRing()
        .help("Discard this recording. Escape does the same.")
    }

    private var onAirBadge: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(VoiceStationTokens.navy)
                .frame(width: 8, height: 8)
                .opacity(viewModel.isRecording ? 1 : 0.45)
                .animation(
                    viewModel.isRecording
                        ? .easeInOut(duration: 0.55).repeatForever(autoreverses: true)
                        : .default,
                    value: viewModel.isRecording
                )

            Text(viewModel.isRecording ? "ON AIR" : "READY")
                .font(VoiceStationTokens.mono(size: 9, weight: .bold))
                .tracking(1.4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(VoiceStationTokens.rec)
        .foregroundColor(VoiceStationTokens.navy)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(VoiceStationTokens.navy, lineWidth: 2))
    }

    /// The station's microphone: a ribbon capsule behind a ticked dial bezel.
    ///
    /// It moves like a speaker cone. At rest the swell is ambient and small — it says the
    /// station is powered, and it never pretends to be a reading. While recording, the
    /// same swell is driven by the measured input level, so what moves is the speaker's
    /// own voice rather than a timer. R9 applies to motion as much as to figures.
    private var micCapsule: some View {
        TimelineView(
            .animation(minimumInterval: 1.0 / 30.0, paused: !viewModel.isWindowVisible)
        ) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let ambient = (sin(time * 1.9) + 1) / 2
            // While recording the swell is the measured level. The ambient floor under
            // it is deliberately small: a microphone that is open and hearing silence
            // should look powered, not stopped, and the floor is far below anything a
            // voice produces, so it can never be mistaken for a reading.
            let level = min(max(viewModel.audioLevel, 0), 1)
            let drive = viewModel.isRecording
                ? max(level, ambient * 0.12)
                : ambient * 0.55

            ZStack {
                // The bass ring: it opens with the level and fades as it goes.
                Circle()
                    .stroke(
                        viewModel.isRecording
                            ? VoiceStationTokens.onAir
                            : VoiceStationTokens.gold,
                        lineWidth: 3
                    )
                    .frame(width: 118, height: 118)
                    .scaleEffect(1 + drive * 0.16)
                    .opacity(0.62 * (1 - drive * 0.8))

                // Bezel, with the dial notches around its rim.
                Circle()
                    .fill(VoiceStationTokens.panelBg)
                    .frame(width: 118, height: 118)
                    .overlay(Circle().stroke(VoiceStationTokens.navy.opacity(0.18), lineWidth: 1))
                    .overlay(dialNotches)
                    // The bezel pushes with the cone rather than standing still while a
                    // ring travels past it.
                    .scaleEffect(1 + drive * 0.03)
                    .background(
                        Circle()
                            .fill(VoiceStationTokens.navy)
                            .frame(width: 118, height: 118)
                            .offset(x: 4, y: 5)
                    )

                // The face the capsule stands on.
                Circle()
                    .fill(VoiceStationTokens.inputCream)
                    .frame(width: 88, height: 88)
                    .overlay(Circle().stroke(VoiceStationTokens.navy, lineWidth: 2.5))
                    .overlay(
                        // The weighted base of the dial, as a thick arc along the floor.
                        Circle()
                            .trim(from: 0.08, to: 0.42)
                            .stroke(
                                VoiceStationTokens.navy,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .frame(width: 80, height: 80)
                    )

                ribbonCapsule
                    .scaleEffect(1 + drive * 0.09)
            }
            .frame(width: 138, height: 138)
        }
    }

    private var snippetsPaperPanel: some View {
        PaperChassis(viewModel: viewModel, system: "SNIPPETS.SYS", subtitle: "VOICE MACROS") {
            ChassisCount(value: viewModel.snippets.count, noun: "snippets")
        } content: {
            VoiceSnippetsTabView(viewModel: viewModel, palette: .paper)
        }
    }

    /// The log keeps its dark screen inside the same chassis. Its category badges —
    /// gold, mint, violet, emerald, red — were chosen for a near-black field, and they
    /// are what the eye scans for a failure. The chrome matches the other sections; the
    /// screen does not, and that difference now means something.
    private var diagnosticsPaperPanel: some View {
        PaperChassis(
            viewModel: viewModel,
            system: "DIAGNOSTICS.SYS",
            subtitle: "ACTIVITY LOG",
            ground: VoiceStationTokens.consoleBg
        ) {
            ChassisCount(value: viewModel.activityLogs.count, noun: "log entries")
        } content: {
            rightActivityCard(showsTabs: false, chrome: false)
        }
    }

    private var historyPaperPanel: some View {
        PaperChassis(viewModel: viewModel, system: "HISTORY.SYS", subtitle: "RECENT DICTATIONS") {
            HStack(spacing: 8) {
                if !viewModel.recentDictations.isEmpty {
                    Button(action: { viewModel.onClearHistory?() }) {
                        Text("CLEAR")
                            .font(VoiceStationTokens.mono(size: 8.5, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(VoiceStationTokens.danger.opacity(0.85))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .voiceFlowNoFocusRing()
                }
                ChassisCount(value: viewModel.recentDictations.count, noun: "dictations")
            }
        } content: {
            // Inside the screen, above the list. History is where a delivery is
            // reviewed, and a held-back cleanup is a question about the last one — so
            // the offer belongs with the rows it concerns. Drawn on the mint canvas
            // instead, it sat outside the chassis and pushed the whole section down.
            VStack(spacing: 10) {
                if let rejected = viewModel.rejectedCleanup {
                    rejectedCleanupCard(rejected)
                }
                DictationHistoryTabView(viewModel: viewModel, palette: .paper)
            }
        }
    }

    /// What the console is showing, for the header that no longer offers tabs.
    private var activeTabLabel: String {
        switch viewModel.activeRightTab {
        case .activityLog: return "LOG"
        case .historyTray: return "HISTORY \(viewModel.recentDictations.count)"
        case .snippets: return "SNIPPETS \(viewModel.snippets.count)"
        }
    }

    /// The notched rim. Thirty-six marks read as a machined dial at this size without
    /// closing into a solid ring.
    private var dialNotches: some View {
        ZStack {
            ForEach(0..<36, id: \.self) { index in
                Capsule()
                    .fill(VoiceStationTokens.navy.opacity(0.32))
                    .frame(width: 1.6, height: 7)
                    .offset(y: -51)
                    .rotationEffect(.degrees(Double(index) * 10))
            }
        }
    }

    /// The ribbon element: a navy body under horizontal grille slats, split by the gold
    /// band, on a stem and a pedestal foot.
    private var ribbonCapsule: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                VoiceStationTokens.micHighlight,
                                VoiceStationTokens.navy
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 46)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(VoiceStationTokens.navy, lineWidth: 1.5)
                    )

                VStack(spacing: 2.6) {
                    ForEach(0..<8, id: \.self) { _ in
                        Capsule()
                            .fill(VoiceStationTokens.panelBg.opacity(0.78))
                            .frame(width: 20, height: 1.8)
                    }
                }

                Capsule()
                    .fill(VoiceStationTokens.gold)
                    .frame(width: 3.2, height: 40)
            }

            Rectangle()
                .fill(VoiceStationTokens.navy)
                .frame(width: 2.6, height: 11)

            Capsule()
                .fill(VoiceStationTokens.navy)
                .frame(width: 22, height: 3)
        }
        .offset(y: -3)
    }

    /// Twelve bars driven by the measured input level: blue through the working range,
    /// gold as it approaches the top, coral at the peak.
    /// The meter always moves, and what the movement means changes with the state.
    ///
    /// At rest the bars breathe on a slow wave at half opacity: an idle animation, not a
    /// reading, which is why it stays low and dim and never reaches the coral top. While
    /// recording, the same bars are driven by the measured input level at full colour,
    /// so what you see is your own voice. The wave keeps its per-bar phase in both
    /// states, so the meter never looks frozen the way it did before.
    private var liveMeter: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !viewModel.isWindowVisible)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(0..<12, id: \.self) { index in
                    // The phase offset per bar is what makes one bar rise while its
                    // neighbour falls, so the row reads as a wave travelling across it
                    // rather than twelve bars breathing together.
                    let wave = (sin(time * 2.0 + Double(index) * 0.85) + 1) / 2
                    let level = viewModel.isRecording
                        ? 0.30 + min(viewModel.audioLevel, 1.0) * 0.95
                        : 0.42
                    // How much of the height the wave owns. At rest it owns most of it:
                    // nothing is being measured, so the movement is decoration and may
                    // be broad. While recording it owns almost none, because the height
                    // is a reading of the speaker's voice and a wave large enough to see
                    // would be a wave large enough to lie.
                    let waveShare = viewModel.isRecording ? 0.22 : 0.65
                    let height = meterFloor
                        + (meterCeiling - meterFloor)
                        * barProfile(index)
                        * level
                        * (1 - waveShare + waveShare * wave)

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(meterColor(at: index))
                        .opacity(viewModel.isRecording ? 1 : 0.78)
                        .frame(width: 20, height: height)
                }
            }
            .frame(height: meterCeiling, alignment: .bottom)
        }
        .frame(height: meterCeiling)
    }

    private var meterFloor: CGFloat { 10 }
    private var meterCeiling: CGFloat { 40 }

    /// A meter is taller in the middle. Without this the bars read as a staircase that
    /// restarts, which is what the first build showed.
    private func barProfile(_ index: Int) -> CGFloat {
        let profile: [CGFloat] = [0.40, 0.52, 0.66, 0.80, 0.92, 1.00,
                                  0.96, 0.86, 0.74, 0.62, 0.50, 0.40]
        return profile[index % profile.count]
    }

    private func meterColor(at index: Int) -> Color {
        switch index {
        case 0...6: return VoiceStationTokens.dotBlue
        case 7...9: return VoiceStationTokens.gold
        default: return VoiceStationTokens.rec
        }
    }

    /// One mode as a switch tile: a lamp square, the short name, filled when active.
    private func modeTile(for mode: ProcessingMode) -> some View {
        let isOn = viewModel.selectedMode == mode
        return Button(action: {
            // R3c: refused while a dictation is in flight, and the refusal reported
            // rather than silent. The station's tile and the Modes page's tile answer
            // a locked run the same way.
            guard viewModel.isSelectionEnabled else {
                viewModel.reportRefusal(
                    "this run keeps \(shortTitle(for: viewModel.selectedMode)) · the mode changes once it is delivered")
                return
            }
            viewModel.selectedMode = mode
            viewModel.onModeSelect?(mode)
            viewModel.addLog("mode switched to: \(mode.rawValue)")
        }) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isOn ? VoiceStationTokens.dotBlue : Color.clear)
                    .frame(width: 13, height: 13)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(isOn ? VoiceStationTokens.panelBg : VoiceStationTokens.navy, lineWidth: 2)
                    )

                Text(shortTitle(for: mode))
                    .font(VoiceStationTokens.mono(size: 10, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 9)
            .background(isOn ? VoiceStationTokens.navy : VoiceStationTokens.inputCream)
            .foregroundColor(isOn ? VoiceStationTokens.panelBg : VoiceStationTokens.navy)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(VoiceStationTokens.navy, lineWidth: 2)
            )
            .retroExtrusion(
                radius: 9,
                offset: isOn ? 3 : 2,
                color: isOn ? VoiceStationTokens.controlDangerBg : VoiceStationTokens.navy
            )
        }
        .buttonStyle(.plain)
        .voiceFlowNoFocusRing()
    }

    // MARK: - Signal Chain (design-system.md §Signal chain)

    /// The path a dictation actually travels, drawn as four lit stages. It replaces the
    /// mode bar because the speaker's first question is not which mode is on, it is what
    /// the machine is doing and whether anything left this Mac.
    private var signalChainBar: some View {
        HStack(spacing: 0) {
            chainStage(
                caption: "INPUT",
                name: "Microphone",
                fill: VoiceStationTokens.dotBlue,
                inPath: true,
                hasRun: viewModel.isRecording || viewModel.lastSTTLatency != nil
            )
            chainLink
            chainStage(
                caption: "SPEECH · LOCAL",
                name: "whisper turbo",
                fill: VoiceStationTokens.dotBlue,
                inPath: true,
                hasRun: viewModel.lastSTTLatency != nil
            )
            chainLink
            chainStage(
                caption: viewModel.selectedCleaner.isCloud ? "CLEANUP · CLOUD" : "CLEANUP · LOCAL",
                name: cleanupStageName,
                fill: viewModel.selectedCleaner.isCloud
                    ? VoiceStationTokens.gold : VoiceStationTokens.ok,
                inPath: true,
                hasRun: viewModel.lastLLMLatency != nil
            )
            chainLink
            chainStage(
                caption: "OUTPUT",
                name: viewModel.targetAppName,
                fill: VoiceStationTokens.working,
                inPath: true,
                hasRun: !viewModel.recentDictations.isEmpty
            )
        }
    }

    /// The cleanup stage names what will answer, including the model when it is a cloud
    /// provider, so the chain never claims more than the configuration allows.
    private var cleanupStageName: String {
        switch viewModel.selectedCleaner {
        case .literal: return "no cleanup"
        case .ollama: return "ollama local"
        case .gemini: return "gemini \(viewModel.selectedGeminiModel.shortName)"
        }
    }

    private func chainStage(
        caption: String,
        name: String,
        fill: Color,
        inPath: Bool,
        hasRun: Bool
    ) -> some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(inPath ? fill : VoiceStationTokens.panelHeader)
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(VoiceStationTokens.navy, lineWidth: 2)
                )
                .overlay(
                    Circle()
                        .fill(VoiceStationTokens.navy)
                        .frame(width: 10, height: 10)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(caption)
                    .font(VoiceStationTokens.mono(size: 7.5, weight: .bold))
                    .foregroundColor(VoiceStationTokens.navy.opacity(0.55))
                    .lineLimit(1)
                Text(name)
                    .font(VoiceStationTokens.mono(size: 10, weight: .bold))
                    .foregroundColor(VoiceStationTokens.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 4)

            Circle()
                .fill(hasRun ? VoiceStationTokens.ok : VoiceStationTokens.navy.opacity(0.18))
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(VoiceStationTokens.navy, lineWidth: 1.5))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(inPath ? VoiceStationTokens.inputCream : VoiceStationTokens.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    VoiceStationTokens.navy,
                    style: StrokeStyle(
                        lineWidth: 2,
                        dash: inPath ? [] : [6, 4]
                    )
                )
        )
        .retroExtrusion(radius: 10, offset: inPath ? 3 : 0, color: inPath ? VoiceStationTokens.navy : .clear)
        .opacity(inPath ? 1 : 0.75)
    }

    private var chainLink: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !viewModel.isWindowVisible)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            // 0...1 twice a cycle, so a dot crosses the rail and restarts.
            let travel = (time.truncatingRemainder(dividingBy: 2.4)) / 2.4

            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(VoiceStationTokens.navy)
                        .frame(height: 2)
                    Triangle()
                        .fill(VoiceStationTokens.navy)
                        .frame(width: 8, height: 10)
                }

                Circle()
                    .fill(VoiceStationTokens.dotBlue)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(VoiceStationTokens.navy, lineWidth: 1))
                    .offset(x: 18 * travel)
                    .opacity(travel < 0.12 || travel > 0.88 ? 0 : 1)
            }
        }
        .frame(width: 26, height: 10)
    }

    /// The cleanup the guard would not accept, put in front of the speaker.
    ///
    /// The guard cannot prove that a restructured sentence still means what was said,
    /// and it is right not to guess. But throwing the text away unseen meant a good
    /// cleanup was lost four times in ten with nothing shown for it. The speaker can
    /// read a sentence, so the refusal becomes a question instead of a verdict.
    private func rejectedCleanupCard(_ rejected: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(VoiceStationTokens.working)
                    .frame(width: 8, height: 8)
                Text("CLEANUP HELD BACK")
                    .font(VoiceStationTokens.mono(size: 9, weight: .bold))
                    .foregroundColor(VoiceStationTokens.navy)
            }

            Text("It rewrote more than the guard can verify. Read it and decide.")
                .font(VoiceStationTokens.mono(size: 8))
                .foregroundColor(VoiceStationTokens.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.vertical, showsIndicators: false) {
                Text(rejected)
                    .font(VoiceStationTokens.mono(size: 9.5))
                    .foregroundColor(VoiceStationTokens.navy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 96)
            .padding(8)
            .background(VoiceStationTokens.inputCream)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(VoiceStationTokens.navy.opacity(0.5), lineWidth: 1)
            )

            HStack(spacing: 7) {
                Button(action: { viewModel.onAcceptRejectedCleanup?(rejected) }) {
                    Text("USE THIS")
                        .font(VoiceStationTokens.mono(size: 9, weight: .bold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(VoiceStationTokens.navy)
                        .foregroundColor(VoiceStationTokens.gold)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(VoiceStationTokens.navy, lineWidth: 1.5)
                        )
                        .retroExtrusion(radius: 6, offset: 2, color: VoiceStationTokens.controlDangerBg)
                }
                .buttonStyle(.plain)
                .voiceFlowNoFocusRing()

                Button(action: { viewModel.onDismissRejectedCleanup?() }) {
                    Text("KEEP MINE")
                        .font(VoiceStationTokens.mono(size: 9, weight: .bold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(VoiceStationTokens.panelBg)
                        .foregroundColor(VoiceStationTokens.navy)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(VoiceStationTokens.navy, lineWidth: 1.5)
                        )
                        .retroExtrusion(radius: 6, offset: 2)
                }
                .buttonStyle(.plain)
                .voiceFlowNoFocusRing()

                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VoiceStationTokens.headerBtnAmber)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(VoiceStationTokens.navy, lineWidth: 2)
        )
        .retroExtrusion(radius: 10, offset: 3)
    }

    // MARK: - Patch Bay

    /// The chain is also the control: the engine and, for a cloud provider, the model
    /// and its stored key. Each option carries the delivery measured on 2026-08-31, so
    /// the choice stays informed rather than a guess.
    private var patchBay: some View {
        HStack(alignment: .top, spacing: 10) {
            patchBank(label: "ENGINE") {
                ForEach(CleanerMode.allCases, id: \.self) { cleaner in
                    patchOption(
                        title: cleaner.displayName,
                        detail: nil,
                        isOn: viewModel.selectedCleaner == cleaner,
                        info: cleaner
                    ) {
                        guard viewModel.isSelectionEnabled else {
                            viewModel.reportRefusal(
                                "this run keeps \(viewModel.selectedCleaner.displayName) · the engine changes once it is delivered")
                            return
                        }
                        viewModel.selectedCleaner = cleaner
                        viewModel.onCleanerSelect?(cleaner)
                        viewModel.addLog("provider: \(cleaner.displayName)")
                    }
                }
            }
        }
    }

    private func patchBank<Content: View>(
        label: String,
        @ViewBuilder options: () -> Content
    ) -> some View {
        HStack(spacing: 7) {
            Text(label)
                .font(VoiceStationTokens.mono(size: 7.5, weight: .bold))
                .foregroundColor(VoiceStationTokens.navy.opacity(0.55))
                .lineLimit(1)
            options()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VoiceStationTokens.inputCream)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(VoiceStationTokens.navy, lineWidth: 2)
        )
        .retroExtrusion(radius: 10, offset: 3)
    }

    /// One engine option: a lamp, its name, and the `?` that explains it.
    ///
    /// The two are siblings inside one visual slab rather than a button inside a button.
    /// The mark sits in the space the name already left empty, so asking a question costs
    /// the row no width, and pressing it cannot change where the speaker's words go.
    private func patchOption(
        title: String,
        detail: String?,
        isOn: Bool,
        info: CleanerMode? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Button(action: action) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isOn ? VoiceStationTokens.ok : VoiceStationTokens.navy.opacity(0.16))
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle().stroke(
                                isOn ? VoiceStationTokens.panelBg : VoiceStationTokens.navy,
                                lineWidth: 1.5
                            )
                        )

                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(VoiceStationTokens.mono(size: 9.5, weight: .bold))
                            .lineLimit(1)
                        if let detail {
                            Text(detail)
                                .font(VoiceStationTokens.mono(size: 7.5))
                                .opacity(0.65)
                                .lineLimit(1)
                        }
                    }

                    // The spacer belongs INSIDE the button. Outside it, the button
                    // shrinks to the width of its own text and the empty half of the
                    // slab stops selecting the engine — which is exactly what happened
                    // when the mark was moved to the border and this went with it.
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .voiceFlowNoFocusRing()

            // Against the slab's right border. It drifts from the name as the window
            // grows, and the owner chose that over the ragged column the alternative
            // produced: the three marks line up, which is what makes the row read as
            // one control rather than three.
            if let info {
                engineInfoMark(for: info, onDark: isOn)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(isOn ? VoiceStationTokens.navy : VoiceStationTokens.panelBg)
        .foregroundColor(isOn ? VoiceStationTokens.panelBg : VoiceStationTokens.navy)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(VoiceStationTokens.navy, lineWidth: 1.5)
        )
        .retroExtrusion(
            radius: 7,
            offset: isOn ? 3 : 2,
            color: isOn ? VoiceStationTokens.controlDangerBg : VoiceStationTokens.navy
        )
    }

    /// The `?` inside an engine slab. It carries the opposite fill of the slab it sits
    /// in — navy on paper, gold on navy — so one rule keeps it legible in both states,
    /// and it stays flat: a slab inside a slab reads as noise at this size.
    private func engineInfoMark(for cleaner: CleanerMode, onDark: Bool) -> some View {
        Button(action: {
            viewModel.engineInfoShown = viewModel.engineInfoShown == cleaner ? nil : cleaner
        }) {
            Text("?")
                .font(VoiceStationTokens.mono(size: 8.5, weight: .bold))
                .frame(width: 15, height: 15)
                .background(onDark ? VoiceStationTokens.gold : VoiceStationTokens.navy)
                .foregroundColor(onDark ? VoiceStationTokens.navy : VoiceStationTokens.panelBg)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .voiceFlowNoFocusRing()
        .help("What this engine costs and delivers")
        .popover(
            isPresented: Binding(
                get: { viewModel.engineInfoShown == cleaner },
                set: { shown in viewModel.engineInfoShown = shown ? cleaner : nil }
            ),
            arrowEdge: .bottom
        ) {
            engineInfoSheet(for: cleaner)
        }
    }

    /// Measured facts only. A panel built to help someone decide is the worst place for
    /// a number nobody measured, so an engine with no measurement says that instead.
    private func engineInfoSheet(for cleaner: CleanerMode) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(cleaner.displayName.uppercased())
                .font(VoiceStationTokens.mono(size: 9, weight: .bold))
                .foregroundColor(VoiceStationTokens.gold)

            ForEach(cleaner.facts, id: \.label) { fact in
                VStack(alignment: .leading, spacing: 1) {
                    Text(fact.label)
                        .font(VoiceStationTokens.mono(size: 7, weight: .bold))
                        .foregroundColor(VoiceStationTokens.gold.opacity(0.55))
                    Text(fact.value)
                        .font(VoiceStationTokens.mono(size: 9))
                        .foregroundColor(VoiceStationTokens.inputCream)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider().overlay(VoiceStationTokens.gold.opacity(0.25))

            Text(cleaner.recommendation)
                .font(VoiceStationTokens.mono(size: 9, weight: .bold))
                .foregroundColor(VoiceStationTokens.inputCream)
                .fixedSize(horizontal: false, vertical: true)

            if let measured = cleaner.factsMeasuredOn {
                Text("measured \(measured) · nothing re-measures")
                    .font(VoiceStationTokens.mono(size: 7))
                    .foregroundColor(VoiceStationTokens.gold.opacity(0.5))
            }
        }
        .padding(14)
        .frame(width: 290, alignment: .leading)
        .background(VoiceStationTokens.consoleBg)
    }

    // MARK: - Left Control Card (Light Amber / Paper #F8ECCF)
    private var leftControlCard: some View {
        VStack(spacing: 0) {
            // The indicator is shown. This panel grows with the mode list and with a
            // held-back cleanup, so it can overflow — and with the indicator hidden the
            // overflow did not read as "there is more below", it read as a card cut in
            // half by the panel edge. A surface that can scroll says so.
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    // The microphone is the protagonist: it is the only element at
                    // this size, so the eye knows where the app begins. The capsule is
                    // the hold control itself, and the meter under it moves with the
                    // real audio level rather than on a timer.
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            onAirBadge
                            if viewModel.isRecording {
                                cancelRecordingButton
                            }
                        }

                        Button(action: {}) {
                            micCapsule
                        }
                        .buttonStyle(HoldToRecordButtonStyle(
                            onPress: { viewModel.onRecordPress?() },
                            onRelease: { viewModel.onRecordRelease?() }
                        ))
                        .voiceFlowNoFocusRing()
                        .disabled(!viewModel.isRecordingEnabled)

                        liveMeter

                        Text("Hold the capsule, or \(viewModel.shortcutName) in any app")
                            .font(VoiceStationTokens.mono(size: 9.5))
                            .foregroundColor(VoiceStationTokens.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)

                    // A cleanup the guard refused, offered rather than discarded.
                    //
                    // It sits above the mode switch because it is the only thing in this
                    // panel that asks for an answer, and it must not be the thing that
                    // scrolls away. Below the switch it was: the grid is two columns over
                    // every mode, so a fifth mode turned two rows into three and pushed
                    // the card past the bottom of a scroll view that shows no indicator.
                    // The two buttons that answer it were cut by the panel edge, and the
                    // panel gave no sign there was anything below to reach.
                    if let rejected = viewModel.rejectedCleanup {
                        rejectedCleanupCard(rejected)
                    }

                    // Modes moved here from the top bar, which the signal chain now
                    // occupies. The switch shows the active mode at a glance instead of
                    // buttons of identical weight. It is built from the mode list, so it
                    // grows a row whenever a mode is added — four modes filled two rows,
                    // five fill three.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MODE")
                            .font(VoiceStationTokens.mono(size: 9.5, weight: .bold))
                            .foregroundColor(VoiceStationTokens.navy)

                        let columns = [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ]
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(ProcessingMode.allCases, id: \.self) { mode in
                                modeTile(for: mode)
                            }
                        }
                    }

                    // Permissions moved to Settings, which owns them. Kept here they were
                    // the one block that made this panel outgrow its card, and the panel
                    // is meant to stand still.

                }
                .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VoiceStationTokens.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VoiceStationTokens.navy, lineWidth: 3))
        .retroExtrusion(radius: 14, offset: 5)
    }

    // MARK: - Right Activity & Terminal Log Card (Dark Olive #262319)
    /// The console.
    ///
    /// `showsTabs` is false where the sidebar already names the destination: repeating
    /// LOG / HISTORY / SNIPPETS there gave one console two navigations that could
    /// disagree. On Home the tabs stay, because there the sidebar is somewhere else.
    private func rightActivityCard(showsTabs: Bool, chrome: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with Tab Switcher
            if chrome {
            HStack(spacing: 6) {
                Image(systemName: viewModel.activeRightTab == .activityLog ? "terminal.fill" : (viewModel.activeRightTab == .historyTray ? "clock.arrow.circlepath" : "text.quote"))
                    .foregroundColor(VoiceStationTokens.gold)
                    .font(.system(size: 10))

                if showsTabs {
                HStack(spacing: 3) {
                    Button(action: { viewModel.activeRightTab = .activityLog }) {
                        Text("LOG")
                            .font(VoiceStationTokens.mono(size: 8.5, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3.5)
                            .background(viewModel.activeRightTab == .activityLog ? VoiceStationTokens.gold : Color.clear)
                            .foregroundColor(viewModel.activeRightTab == .activityLog ? VoiceStationTokens.navy : VoiceStationTokens.gold.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .retroExtrusion(
                                radius: 5,
                                offset: viewModel.activeRightTab == .activityLog ? 2 : 0,
                                color: viewModel.activeRightTab == .activityLog
                                    ? Color.black.opacity(0.45) : .clear
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: { viewModel.activeRightTab = .historyTray }) {
                        Text("HISTORY \(viewModel.recentDictations.count)")
                            .font(VoiceStationTokens.mono(size: 8.5, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3.5)
                            .background(viewModel.activeRightTab == .historyTray ? VoiceStationTokens.gold : Color.clear)
                            .foregroundColor(viewModel.activeRightTab == .historyTray ? VoiceStationTokens.navy : VoiceStationTokens.gold.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: { viewModel.activeRightTab = .snippets }) {
                        Text("SNIPPETS \(viewModel.snippets.count)")
                            .font(VoiceStationTokens.mono(size: 8.5, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3.5)
                            .background(viewModel.activeRightTab == .snippets ? VoiceStationTokens.gold : Color.clear)
                            .foregroundColor(viewModel.activeRightTab == .snippets ? VoiceStationTokens.navy : VoiceStationTokens.gold.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                } else {
                    Text(activeTabLabel)
                        .font(VoiceStationTokens.mono(size: 8.5, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3.5)
                        .background(VoiceStationTokens.gold)
                        .foregroundColor(VoiceStationTokens.navy)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }

                Spacer(minLength: 4)

                if viewModel.activeRightTab == .historyTray && !viewModel.recentDictations.isEmpty {
                    Button(action: { viewModel.onClearHistory?() }) {
                        Text("CLEAR")
                            .font(VoiceStationTokens.mono(size: 8, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(VoiceStationTokens.danger.opacity(0.85))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("ANDOR CONSOLE")
                        .font(VoiceStationTokens.mono(size: 8.5, weight: .bold))
                        .foregroundColor(VoiceStationTokens.gold.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            Divider().background(VoiceStationTokens.gold.opacity(0.4))
            }

            if viewModel.activeRightTab == .activityLog {
                // Telemetry Diagnostics Header Bar
                TelemetryHeaderView(viewModel: viewModel)

                // Tactical Category Filter Chips
                TacticalFilterChipsView(selectedFilter: $viewModel.selectedFilter, logs: viewModel.activityLogs)

                // CRT Phosphor Terminal Screen
                ZStack {
                    VoiceStationTokens.consoleBg

                    // Scanlines Overlay (responsive geometry)
                    CRTScanlinesOverlay()

                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(filteredLogs) { log in
                                    LogEntryRowView(log: log)
                                        .id(log.id)
                                }
                                ConsoleCursorView(paused: !viewModel.isWindowVisible)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .onChange(of: viewModel.activityLogs.count) { _ in
                            if let last = filteredLogs.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(VoiceStationTokens.gold.opacity(0.4), lineWidth: 1.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.activeRightTab == .historyTray {
                DictationHistoryTabView(viewModel: viewModel)
            } else {
                // Snippets Screen
                VoiceSnippetsTabView(viewModel: viewModel)
            }

            // Bottom Console Status Line
            if chrome {
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isRecording ? VoiceStationTokens.rec : VoiceStationTokens.ok)
                    .frame(width: 6, height: 6)
                Text(viewModel.statusDetail.isEmpty
                     ? viewModel.statusTitle : viewModel.statusDetail)
                    .font(VoiceStationTokens.mono(size: 9.5, weight: .bold))
                    .foregroundColor(VoiceStationTokens.gold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                Text(viewModel.selectedCleaner.isCloud ? "Cloud (Gemini)" : "100% Local (Whisper)")
                    .font(VoiceStationTokens.mono(size: 8.5, weight: .bold))
                    .foregroundColor(VoiceStationTokens.appBg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            }
        }
        .padding(chrome ? 14 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(chrome ? VoiceStationTokens.consoleBg : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: chrome ? 14 : 0, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(chrome ? VoiceStationTokens.navy : Color.clear, lineWidth: 3)
        )
        .retroExtrusion(radius: 14, offset: chrome ? 5 : 0, color: chrome ? VoiceStationTokens.navy : .clear)
    }

    // MARK: - Footer Bar (Strict Design System Contract §Footer)
    private var footerBar: some View {
        ZStack {
            VoiceStationTokens.navy

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("sanblue")
                    .font(VoiceStationTokens.mono(size: 10, weight: .bold))
                    .foregroundColor(VoiceStationTokens.gold)

                Text("dot")
                    .font(VoiceStationTokens.mono(size: 7, weight: .heavy))
                    .foregroundColor(VoiceStationTokens.dotBlue)
                    .baselineOffset(5)

                Text(" — retro dev-station")
                    .font(VoiceStationTokens.mono(size: 10, weight: .bold))
                    .foregroundColor(VoiceStationTokens.footerMuted)
            }
        }
        .frame(height: 40)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(VoiceStationTokens.gold)
                .frame(height: 2)
        }
    }

    // MARK: - Helper Views & Functions
    private var statusBadgeView: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(viewModel.isRecording ? VoiceStationTokens.rec : VoiceStationTokens.ok)
                .frame(width: 7, height: 7)
                .shadow(color: viewModel.isRecording ? VoiceStationTokens.rec : VoiceStationTokens.ok, radius: 3)
            Text(viewModel.isRecording ? "ON AIR" : "READY")
                .font(VoiceStationTokens.mono(size: 9, weight: .heavy))
                .foregroundColor(VoiceStationTokens.navy)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(viewModel.isRecording ? VoiceStationTokens.controlBg.opacity(0.4) : VoiceStationTokens.appBg.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(VoiceStationTokens.navy, lineWidth: 1))
    }

    private func cleanerButtonLabel(for cleaner: CleanerMode) -> String {
        switch cleaner {
        case .literal: return "Literal (No AI)"
        case .ollama: return "Ollama (Local)"
        case .gemini: return "Gemini (Cloud)"
        }
    }

    private var filteredLogs: [ActivityLogItem] {
        switch viewModel.selectedFilter {
        case .all: return viewModel.activityLogs
        case .audio: return viewModel.activityLogs.filter { $0.category == .stt }
        case .ai: return viewModel.activityLogs.filter { $0.category == .gemini || $0.category == .ollama }
        case .actions: return viewModel.activityLogs.filter { $0.category == .action }
        case .snippets: return viewModel.activityLogs.filter { $0.category == .snippet }
        case .system: return viewModel.activityLogs.filter { $0.category == .system || $0.category == .paste }
        case .errors:
            // The chip vanishes when the last warning ages out of the log. Falling back
            // to everything keeps the console from going blank with no chip to press.
            let warnings = viewModel.activityLogs.filter { $0.category == .warn }
            return warnings.isEmpty ? viewModel.activityLogs : warnings
        }
    }
}

// MARK: - Hold to Record Button Style
private struct HoldToRecordButtonStyle: ButtonStyle {
    let onPress: () -> Void
    let onRelease: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed {
                    onPress()
                } else {
                    onRelease()
                }
            }
    }
}

// MARK: - Voice Snippets Tab View
/// The colours one console surface is drawn with.
///
/// The dark terminal and the paper panel differ only by these six values, so a section
/// can carry its own scheme without a second copy of the view underneath it. `terminal`
/// reproduces what the console has always used; only `paper` is new.
struct ConsolePalette {
    let well: Color
    let sunkenForm: Color
    let sunkenRow: Color
    let label: Color
    let ink: Color
    let inkDim: Color
    let rule: Color
    let fieldStroke: Color
    let chipBg: Color
    let chipInk: Color

    static let terminal = ConsolePalette(
        well: VoiceStationTokens.consoleBg,
        sunkenForm: Color.black.opacity(0.3),
        sunkenRow: Color.black.opacity(0.25),
        label: VoiceStationTokens.gold,
        ink: VoiceStationTokens.inputCream,
        inkDim: VoiceStationTokens.gold.opacity(0.6),
        rule: VoiceStationTokens.gold.opacity(0.35),
        fieldStroke: .clear,
        chipBg: VoiceStationTokens.dotBlue.opacity(0.3),
        chipInk: VoiceStationTokens.dotBlue
    )

    static let paper = ConsolePalette(
        well: VoiceStationTokens.panelBg,
        sunkenForm: VoiceStationTokens.inputCream,
        sunkenRow: VoiceStationTokens.inputCream,
        label: VoiceStationTokens.navy,
        ink: VoiceStationTokens.navy,
        inkDim: VoiceStationTokens.textMuted,
        // The terminal's own olive, so the paper panel is bound to the title strip
        // above it and to the console the rest of the app is drawn with.
        rule: VoiceStationTokens.consoleBg.opacity(0.45),
        fieldStroke: VoiceStationTokens.consoleBg.opacity(0.6),
        chipBg: VoiceStationTokens.dotBlue,
        chipInk: VoiceStationTokens.navy
    )
}

/// A section drawn as a screen set into the console's chassis.
///
/// This is the chrome the owner's own site uses, without its outer frame — the window is
/// already the frame, and a frame inside a frame inside a frame spends the height the
/// station needs. The title strip replaces the page heading rather than sitting under
/// it, so a section is named once.
struct PaperChassis<Trailing: View, Content: View>: View {
    @ObservedObject var viewModel: VoiceStationViewModel
    let system: String
    let subtitle: String
    /// The screen inside the chassis. Paper for the sections you operate; the console's
    /// own ground for the log, whose category badges were coloured for a dark field.
    var ground: Color = VoiceStationTokens.panelBg
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(system)
                    .font(VoiceStationTokens.pixel(9))
                    .foregroundColor(VoiceStationTokens.gold)
                Text("— \(subtitle)")
                    .font(VoiceStationTokens.pixel(9))
                    .foregroundColor(VoiceStationTokens.gold.opacity(0.5))
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VoiceStationTokens.consoleBg)

            // The strip continues down both sides and across the foot as a band of the
            // terminal's own colour, and the paper begins inside it.
            content()
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 18)

            // The foot carries the same status line the console does, in the same
            // colours: the band is the console's own ground, so nothing is re-tinted.
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isRecording ? VoiceStationTokens.rec : VoiceStationTokens.ok)
                    .frame(width: 6, height: 6)
                // The detail, not the title. A failure sets the title to a constant and
                // puts the message in the detail, so a foot that shows only the title
                // reports that something is wrong and never what. This is the same
                // expression the console's own foot uses; the two now match.
                Text(viewModel.statusDetail.isEmpty
                     ? viewModel.statusTitle : viewModel.statusDetail)
                    .font(VoiceStationTokens.mono(size: 9.5, weight: .bold))
                    .foregroundColor(VoiceStationTokens.gold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                Text(viewModel.selectedCleaner.isCloud
                     ? "Cloud (Gemini)" : "100% Local (Whisper)")
                    .font(VoiceStationTokens.mono(size: 8.5, weight: .bold))
                    .foregroundColor(VoiceStationTokens.appBg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, 11)
        }
        .background(VoiceStationTokens.consoleBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(VoiceStationTokens.navy, lineWidth: 3)
        )
        .retroExtrusion(radius: 14, offset: 5)
    }
}

/// How many the section holds, on the title strip.
struct ChassisCount: View {
    let value: Int
    /// What the number counts. Drawn it is obvious from the chassis title beside it;
    /// read aloud the badge arrives alone, and a bare digit counts nothing.
    let noun: String

    var body: some View {
        Text("\(value)")
            .accessibilityLabel("\(value) \(noun)")
            .font(VoiceStationTokens.mono(size: 9.5, weight: .bold))
            .foregroundColor(VoiceStationTokens.navy)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(VoiceStationTokens.gold)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct DictationHistoryTabView: View {
    @ObservedObject var viewModel: VoiceStationViewModel
    var palette: ConsolePalette = .terminal

    var body: some View {
        if viewModel.recentDictations.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "tray")
                    .font(.system(size: 24))
                    .foregroundColor(palette.inkDim)
                Text("No recent dictations yet.")
                    .font(VoiceStationTokens.mono(size: 9.5, weight: .bold))
                    .foregroundColor(palette.label)
                Text("Dictated text and translations appear here for 1-click rescue.")
                    .font(VoiceStationTokens.mono(size: 8.5))
                    .foregroundColor(palette.inkDim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.well)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(palette.rule, lineWidth: 1.5))
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.recentDictations) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text("[\(record.timeString)]")
                                    .font(VoiceStationTokens.mono(size: 8.5, weight: .bold))
                                    .foregroundColor(palette.label)

                                Text(record.mode.uppercased())
                                    .font(VoiceStationTokens.mono(size: 7.5, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(VoiceStationTokens.dotBlue.opacity(0.3))
                                    .foregroundColor(VoiceStationTokens.dotBlue)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))

                                Text(record.model ?? record.cleaner)
                                    .font(VoiceStationTokens.mono(size: 7.5))
                                    .foregroundColor(palette.inkDim)

                                Spacer()

                                Text(String(format: "%.1fs", record.latencySeconds))
                                    .font(VoiceStationTokens.mono(size: 7.5))
                                    .foregroundColor(palette.inkDim)
                            }

                            // A delivered transcript looked exactly like a successful
                            // cleanup: same badges, same engine name, and nothing saying
                            // the engine's text never arrived. framework.md asks for the
                            // opposite — which side refused, because a guard rejection
                            // and a provider failure call for opposite responses.
                            if record.usedFallback {
                                HStack(spacing: 5) {
                                    Text("FALLBACK")
                                        .font(VoiceStationTokens.mono(size: 7.5, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(VoiceStationTokens.rec.opacity(0.3))
                                        .foregroundColor(VoiceStationTokens.rec)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                    Text(record.fallbackReason
                                         ?? "the cleanup did not arrive")
                                        .font(VoiceStationTokens.mono(size: 7.5))
                                        .foregroundColor(palette.inkDim)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Spacer(minLength: 0)
                                }
                                .accessibilityElement(children: .combine)
                            }

                            Text(record.finalText)
                                .font(VoiceStationTokens.mono(size: 12, weight: .regular))
                                .foregroundColor(palette.ink)
                                .textSelection(.enabled)

                            DisclosureGroup("VIEW ORIGINAL & PERSONALIZED TEXT") {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("ORIGINAL · speech recognition").fontWeight(.bold)
                                    Text(record.rawText)
                                    Text("PERSONALIZED · confirmed corrections").fontWeight(.bold)
                                    Text(record.personalizedText)
                                }
                                .font(VoiceStationTokens.mono(size: 12))
                                .foregroundColor(palette.ink)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                            }
                            .font(VoiceStationTokens.mono(size: 10, weight: .bold))
                            .foregroundColor(VoiceStationTokens.gold)

                            HStack(spacing: 6) {
                                Button(action: {
                                    viewModel.onCopyHistoryRecord?(record)
                                    viewModel.addLog("copied from history: \"\(record.menuPreview())\"", isHighlight: true)
                                }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 8))
                                        Text("COPY")
                                            .font(VoiceStationTokens.mono(size: 8, weight: .bold))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(VoiceStationTokens.gold)
                                    .foregroundColor(VoiceStationTokens.navy)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)

                                if record.rawText != record.finalText && !record.rawText.isEmpty {
                                    Button(action: {
                                        viewModel.onCopyRawRecord?(record)
                                        viewModel.addLog("copied raw transcript from history", isHighlight: true)
                                    }) {
                                        HStack(spacing: 3) {
                                            Image(systemName: "waveform")
                                                .font(.system(size: 8))
                                            Text("RAW")
                                                .font(VoiceStationTokens.mono(size: 8, weight: .bold))
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(VoiceStationTokens.panelHeader)
                                        .foregroundColor(VoiceStationTokens.navy)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                    .buttonStyle(.plain)
                                }

                                Button(action: {
                                    viewModel.onRepasteHistoryRecord?(record)
                                }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "bolt.fill")
                                            .font(.system(size: 8))
                                        Text("RE-PASTE")
                                            .font(VoiceStationTokens.mono(size: 8, weight: .bold))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(VoiceStationTokens.dotBlue)
                                    .foregroundColor(VoiceStationTokens.navy)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                        .background(palette.sunkenRow)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.rule, lineWidth: 1))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .background(palette.well)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(palette.rule, lineWidth: 1.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct VoiceSnippetsTabView: View {
    @ObservedObject var viewModel: VoiceStationViewModel
    var palette: ConsolePalette = .terminal
    @State private var newTrigger: String = ""
    @State private var newExpansion: String = ""
    @State private var newDescription: String = ""

    var body: some View {
        VStack(spacing: 8) {
            // New Snippet Form Card
            VStack(alignment: .leading, spacing: 5) {
                Text("ADD VOICE SNIPPET / MACRO")
                    .font(VoiceStationTokens.mono(size: 8, weight: .bold))
                    .foregroundColor(palette.label)

                HStack(spacing: 5) {
                    TextField("Spoken trigger (e.g. mi linkedin)", text: $newTrigger)
                        .textFieldStyle(.plain)
                        .font(VoiceStationTokens.mono(size: 8.5))
                        .padding(5)
                        .background(VoiceStationTokens.inputCream)
                        .foregroundColor(VoiceStationTokens.navy)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(palette.fieldStroke, lineWidth: 1)
                        )

                    TextField("Description (optional)", text: $newDescription)
                        .textFieldStyle(.plain)
                        .font(VoiceStationTokens.mono(size: 8.5))
                        .padding(5)
                        .background(VoiceStationTokens.inputCream)
                        .foregroundColor(VoiceStationTokens.navy)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(palette.fieldStroke, lineWidth: 1)
                        )
                }

                HStack(spacing: 5) {
                    TextField("Replacement text or template", text: $newExpansion)
                        .textFieldStyle(.plain)
                        .font(VoiceStationTokens.mono(size: 8.5))
                        .padding(5)
                        .background(VoiceStationTokens.inputCream)
                        .foregroundColor(VoiceStationTokens.navy)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(palette.fieldStroke, lineWidth: 1)
                        )

                    let isAddDisabled = newTrigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newExpansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                    Button(action: {
                        let trig = newTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
                        let exp = newExpansion.trimmingCharacters(in: .whitespacesAndNewlines)
                        let desc = newDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trig.isEmpty, !exp.isEmpty else { return }
                        viewModel.onAddSnippet?(trig, exp, desc.isEmpty ? nil : desc)
                        newTrigger = ""
                        newExpansion = ""
                        newDescription = ""
                    }) {
                        Text("+ ADD")
                            .font(VoiceStationTokens.mono(size: 8, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(isAddDisabled ? VoiceStationTokens.panelHeader : VoiceStationTokens.gold)
                            .foregroundColor(VoiceStationTokens.navy)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                    .disabled(isAddDisabled)
                }
            }
            .padding(6)
            .background(palette.sunkenForm)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.rule, lineWidth: 1))

            // Snippets List
            if viewModel.snippets.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "text.quote")
                        .font(.system(size: 20))
                        .foregroundColor(palette.inkDim)
                    Text("No voice snippets registered yet.")
                        .font(VoiceStationTokens.mono(size: 8.5, weight: .bold))
                        .foregroundColor(palette.label)
                    Text("Say your trigger phrase to expand URLs, signatures, or templates instantly.")
                        .font(VoiceStationTokens.mono(size: 7.5))
                        .foregroundColor(palette.inkDim)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.well)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(palette.rule, lineWidth: 1.5))
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(viewModel.snippets) { snippet in
                            HStack(alignment: .top, spacing: 6) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 5) {
                                        Text("[\(snippet.trigger)]")
                                            .font(VoiceStationTokens.mono(size: 8.5, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(VoiceStationTokens.gold)
                                            .foregroundColor(VoiceStationTokens.navy)
                                            .clipShape(RoundedRectangle(cornerRadius: 3))

                                        if let desc = snippet.description, !desc.isEmpty {
                                            Text(desc)
                                                .font(VoiceStationTokens.mono(size: 7.5))
                                                .foregroundColor(palette.inkDim)
                                        }
                                    }

                                    Text(snippet.expansion)
                                        .font(VoiceStationTokens.mono(size: 8.5))
                                        .foregroundColor(palette.ink)
                                        .lineLimit(2)
                                }

                                Spacer()

                                Button(action: {
                                    viewModel.onDeleteSnippet?(snippet.id)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 8))
                                        .padding(4)
                                        .background(VoiceStationTokens.danger.opacity(0.8))
                                        .foregroundColor(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(6)
                            .background(palette.sunkenRow)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.rule, lineWidth: 1))
                        }
                    }
                    .padding(6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.well)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(palette.rule, lineWidth: 1.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Mini VU Meter View
private struct MiniVUMeterView: View {
    let isRecording: Bool
    let audioLevel: Double

    private let barCount = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("AUDIO INPUT VU")
                    .font(VoiceStationTokens.mono(size: 8, weight: .bold))
                    .foregroundColor(VoiceStationTokens.navy)

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(isRecording ? VoiceStationTokens.danger : VoiceStationTokens.textMuted.opacity(0.4))
                        .frame(width: 5, height: 5)
                    Text(isRecording ? "LIVE SIGNAL" : "STANDBY")
                        .font(VoiceStationTokens.mono(size: 7, weight: .bold))
                        .foregroundColor(isRecording ? VoiceStationTokens.danger : VoiceStationTokens.textMuted)
                }
            }

            HStack(spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { index in
                    let activeThreshold = Double(index + 1) / Double(barCount)
                    let isActive = isRecording && (index == 0 ? audioLevel > 0.02 : audioLevel >= activeThreshold)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isActive ? barColor(for: index) : Color.black.opacity(0.12))
                        .frame(height: 8)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(4)
            .background(VoiceStationTokens.inputCream)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(VoiceStationTokens.navy, lineWidth: 1))
        }
    }

    private func barColor(for index: Int) -> Color {
        if index < 7 {
            return VoiceStationTokens.dotBlue
        } else if index < 10 {
            return VoiceStationTokens.gold
        } else {
            return VoiceStationTokens.onAir
        }
    }
}

// MARK: - App Target Monitor View
private struct AppTargetMonitorView: View {
    let targetAppName: String
    let targetAppProfile: String

    var body: some View {
        let isClipboardOnly = targetAppProfile.hasPrefix("Clipboard")
        let isTerminal = targetAppProfile.hasPrefix("Terminal")

        return HStack(spacing: 12) {
            // A colour tile stands in for the destination application, as in the
            // approved preview: the strip is read at a glance, not parsed.
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    isClipboardOnly
                        ? VoiceStationTokens.gold
                        : (isTerminal ? VoiceStationTokens.working : VoiceStationTokens.dotBlue)
                )
                .frame(width: 30, height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(VoiceStationTokens.navy, lineWidth: 2)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(targetAppName)
                    .font(VoiceStationTokens.mono(size: 12, weight: .bold))
                    .foregroundColor(VoiceStationTokens.navy)
                    .lineLimit(1)
                Text(targetAppProfile)
                    .font(VoiceStationTokens.mono(size: 9))
                    .foregroundColor(VoiceStationTokens.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(isClipboardOnly ? "CLIPBOARD" : (isTerminal ? "TERMINAL" : "AUTO-PASTE"))
                .font(VoiceStationTokens.mono(size: 9, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isClipboardOnly ? VoiceStationTokens.gold : (isTerminal ? VoiceStationTokens.working : VoiceStationTokens.dotBlue))
                .foregroundColor(VoiceStationTokens.navy)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(VoiceStationTokens.navy, lineWidth: 2))
                .retroExtrusion(radius: 999, offset: 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(VoiceStationTokens.inputCream)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(VoiceStationTokens.navy, lineWidth: 2)
        )
        .retroExtrusion(radius: 10, offset: 3)
    }
}

// MARK: - Telemetry Header View
private struct TelemetryHeaderView: View {
    @ObservedObject var viewModel: VoiceStationViewModel
    @State private var isPulsing: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            gaugeRow
            if viewModel.selectedCleaner.isCloud {
                cloudRow
                cloudMeasurementCaption
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(VoiceStationTokens.gold.opacity(0.2), lineWidth: 1))
        // The beacon was the one continuous animation here that kept running while the
        // window was hidden. `repeatForever` does not stop on its own, so it is started
        // and stopped from the same visibility flag the four TimelineViews already read.
        .onAppear { setPulse(viewModel.isWindowVisible) }
        .onChange(of: viewModel.isWindowVisible) { visible in
            setPulse(visible)
        }
    }

    private func setPulse(_ running: Bool) {
        guard running else {
            withAnimation(.linear(duration: 0)) { isPulsing = false }
            return
        }
        withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }

    /// The two facts the model chips cannot carry on their own: when their figures were
    /// measured, and the order the engine will actually walk when the chosen model is
    /// busy. The date is there because nothing re-measures, so the numbers above are a
    /// photograph and should not read as today's ranking.
    private var cloudMeasurementCaption: some View {
        HStack(spacing: 4) {
            Text("measured \(GeminiModel.measurementDate)")
            Text("·")
            Text("busy → \(fallbackOrderAfterSelection) → local transcript")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .font(VoiceStationTokens.mono(size: 7, weight: .regular))
        .foregroundColor(VoiceStationTokens.gold.opacity(0.5))
    }

    /// Name the order the engine will actually walk, not a generic promise.
    private var fallbackOrderAfterSelection: String {
        GeminiModel.fallbackOrder
            .filter { $0 != viewModel.selectedGeminiModel }
            .map(\.shortName)
            .joined(separator: " → ")
    }

    private var gaugeRow: some View {
        HStack(spacing: 8) {
            // Pulsing Live Beacon
            HStack(spacing: 4) {
                Circle()
                    .fill(isPulsing ? VoiceStationTokens.danger : VoiceStationTokens.danger.opacity(0.4))
                    .frame(width: 6, height: 6)
                    .shadow(color: VoiceStationTokens.danger, radius: isPulsing ? 3 : 0)

                Text("TELEMETRY")
                    .font(VoiceStationTokens.mono(size: 8.5, weight: .bold))
                    .foregroundColor(VoiceStationTokens.gold)
                    .lineLimit(1)
            }

            // Gauges. Each one shows only what the run measured; a stage that
            // reported nothing shows a dash rather than a plausible number.
            HStack(spacing: 6) {
                gauge(
                    label: "SPEECH",
                    value: viewModel.lastSTTLatency.map { String(format: "%.2fs", $0) },
                    fraction: viewModel.lastSTTLatency.map { min($0 / 4.0, 1.0) },
                    tint: VoiceStationTokens.dotBlue
                )
                gauge(
                    label: "CLEANUP",
                    value: viewModel.lastLLMLatency.map { String(format: "%.2fs", $0) },
                    fraction: viewModel.lastLLMLatency.map { min($0 / 10.0, 1.0) },
                    tint: VoiceStationTokens.gold
                )
                gauge(
                    label: "RATE",
                    value: viewModel.lastWPM.map { "\($0)" },
                    fraction: viewModel.lastWPM.map { min(Double($0) / 220.0, 1.0) },
                    tint: VoiceStationTokens.appBg
                )
            }
        }
    }


    /// The cloud row: which model answers, in measured order, and whether the key is
    /// stored. It lives here rather than on the mint canvas because it explains the
    /// readings above it, and because a dark ground is where these chips read.
    private var cloudRow: some View {
        HStack(spacing: 7) {
            Text("MODEL")
                .font(VoiceStationTokens.mono(size: 7, weight: .bold))
                .foregroundColor(VoiceStationTokens.gold.opacity(0.6))

            ForEach(GeminiModel.allCases, id: \.self) { model in
                consoleChip(
                    title: model.shortName,
                    detail: model.measuredNote,
                    isOn: viewModel.selectedGeminiModel == model
                ) {
                    guard viewModel.isSelectionEnabled else {
                        viewModel.reportRefusal(
                            "this run keeps Gemini \(viewModel.selectedGeminiModel.shortName) · the model changes once it is delivered")
                        return
                    }
                    viewModel.selectedGeminiModel = model
                    viewModel.onGeminiModelSelect?(model)
                    viewModel.addLog("cloud model: \(model.rawValue)")
                }
            }

            Spacer(minLength: 6)

            Text("KEY")
                .font(VoiceStationTokens.mono(size: 7, weight: .bold))
                .foregroundColor(VoiceStationTokens.gold.opacity(0.6))

            consoleChip(
                title: viewModel.hasKey ? "Stored" : "Set key…",
                detail: viewModel.hasKey ? "keychain" : "required",
                isOn: viewModel.hasKey
            ) {
                viewModel.onSetAPIKey?(viewModel.selectedCleaner)
            }

            if viewModel.hasKey {
                consoleChip(title: "Remove", detail: nil, isOn: false) {
                    viewModel.onForgetAPIKey?(viewModel.selectedCleaner)
                }
            }
        }
    }

    /// A chip for the dark console: gold when it is the one in use, outlined when not.
    private func consoleChip(
        title: String,
        detail: String?,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(isOn ? VoiceStationTokens.ok : VoiceStationTokens.gold.opacity(0.25))
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(VoiceStationTokens.mono(size: 9, weight: .bold))
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(VoiceStationTokens.mono(size: 7))
                            .opacity(0.7)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(isOn ? VoiceStationTokens.gold : Color.black.opacity(0.35))
            .foregroundColor(isOn ? VoiceStationTokens.navy : VoiceStationTokens.gold.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(VoiceStationTokens.gold.opacity(isOn ? 0 : 0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .voiceFlowNoFocusRing()
    }

    /// One measured reading with its level bar. `nil` prints an em dash, never a guess.
    private func gauge(
        label: String,
        value: String?,
        fraction: Double?,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(VoiceStationTokens.mono(size: 7, weight: .bold))
                .foregroundColor(VoiceStationTokens.gold.opacity(0.6))
                .lineLimit(1)

            Text(value ?? "—")
                .font(VoiceStationTokens.mono(size: 13, weight: .bold))
                .foregroundColor(value == nil ? VoiceStationTokens.gold.opacity(0.35) : VoiceStationTokens.inputCream)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            GeometryReader { bar in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(tint)
                        .frame(width: bar.size.width * CGFloat(fraction ?? 0))
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(VoiceStationTokens.gold.opacity(0.30), lineWidth: 1.5)
        )
    }
}

// MARK: - Tactical Filter Chips View
private struct TacticalFilterChipsView: View {
    @Binding var selectedFilter: ConsoleFilterMode
    let logs: [ActivityLogItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                // ERRORS appears only when there is something in it. Its arrival is
                // the signal, and the row has no width for a seventh chip that would
                // read zero almost always.
                ForEach(visibleFilters, id: \.self) { filter in
                    let count = countFor(filter)
                    Button(action: { selectedFilter = filter }) {
                        Text("\(filter.rawValue)\(count > 0 ? " (\(count))" : "")")
                            .font(VoiceStationTokens.mono(size: 8, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(selectedFilter == filter ? VoiceStationTokens.dotBlue.opacity(0.3) : Color.black.opacity(0.2))
                            .foregroundColor(selectedFilter == filter ? VoiceStationTokens.dotBlue : VoiceStationTokens.gold.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(selectedFilter == filter ? VoiceStationTokens.dotBlue : VoiceStationTokens.gold.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Every filter, plus ERRORS only while it holds something.
    private var visibleFilters: [ConsoleFilterMode] {
        ConsoleFilterMode.allCases.filter { $0 != .errors || countFor(.errors) > 0 }
    }

    private func countFor(_ filter: ConsoleFilterMode) -> Int {
        switch filter {
        case .all: return logs.count
        case .audio: return logs.filter { $0.category == .stt }.count
        case .ai: return logs.filter { $0.category == .gemini || $0.category == .ollama }.count
        case .actions: return logs.filter { $0.category == .action }.count
        case .snippets: return logs.filter { $0.category == .snippet }.count
        case .system: return logs.filter { $0.category == .system || $0.category == .paste }.count
        case .errors: return logs.filter { $0.category == .warn }.count
        }
    }
}

// MARK: - CRT Scanlines Overlay
private struct CRTScanlinesOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let lineSpacing: CGFloat = 3.0
            let count = max(0, Int(geo.size.height / lineSpacing))
            VStack(spacing: 2) {
                ForEach(0..<count, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.08))
                        .frame(height: 1)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - Log Entry Row View
private struct LogEntryRowView: View {
    let log: ActivityLogItem
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Timestamp
            Text("[\(log.timestamp)]")
                .font(VoiceStationTokens.mono(size: 8.5, weight: .regular))
                .foregroundColor(VoiceStationTokens.gold.opacity(0.5))
                .frame(width: 54, alignment: .leading)

            // Category Badge
            Text(log.category.rawValue)
                .font(VoiceStationTokens.mono(size: 7.5, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(log.category.badgeColor)
                .foregroundColor(VoiceStationTokens.navy)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.5), lineWidth: 1))
                .frame(width: 64, alignment: .center)

            // Message & Latency Tags
            VStack(alignment: .leading, spacing: 2) {
                Text(log.message)
                    .font(VoiceStationTokens.mono(size: 8.5, weight: log.isHighlight ? .bold : .regular))
                    .foregroundColor(log.isHighlight ? VoiceStationTokens.inputCream : VoiceStationTokens.gold.opacity(0.95))
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)

                if log.latency != nil || !log.tags.isEmpty {
                    HStack(spacing: 4) {
                        if let latency = log.latency {
                            Text("⚡ \(String(format: "%.2f", latency))s")
                                .font(VoiceStationTokens.mono(size: 7, weight: .bold))
                                .foregroundColor(VoiceStationTokens.dotBlue)
                        }
                        ForEach(log.tags, id: \.self) { tag in
                            Text(tag)
                                .font(VoiceStationTokens.mono(size: 7))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(VoiceStationTokens.appBg.opacity(0.2))
                                .foregroundColor(VoiceStationTokens.appBg)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Hover Action: Copy Log Entry
            if isHovered {
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(log.message, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 8))
                        .padding(3)
                        .background(VoiceStationTokens.gold)
                        .foregroundColor(VoiceStationTokens.navy)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isHovered ? Color.white.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
