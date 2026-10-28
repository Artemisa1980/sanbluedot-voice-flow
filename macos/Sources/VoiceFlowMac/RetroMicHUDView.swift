import SwiftUI
import VoiceFlowMacCore

public enum HUDMode: Equatable {
    case idle
    case recording
    case processing
    case completed(didAutoPaste: Bool, usedFallback: Bool, unrecognizedCommand: Bool = false)
    case actionExecuted(description: String)
    case failed(String)
    case modeChanged(ProcessingMode)
    case cancelled

    public var stateKey: String {
        switch self {
        case .idle: return "idle"
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
        case .idle: return "VoiceFlow mascot idle"
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
    @Published public var mode: HUDMode = .idle
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

    /// Whether user clicked the mascot to toggle standing erguido (default = false, seated)
    @Published public var userPrefersStanding: Bool = UserDefaults.standard.bool(forKey: "microduck.userPrefersStanding")

    /// Active visual edition: MD-01 Fusion (Parado A + Sentado 2) or Classic Reserve
    @Published public var edition: MicroduckEdition = {
        if let raw = UserDefaults.standard.string(forKey: "microduck.edition"),
           let saved = MicroduckEdition(rawValue: raw) {
            return saved
        }
        return .md01Fusion
    }()

    /// Timestamp of last user interaction or speech event to track idle sleep
    @Published public var lastActivityTime: TimeInterval = ProcessInfo.processInfo.systemUptime

    /// Manual sleep toggle from companion menu
    @Published public var forceSleeping: Bool = false

    /// Whether voice speech has been detected since key down (level > 0.2).
    /// If false during recording, only the minimal capsule shows.
    @Published public var voiceHeard: Bool = false

    /// Tracks visibility of the floating HUD to pause the 30 FPS animation when ordered out.
    @Published public var isVisible: Bool = false

    /// Screen position of the floating HUD panel to compute mouse tracking angles.
    @Published public var panelOrigin: CGPoint = .zero

    public init() {}

    public func toggleStanding() {
        userPrefersStanding.toggle()
        UserDefaults.standard.set(userPrefersStanding, forKey: "microduck.userPrefersStanding")
        lastActivityTime = ProcessInfo.processInfo.systemUptime
    }

    public func setEdition(_ newEdition: MicroduckEdition) {
        edition = newEdition
        UserDefaults.standard.set(newEdition.rawValue, forKey: "microduck.edition")
        lastActivityTime = ProcessInfo.processInfo.systemUptime
    }

    public func toggleSleep() {
        forceSleeping.toggle()
        if !forceSleeping {
            lastActivityTime = ProcessInfo.processInfo.systemUptime
        }
    }

    public func recordActivity() {
        lastActivityTime = ProcessInfo.processInfo.systemUptime
        forceSleeping = false
    }
}

// MARK: - Microduck HUD View (I-82)
/// Articulated mascot and thought bubble capsule beside the duck.
public struct RetroMicHUDView: View {
    @ObservedObject public var viewModel: HUDViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var modeChangeTime: TimeInterval = ProcessInfo.processInfo.systemUptime

    public init(viewModel: HUDViewModel) {
        self.viewModel = viewModel
    }

    private var isRecording: Bool { viewModel.mode == .recording }
    private var isProcessing: Bool { viewModel.mode == .processing }
    private var isIdle: Bool { viewModel.mode == .idle }

    private var shouldShowDuck: Bool {
        switch viewModel.mode {
        case .idle:
            return true
        case .recording:
            return viewModel.voiceHeard
        case .processing, .completed, .actionExecuted, .failed, .cancelled:
            return true
        case .modeChanged:
            return false
        }
    }

    private var shouldShowBubble: Bool {
        switch viewModel.mode {
        case .idle:
            return false
        case .recording, .processing, .completed, .actionExecuted, .failed, .cancelled, .modeChanged:
            return true
        }
    }

    private var bubbleSize: (width: CGFloat, height: CGFloat) {
        switch viewModel.mode {
        case .idle:
            return (0, 0)
        case .recording:
            if !viewModel.voiceHeard {
                return (HUDLayout.capsuleMinSize.width, HUDLayout.capsuleMinSize.height)
            }
            return (HUDLayout.capsuleFullSize.width, HUDLayout.capsuleFullSize.height)
        case .processing, .completed, .actionExecuted:
            return (HUDLayout.capsuleFullSize.width, HUDLayout.capsuleFullSize.height)
        case .failed, .cancelled, .modeChanged:
            return (HUDLayout.capsuleShortSize.width, HUDLayout.capsuleShortSize.height)
        }
    }

    private func currentPose(time: TimeInterval, uptime: TimeInterval) -> DuckPose {
        if reduceMotion {
            switch viewModel.mode {
            case .idle:
                return viewModel.userPrefersStanding ? .standFront : .seatedDefault
            case .recording:
                var base: DuckPose = .recordingSitting
                let lvl = viewModel.audioLevel
                base.jaw = lvl > 0.20 ? Double(min(1.0, lvl * 1.25)) : 0.0
                return base
            case .processing:
                return .recordingSitting
            case .completed, .actionExecuted, .failed, .cancelled, .modeChanged:
                return .standFront
            }
        }

        let s = MicroduckKinematics.canonicalSmoothness
        let breathingPhase = time * 2.8 * s
        let wigglePhase = time * 3.8 * s

        // Mouse cursor tracking: direct to head yaw and pitch per owner direction
        let mouseLocation = NSEvent.mouseLocation
        let duckScreenX = viewModel.panelOrigin.x + 30.0
        let duckScreenY = viewModel.panelOrigin.y + 48.0
        let dx = mouseLocation.x - duckScreenX
        let dy = mouseLocation.y - duckScreenY
        let mouseDistance = hypot(dx, dy)
        let isMouseHovering = mouseDistance < 85.0

        let turnNorm = max(90.0, mouseDistance)
        let decay = max(0.0, min(1.0, 1.0 - (mouseDistance - 100.0) / 250.0))
        let mouseTurn = max(-14.0, min(14.0, (dx / turnNorm) * 20.0 * decay))
        let mouseTilt = max(-10.0, min(10.0, -(dy / turnNorm) * 14.0 * decay))

        switch viewModel.mode {
        case .idle:
            let inactivity = uptime - viewModel.lastActivityTime
            let shouldSleep = (inactivity > 110.0 || viewModel.forceSleeping) && !isMouseHovering
            if shouldSleep {
                // Sleep / Nap mode after inactivity or manual nap toggle (preserves standing or seated posture)
                var base: DuckPose = viewModel.userPrefersStanding ? .standFront : .seatedSleep
                let slowBreath = sin(time * 1.4 * s) * 0.8
                base.isSitting = !viewModel.userPrefersStanding
                base.body += slowBreath * 0.45
                base.head = (viewModel.userPrefersStanding ? 5.5 : 6.0) + slowBreath * 0.65
                base.footWiggle = time * 0.8 * s
                base.isSleeping = true
                base.drowsy = 1.0
                return base
            }

            if viewModel.userPrefersStanding {
                var base: DuckPose = .standFront
                let totalCycle: Double = 110.0 // 6 modalities * ~18s each
                let standCycle = (uptime * s).truncatingRemainder(dividingBy: totalCycle)

                if standCycle < 18.0 {
                    // 1. Curious Idle & Blink (0.0 to 18.0s)
                    let localT = standCycle
                    let breathe = sin(localT * 2.0 * s)
                    base.hipDropY = breathe * 0.9
                    base.kneeSpreadL = breathe * 0.6
                    base.kneeSpreadR = breathe * 0.6
                    base.headRoll = sin(localT * 1.35 * s) * 6.5
                    base.turn = max(-14.0, min(14.0, sin(localT * 0.85 * s) * 7.5 + mouseTurn))
                    base.head = -3.5 + cos(localT * 1.35 * s) * 2.0 + mouseTilt

                    let bMod = localT.truncatingRemainder(dividingBy: 3.5)
                    if ((bMod > 1.8 && bMod < 1.95) || (bMod > 2.1 && bMod < 2.24)) && !isMouseHovering {
                        base.drowsy = 0.9
                    }
                } else if standCycle < 36.0 {
                    // 2. Tippy-Taps de Botita (18.0 to 36.0s)
                    let localT = standCycle - 18.0
                    let sway = sin(localT * 2.4 * s)
                    base.bodyShiftX = sway * 3.8
                    base.bodyRoll = sway * 2.8
                    base.headRoll = -sway * 4.5
                    base.turn = max(-14.0, min(14.0, sway * 5.0 + mouseTurn))
                    base.head = -3.5 + mouseTilt

                    if sway > 0.25 {
                        let tap = abs(sin(localT * 11.0 * s))
                        base.footTiltL = -tap * 16.0
                        base.footLiftL = tap * 2.2
                    } else if sway < -0.25 {
                        let tap = abs(sin(localT * 11.0 * s))
                        base.footTiltR = tap * 16.0
                        base.footLiftR = tap * 2.2
                    }
                } else if standCycle < 54.0 {
                    // 3. Caminata Waddle (36.0 to 54.0s)
                    let localT = standCycle - 36.0
                    let phase = localT * 3.6 * s
                    let sinP = sin(phase)
                    base.bodyShiftX = cos(phase) * 2.5
                    base.bodyRoll = sinP * 3.0
                    base.headRoll = -sinP * 3.5
                    base.head = -3.0 + abs(sinP) * 2.5 + mouseTilt
                    base.turn = mouseTurn
                    base.footLiftL = max(0.0, sinP) * 6.5
                    base.footTiltL = max(0.0, sinP) * 10.0
                    base.kneeSpreadL = max(0.0, sinP) * 2.5
                    base.footLiftR = max(0.0, -sinP) * 6.5
                    base.footTiltR = -max(0.0, -sinP) * 10.0
                    base.kneeSpreadR = max(0.0, -sinP) * 2.5
                } else if standCycle < 72.0 {
                    // 4. Saltito Feliz (54.0 to 72.0s)
                    let localT = standCycle - 54.0
                    let c = (localT * s).truncatingRemainder(dividingBy: 2.5)
                    if c < 0.5 {
                        let p = sin((c / 0.5) * .pi * 0.5)
                        base.hipDropY = p * 5.5
                        base.kneeSpreadL = p * 3.5
                        base.kneeSpreadR = p * 3.5
                        base.head = -1.0 + p * 4.0 + mouseTilt
                    } else if c < 1.35 {
                        let p = (c - 0.5) / 0.85
                        let arc = sin(p * .pi)
                        base.hopY = arc * 15.0
                        base.footLiftL = arc * 15.0
                        base.footLiftR = arc * 15.0
                        base.footTiltL = 12.0 * arc
                        base.footTiltR = -12.0 * arc
                        base.head = -9.0 * arc - 3.0 + mouseTilt
                        base.jaw = arc * 0.55
                    } else if c < 1.85 {
                        let p = sin(((1.85 - c) / 0.5) * .pi * 0.5)
                        base.hipDropY = p * 4.5
                        base.kneeSpreadL = p * 3.0
                        base.kneeSpreadR = p * 3.0
                        base.head = -3.0 + mouseTilt
                    } else {
                        base.head = -3.5 + mouseTilt
                    }
                    base.turn = mouseTurn
                } else if standCycle < 90.0 {
                    // 5. Standing Double Quack (72.0 to 90.0s): Exactly 3 sets of «quack · quack» with 3s pause between sets
                    let localT = standCycle - 72.0
                    let setDur: Double = 1.30 // natural cadence for a pair of quacks (not slow, not rushed)
                    let pauseDur: Double = 3.0 // 3-second quiet pause
                    let period: Double = setDur + pauseDur // 4.30s per set+pause cycle

                    let qSubClock: Double
                    let isInQuackBurst: Bool

                    if localT < setDur {
                        // Set 1: first «quack · quack» (0.0 to 1.30s)
                        qSubClock = localT / setDur
                        isInQuackBurst = true
                    } else if localT < period {
                        // Pause 1: 3-second quiet pause with beak closed (1.30 to 4.30s)
                        qSubClock = 0.0
                        isInQuackBurst = false
                    } else if localT < period + setDur {
                        // Set 2: second «quack · quack» (4.30 to 5.60s)
                        qSubClock = (localT - period) / setDur
                        isInQuackBurst = true
                    } else if localT < period * 2.0 {
                        // Pause 2: 3-second quiet pause with beak closed (5.60 to 8.60s)
                        qSubClock = 0.0
                        isInQuackBurst = false
                    } else if localT < period * 2.0 + setDur {
                        // Set 3: third «quack · quack» (8.60 to 9.90s)
                        qSubClock = (localT - period * 2.0) / setDur
                        isInQuackBurst = true
                    } else {
                        // "Y pasa": finishes quacking and transitions peacefully to drowsy (9.90 to 18.0s)
                        qSubClock = 0.0
                        isInQuackBurst = false
                    }

                    if isInQuackBurst {
                        base.quackClock = qSubClock
                        base.isQuacking = true
                        base.hipDropY = sin(localT * 2.5 * s) * 0.8
                        base.headRoll = -4.0 + sin(localT * 2.0 * s) * 3.0

                        if qSubClock > 0.05 && qSubClock < 0.45 {
                            let qp = sin(((qSubClock - 0.05) / 0.40) * .pi)
                            base.jaw = qp * 0.85
                            base.head = -4.0 - qp * 4.5 + mouseTilt
                            base.neckLean = -qp * 2.0
                        } else if qSubClock > 0.52 && qSubClock < 0.98 {
                            let qp = sin(((qSubClock - 0.52) / 0.46) * .pi)
                            base.jaw = qp * 0.95
                            base.head = -5.0 - qp * 6.0 + mouseTilt
                            base.neckLean = -qp * 3.0
                        } else {
                            base.jaw = 0.0
                            base.head = -3.5 + mouseTilt
                        }
                    } else {
                        base.quackClock = 0.0
                        base.isQuacking = false
                        base.jaw = 0.0
                        base.head = -3.5 + mouseTilt
                        base.neckLean = 0.0
                    }
                    base.turn = mouseTurn
                } else {
                    // 6. Cabeceo de Sueñito / Drowsy (90.0 to 110.0s)
                    let localT = standCycle - 90.0
                    let nod = sin(localT * 1.4 * s)
                    base.hipDropY = 1.5 + sin(localT * 1.4 * s) * 1.0
                    base.bodyRoll = sin(localT * 0.9 * s) * 1.5
                    base.headRoll = 6.5 + sin(localT * 1.1 * s) * 2.0
                    base.head = 5.5 + max(0.0, nod) * 4.5 + mouseTilt * 0.4
                    base.drowsy = min(0.95, 0.35 + (localT / 20.0) * 0.60)
                    base.turn = mouseTurn * 0.5
                }

                if isMouseHovering {
                    // Attentive alert when cursor nears Microduck
                    base.head = -12.0
                    base.drowsy = 0.0
                    base.turn = mouseTurn
                }
                return base
            }

            // Default Seated Companion (Sentado 2 / Classic Reserve at 0.60x canonical smoothness):
            var base: DuckPose = .seatedDefault
            let breath = sin(breathingPhase)
            base.body += breath * 0.5
            base.n = base.n.map { $0 + breath * 0.8 }
            base.footWiggle = wigglePhase
            base.turn = mouseTurn
            base.head = -8.0 + mouseTilt

            // Ambient autonomous accents when mouse isn't hovering right on top
            if !isMouseHovering {
                let ambientCycle = (uptime * s).truncatingRemainder(dividingBy: 42.0)
                if ambientCycle >= 14.0 && ambientCycle < 20.0 {
                    // Seated Curious Look
                    let lookProgress = (ambientCycle - 14.0) / 6.0
                    let turnAngle = sin(lookProgress * .pi * 2.0) * 11.5
                    base.turn = max(-14.0, min(14.0, base.turn + turnAngle))
                    base.head += abs(turnAngle) * 0.18
                    base.eyeOffsetX = sin(lookProgress * .pi * 2.0) * 2.2
                } else if ambientCycle >= 20.0 && ambientCycle < 25.0 {
                    // Seated Drowsy Blink (golden upper eyelid lowers half-way with heavy nod)
                    let drowsyProgress = (ambientCycle - 20.0) / 5.0
                    let drowsyEnvelope = sin(drowsyProgress * .pi)
                    base.drowsy = drowsyEnvelope * 0.68
                    base.head = -4.0 + drowsyEnvelope * 6.0 + mouseTilt * 0.4
                    base.footWiggle = wigglePhase * 0.45
                } else if ambientCycle >= 25.0 && ambientCycle < 42.0 {
                    // Seated Double Quack: Exactly 3 sets of «quack · quack» with 3s pause between sets
                    let localT = ambientCycle - 25.0 // 0.0 to 17.0s
                    let setDur: Double = 1.30 // natural cadence for a pair of quacks (not slow, not rushed)
                    let pauseDur: Double = 3.0 // 3-second quiet pause
                    let period: Double = setDur + pauseDur // 4.30s per set+pause cycle

                    let qSubClock: Double
                    let isInQuackBurst: Bool

                    if localT < setDur {
                        // Set 1: first «quack · quack» (0.0 to 1.30s)
                        qSubClock = localT / setDur
                        isInQuackBurst = true
                    } else if localT < period {
                        // Pause 1: 3-second quiet pause with beak closed (1.30 to 4.30s)
                        qSubClock = 0.0
                        isInQuackBurst = false
                    } else if localT < period + setDur {
                        // Set 2: second «quack · quack» (4.30 to 5.60s)
                        qSubClock = (localT - period) / setDur
                        isInQuackBurst = true
                    } else if localT < period * 2.0 {
                        // Pause 2: 3-second quiet pause with beak closed (5.60 to 8.60s)
                        qSubClock = 0.0
                        isInQuackBurst = false
                    } else if localT < period * 2.0 + setDur {
                        // Set 3: third «quack · quack» (8.60 to 9.90s)
                        qSubClock = (localT - period * 2.0) / setDur
                        isInQuackBurst = true
                    } else {
                        // "Y pasa": finishes quacking and transitions peacefully (9.90 to 17.0s)
                        qSubClock = 0.0
                        isInQuackBurst = false
                    }

                    if isInQuackBurst {
                        base.quackClock = qSubClock
                        base.isQuacking = true

                        if qSubClock > 0.05 && qSubClock < 0.45 {
                            let qp = sin(((qSubClock - 0.05) / 0.40) * .pi)
                            base.jaw = qp * 0.88
                            base.n = [-5.0 + qp * 2.0, -4.0, 0]
                            base.head = -11.0 - qp * 4.5 + mouseTilt * 0.5
                        } else if qSubClock > 0.52 && qSubClock < 0.98 {
                            let qp = sin(((qSubClock - 0.52) / 0.46) * .pi)
                            base.jaw = qp * 0.95
                            base.n = [-6.0 + qp * 2.5, -4.0, 0]
                            base.head = -12.0 - qp * 5.5 + mouseTilt * 0.5
                        } else {
                            base.jaw = 0.0
                            base.n = [-5.0, -4.0, 0]
                            base.head = -8.0 + mouseTilt
                        }
                    } else {
                        base.quackClock = 0.0
                        base.isQuacking = false
                        base.jaw = 0.0
                        base.n = [-2.0, -2.0, 0]
                        base.head = -8.0 + mouseTilt
                    }
                }
            } else {
                // Mouse is hovering right near Microduck: curious alert perk up!
                base.head = -14.0
                base.drowsy = 0.0
                base.footWiggle = time * 4.2 * s
            }
            return base

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
                base.head = -4.0 + sin(elapsed * .pi * 4.5 * s) * 12.0 * decay
            }
            return base

        case .failed, .cancelled:
            // Stands upright, shaking head in error / cancellation!
            var base: DuckPose = .standFront
            let elapsed = uptime - modeChangeTime
            if elapsed < 1.2 {
                let decay = max(0.0, 1.0 - elapsed / 1.2)
                base.head = -4.0 + sin(elapsed * .pi * 6.0 * s) * 14.0 * decay
            }
            return base

        case .modeChanged:
            // Stands upright when ready / mode changed
            return .standFront
        }
    }

    private var ledColor: Color {
        computeLedColor(isHovering: false)
    }

    private func computeLedColor(isHovering: Bool, isSleeping: Bool = false) -> Color {
        switch viewModel.mode {
        case .idle:
            if isHovering {
                return VoiceStationTokens.dotBlue
            }
            if isSleeping {
                return VoiceStationTokens.sleepRed // Coral sleep LED (#FF6B6B)
            }
            return viewModel.userPrefersStanding ? VoiceStationTokens.gold : VoiceStationTokens.okOnDark
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
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !viewModel.isVisible)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let uptime = ProcessInfo.processInfo.systemUptime
            let pose = currentPose(time: time, uptime: uptime)
            let isSitting = pose.isSitting

            let mouseLoc = NSEvent.mouseLocation
            let duckScreenX = viewModel.panelOrigin.x + 30.0
            let duckScreenY = viewModel.panelOrigin.y + 48.0
            let isHovering = isIdle && hypot(mouseLoc.x - duckScreenX, mouseLoc.y - duckScreenY) < 85.0
            let activeLedColor = computeLedColor(isHovering: isHovering, isSleeping: pose.isSleeping)

            ZStack(alignment: .bottomLeading) {
                // 1. Duck Articulated Mascot (at bottom left, facing front)
                if shouldShowDuck {
                    MicroduckView(
                        pose: pose,
                        audioLevel: viewModel.audioLevel,
                        ledColor: activeLedColor,
                        edition: viewModel.edition
                    )
                        .frame(width: HUDLayout.duckWidth, height: HUDLayout.duckHeight)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering {
                                viewModel.recordActivity()
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.5, anchor: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .id("microduck-actor")

                    // 2. Ambient Sleep Zzz particles when sleeping (delicate light-blue z · z · Z)
                    if pose.isSleeping && !shouldShowBubble {
                        sleepZzzOverlay(time: time, isSitting: isSitting)
                    }

                    // 3. Ambient Quack floating words (backgroundless staggered quack · quack)
                    if pose.isQuacking && !shouldShowBubble {
                        quackCallout(time: time, pose: pose, isSitting: isSitting)
                    }

                    // 4. Thought Trail Dots connecting duck's head to the bubble (only when bubble is active)
                    if shouldShowBubble {
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
                }

                // 5. Bubble Capsule (beside duck's head, only active during speech/status)
                if shouldShowBubble {
                    capsuleBubble
                        .offset(
                            x: shouldShowDuck ? HUDLayout.duckToBubble : 0,
                            y: shouldShowDuck ? (isSitting ? -36 : -44) : -10
                        )
                        .animation(.spring(response: 0.36, dampingFraction: 0.75), value: shouldShowDuck)
                        .animation(.spring(response: 0.36, dampingFraction: 0.75), value: isSitting)
                        .animation(.spring(response: 0.36, dampingFraction: 0.75), value: bubbleSize.width)
                        .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
            .frame(width: HUDLayout.panelWidth, height: HUDLayout.panelHeight, alignment: .bottomLeading)
        }
        .onChange(of: viewModel.mode) { _, _ in
            modeChangeTime = ProcessInfo.processInfo.systemUptime
            viewModel.recordActivity()
        }
        .onChange(of: viewModel.audioLevel) { _, lvl in
            if lvl > 0.20 {
                if !viewModel.voiceHeard {
                    viewModel.voiceHeard = true
                }
                viewModel.recordActivity()
            }
        }
    }

    // MARK: - Ambient Expression Overlays

    private func sleepZzzOverlay(time: Double, isSitting: Bool) -> some View {
        let s = MicroduckKinematics.canonicalSmoothness
        return ZStack(alignment: .bottomLeading) {
            ForEach(0..<3, id: \.self) { i in
                let cyclePhase = (time * 1.15 * s + Double(i) * 0.95).truncatingRemainder(dividingBy: 2.85) / 2.85
                // Delicate light-blue Zzz rising gently from the top of the duck's head
                let xDrift = 34.0 + Double(i) * 4.5 + cyclePhase * 12.0 + sin(cyclePhase * .pi * 2.0) * 2.4
                let yRise = (isSitting ? -46.0 : -52.0) - cyclePhase * 16.0
                let opacity = sin(cyclePhase * .pi) * 0.92
                let fontSize: CGFloat = 10.0 + CGFloat(i) * 2.5
                let glyph = i < 2 ? "z" : "Z"

                Text(glyph)
                    .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                    .foregroundColor(VoiceStationTokens.dotBlue)
                    .shadow(color: Color.black.opacity(0.75), radius: 2.0, x: 0, y: 1.0)
                    .offset(x: xDrift, y: yRise)
                    .opacity(opacity)
                    .scaleEffect(0.82 + cyclePhase * 0.28)
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func quackCallout(time: Double, pose: DuckPose, isSitting: Bool) -> some View {
        let qClock = pose.quackClock
        return ZStack(alignment: .bottomLeading) {
            // 1. First Quack (Gold, appears in sync with first beak opening at 0.05)
            if qClock >= 0.05 && qClock <= 0.52 {
                let p = (qClock - 0.05) / 0.42
                let easeOut = 1.0 - pow(1.0 - p, 2.2)
                let alpha = p < 0.20 ? (p / 0.20) : p > 0.70 ? (1.0 - (p - 0.70) / 0.30) : 1.0
                let x = 32.0 + easeOut * 14.0
                let y = (isSitting ? -38.0 : -52.0) - easeOut * 16.0

                Text("quack")
                    .font(.system(size: 11.0, weight: .heavy, design: .rounded))
                    .foregroundColor(VoiceStationTokens.gold)
                    .shadow(color: VoiceStationTokens.navy.opacity(0.95), radius: 0.8, x: 0, y: 0.8)
                    .rotationEffect(.degrees(-10.0))
                    .offset(x: x, y: y)
                    .opacity(alpha)
                    .scaleEffect(0.92 + easeOut * 0.16)
            }

            // 2. Second Quack (Duck Orange, appears in sync with second beak opening at 0.52)
            if qClock >= 0.52 && qClock <= 0.98 {
                let p = (qClock - 0.52) / 0.44
                let easeOut = 1.0 - pow(1.0 - p, 2.2)
                let alpha = p < 0.20 ? (p / 0.20) : p > 0.70 ? (1.0 - (p - 0.70) / 0.30) : 1.0
                let x = 40.0 + easeOut * 18.0
                let y = (isSitting ? -46.0 : -60.0) - easeOut * 18.0

                Text("quack")
                    .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                    .foregroundColor(VoiceStationTokens.duckOrange)
                    .shadow(color: VoiceStationTokens.navy.opacity(0.95), radius: 0.8, x: 0, y: 0.8)
                    .rotationEffect(.degrees(-6.0))
                    .offset(x: x, y: y)
                    .opacity(alpha)
                    .scaleEffect(0.96 + easeOut * 0.18)
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
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

            // Row 2: 12-bar equalizer / processing wave (fills 106pt column width evenly: 12*7 + 11*2 = 106)
            HStack(spacing: 2.0) {
                ForEach(0..<12) { i in
                    RoundedRectangle(cornerRadius: 1.0)
                        .fill(barColor(for: i))
                        .frame(width: 7.0, height: 3.6)
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
        case .idle:
            return "READY"
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
        case .idle:
            return VoiceStationTokens.okOnDark
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
        case .idle:
            return Color.white.opacity(0.12)
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
