import SwiftUI
import VoiceFlowMacCore

// MARK: - Microduck Edition (Active MD-01 Fusion vs Classic Reserve)

public enum MicroduckEdition: String, CaseIterable, Sendable {
    /// Approved Parado A + Sentado 2 sharing authentic Microduck MD-01 mechanical anatomy.
    case md01Fusion = "md01Fusion"
    /// Previous sitting and standing design preserved intact in reserve for future use.
    case classicReserve = "classicReserve"

    public var displayName: String {
        switch self {
        case .md01Fusion: return "MD-01 Fusion (Default)"
        case .classicReserve: return "Classic Duck (Reserve)"
        }
    }
}

// MARK: - Microduck Mascot Poses (Standing & Sitting with 0.60x Canonical Kinematics)

public struct DuckPose: Equatable, Sendable {
    public var tF: Double   // Left / Front Thigh angle
    public var kF: Double   // Left / Front Knee angle
    public var tB: Double   // Right / Back Thigh angle
    public var kB: Double   // Right / Back Knee angle
    public var body: Double // Body tilt / roll angle
    public var n: [Double]  // Neck 3-link angles [n0, n1, n2]
    public var head: Double // Head pitch / tilt angle (negative = head high / looking up)
    public var jaw: Double  // Jaw drop factor (0.0 to 1.0)
    public var isSideView: Bool // false = front facing
    public var isSitting: Bool  // true = sitting pose
    public var footWiggle: Double // Foot wiggle phase for playful seated swinging
    public var turn: Double // Head horizontal turn yaw (-14° to +14°)
    public var isSleeping: Bool // true when in deep sleep / nap mode (golden — eye line)
    public var isQuacking: Bool // true when quacking (backgroundless floating quack particles)
    public var eyeOffsetX: Double // Eye pupil horizontal shift (-3.5 to +3.5)
    public var eyeOffsetY: Double // Eye pupil vertical shift (-3.5 to +3.5)
    public var hopY: Double // Upward airborne / bounce offset (pt)
    public var bodyShiftX: Double // Subtle lateral hip shift during waddle / tip-tap (pt)
    public var drowsy: Double // Half-closed golden upper eyelid factor (0.0 awake to 1.0 sleepy)
    public var hipDropY: Double // Standing vertical hip crouch / breath drop
    public var bodyRoll: Double // Additional body roll for standing tiptap / waddle
    public var neckLean: Double // Neck lean angle during quack / crouch
    public var headRoll: Double // Head side-to-side roll / tilt angle
    public var footLiftL: Double // Left foot lift height (pt)
    public var footTiltL: Double // Left boot tilt angle (deg)
    public var footLiftR: Double // Right foot lift height (pt)
    public var footTiltR: Double // Right boot tilt angle (deg)
    public var kneeSpreadL: Double // Left knee outward spread (pt)
    public var kneeSpreadR: Double // Right knee outward spread (pt)
    public var quackClock: Double // Normalized 0.0 to 1.0 quack phase for two-beat beak sync

    public init(
        tF: Double,
        kF: Double,
        tB: Double,
        kB: Double,
        body: Double,
        n: [Double],
        head: Double,
        jaw: Double,
        isSideView: Bool,
        isSitting: Bool,
        footWiggle: Double = 0.0,
        turn: Double = 0.0,
        isSleeping: Bool = false,
        isQuacking: Bool = false,
        eyeOffsetX: Double = 0.0,
        eyeOffsetY: Double = 0.0,
        hopY: Double = 0.0,
        bodyShiftX: Double = 0.0,
        drowsy: Double = 0.0,
        hipDropY: Double = 0.0,
        bodyRoll: Double = 0.0,
        neckLean: Double = 0.0,
        headRoll: Double = 0.0,
        footLiftL: Double = 0.0,
        footTiltL: Double = 0.0,
        footLiftR: Double = 0.0,
        footTiltR: Double = 0.0,
        kneeSpreadL: Double = 0.0,
        kneeSpreadR: Double = 0.0,
        quackClock: Double = 0.0
    ) {
        self.tF = tF
        self.kF = kF
        self.tB = tB
        self.kB = kB
        self.body = body
        self.n = n
        self.head = head
        self.jaw = jaw
        self.isSideView = isSideView
        self.isSitting = isSitting
        self.footWiggle = footWiggle
        self.turn = turn
        self.isSleeping = isSleeping
        self.isQuacking = isQuacking
        self.eyeOffsetX = eyeOffsetX
        self.eyeOffsetY = eyeOffsetY
        self.hopY = hopY
        self.bodyShiftX = bodyShiftX
        self.drowsy = drowsy
        self.hipDropY = hipDropY
        self.bodyRoll = bodyRoll
        self.neckLean = neckLean
        self.headRoll = headRoll
        self.footLiftL = footLiftL
        self.footTiltL = footTiltL
        self.footLiftR = footLiftR
        self.footTiltR = footTiltR
        self.kneeSpreadL = kneeSpreadL
        self.kneeSpreadR = kneeSpreadR
        self.quackClock = quackClock
    }

    // Standing pose: upright on both feet, head high, proud & alert (idle / ready)
    public static let standFront = DuckPose(
        tF: 0, kF: 0, tB: 0, kB: 0, body: 0,
        n: [-2, -2, 0], head: -4, jaw: 0, isSideView: false, isSitting: false, footWiggle: 0
    )
    public static let front = DuckPose(
        tF: 0, kF: 0, tB: 0, kB: 0, body: 0,
        n: [-2, -2, 0], head: -4, jaw: 0, isSideView: false, isSitting: false, footWiggle: 0
    )
    public static let stand = DuckPose(
        tF: 0, kF: 0, tB: 0, kB: 0, body: 0,
        n: [-2, -2, 0], head: -4, jaw: 0, isSideView: false, isSitting: false, footWiggle: 0
    )

    // Ambient seated poses (Tamagotchi / desktop companion behaviors)
    public static let seatedDefault = DuckPose(
        tF: 0, kF: 0, tB: 0, kB: 0, body: 0,
        n: [-2, -2, 0], head: -8, jaw: 0, isSideView: false, isSitting: true, footWiggle: 0
    )
    public static let seatedCurious = DuckPose(
        tF: 0, kF: 0, tB: 0, kB: 0, body: 0,
        n: [-2, -2, 0], head: -8, jaw: 0, isSideView: false, isSitting: true, footWiggle: 0, turn: -12.0
    )
    public static let seatedQuack = DuckPose(
        tF: 0, kF: 0, tB: 0, kB: 0, body: 0,
        n: [-5, -4, 0], head: -12, jaw: 0.85, isSideView: false, isSitting: true, footWiggle: 0, isQuacking: true
    )
    public static let seatedSleep = DuckPose(
        tF: 0, kF: 0, tB: 0, kB: 2.0, body: 2.0,
        n: [2, 1, 0], head: 6, jaw: 0, isSideView: false, isSitting: true, footWiggle: 0, isSleeping: true
    )

    // Sitting pose: knees folded forward, settling in to listen (when recording)
    public static let recordingSitting = DuckPose(
        tF: 0, kF: 0, tB: 0, kB: 0, body: 0,
        n: [-2, -2, 0], head: -8, jaw: 0, isSideView: false, isSitting: true, footWiggle: 0
    )
    public static let stretchSitting = DuckPose(
        tF: 0, kF: 0, tB: 0, kB: 0, body: 0,
        n: [-5, -3, 0], head: -12, jaw: 1.0, isSideView: false, isSitting: true, footWiggle: 0
    )

    // Legacy pose mappings kept safe
    public static let lean = DuckPose(
        tF: 0, kF: 0, tB: 0, kB: 0, body: 0,
        n: [-2, -2, 0], head: -8, jaw: 0, isSideView: false, isSitting: true, footWiggle: 0
    )
    public static let stretch = DuckPose(
        tF: 0, kF: 0, tB: 0, kB: 0, body: 0,
        n: [-5, -3, 0], head: -12, jaw: 1.0, isSideView: false, isSitting: true, footWiggle: 0
    )
    public static let lookUp = DuckPose(
        tF: 0, kF: 0, tB: 0, kB: 0, body: 0,
        n: [-3, -3, 0], head: -10, jaw: 0, isSideView: false, isSitting: true, footWiggle: 0
    )
    public static let sit = DuckPose(
        tF: 0, kF: 0, tB: 0, kB: 0, body: 0,
        n: [-2, -2, 0], head: -8, jaw: 0, isSideView: false, isSitting: true, footWiggle: 0
    )

    public func mixed(with target: DuckPose, k: Double) -> DuckPose {
        let f = max(0.0, min(1.0, k))
        let mixedNeck = zip(n, target.n).map { $0 + ($1 - $0) * f }
        return DuckPose(
            tF: tF + (target.tF - tF) * f,
            kF: kF + (target.kF - kF) * f,
            tB: tB + (target.tB - tB) * f,
            kB: kB + (target.kB - kB) * f,
            body: body + (target.body - body) * f,
            n: mixedNeck,
            head: head + (target.head - head) * f,
            jaw: jaw + (target.jaw - jaw) * f,
            isSideView: f > 0.5 ? target.isSideView : isSideView,
            isSitting: f > 0.5 ? target.isSitting : isSitting,
            footWiggle: footWiggle + (target.footWiggle - footWiggle) * f,
            turn: turn + (target.turn - turn) * f,
            isSleeping: f > 0.5 ? target.isSleeping : isSleeping,
            isQuacking: f > 0.5 ? target.isQuacking : isQuacking,
            eyeOffsetX: eyeOffsetX + (target.eyeOffsetX - eyeOffsetX) * f,
            eyeOffsetY: eyeOffsetY + (target.eyeOffsetY - eyeOffsetY) * f,
            hopY: hopY + (target.hopY - hopY) * f,
            bodyShiftX: bodyShiftX + (target.bodyShiftX - bodyShiftX) * f,
            drowsy: drowsy + (target.drowsy - drowsy) * f,
            hipDropY: hipDropY + (target.hipDropY - hipDropY) * f,
            bodyRoll: bodyRoll + (target.bodyRoll - bodyRoll) * f,
            neckLean: neckLean + (target.neckLean - neckLean) * f,
            headRoll: headRoll + (target.headRoll - headRoll) * f,
            footLiftL: footLiftL + (target.footLiftL - footLiftL) * f,
            footTiltL: footTiltL + (target.footTiltL - footTiltL) * f,
            footLiftR: footLiftR + (target.footLiftR - footLiftR) * f,
            footTiltR: footTiltR + (target.footTiltR - footTiltR) * f,
            kneeSpreadL: kneeSpreadL + (target.kneeSpreadL - kneeSpreadL) * f,
            kneeSpreadR: kneeSpreadR + (target.kneeSpreadR - kneeSpreadR) * f,
            quackClock: quackClock + (target.quackClock - quackClock) * f
        )
    }
}

public enum MicroduckKinematics {
    /// Canonical movement speed multiplier approved in reference mockups (0.60x delicate cadence).
    public static let canonicalSmoothness: Double = 0.60
    public static let ground: Double = 188.0
    public static let rx: Double = 78.0
    public static let thigh: Double = 12.0
    public static let shin: Double = 12.0
    public static let foot: Double = 11.5
    public static let deg2rad: Double = Double.pi / 180.0

    public static func ankleY(t: Double, k: Double) -> Double {
        thigh * cos(t * deg2rad) + shin * cos((t + k) * deg2rad)
    }

    public static func hipY(pose: DuckPose) -> Double {
        let aF = ankleY(t: pose.tF, k: pose.kF)
        let aB = ankleY(t: pose.tB, k: pose.kB)
        return ground - foot - max(aF, aB)
    }
}

// MARK: - SwiftUI Microduck Articulated Mascot View

public struct MicroduckView: View {
    public let pose: DuckPose
    public let audioLevel: Float
    public let ledColor: Color
    public let edition: MicroduckEdition

    public init(
        pose: DuckPose,
        audioLevel: Float,
        ledColor: Color,
        edition: MicroduckEdition = .md01Fusion
    ) {
        self.pose = pose
        self.audioLevel = audioLevel
        self.ledColor = ledColor
        self.edition = edition
    }

    // Geometry box 170 × 200, aspect-fit uniformly into 60 × 82 pt to prevent anamorphic distortion
    public var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 170.0, size.height / 200.0)
            let offsetX = (size.width - 170.0 * scale) / 2.0
            let offsetY = (size.height - 200.0 * scale) / 2.0
            context.translateBy(x: offsetX, y: offsetY)
            context.scaleBy(x: scale, y: scale)

            switch edition {
            case .md01Fusion:
                if pose.isSitting {
                    drawMD01SittingDuck(context: context, pose: pose)
                } else {
                    drawMD01StandingDuck(context: context, pose: pose)
                }
            case .classicReserve:
                if pose.isSitting {
                    drawClassicSittingDuck(context: context, pose: pose)
                } else {
                    drawClassicStandingDuck(context: context, pose: pose)
                }
            }
        }
        .frame(width: HUDLayout.duckWidth, height: HUDLayout.duckHeight)
    }

    // MARK: - MD-01 Fusion Standing Duck (Parado A: Diamond Stance < >, Champagne Hip Brackets, Pyramidal Boots)

    private func drawMD01StandingDuck(context: GraphicsContext, pose: DuckPose) {
        let gY = MicroduckKinematics.ground // 188.0
        let rx = MicroduckKinematics.rx + pose.bodyShiftX // 78.0 + hipShiftX

        // 1. Soft Ground Shadow
        let hopRatio = max(0.0, min(1.0, pose.hopY / 16.0))
        let shadowWidth = 84.0 - hopRatio * 18.0
        let shadowHeight = 10.4 - hopRatio * 3.0
        let shadowRect = CGRect(
            x: (MicroduckKinematics.rx + pose.bodyShiftX * 0.5) - shadowWidth / 2.0,
            y: (gY + 2.0) - shadowHeight / 2.0,
            width: shadowWidth,
            height: shadowHeight
        )
        context.fill(Path(ellipseIn: shadowRect), with: .color(Color.black.opacity(max(0.12, 0.36 - hopRatio * 0.16))))

        let hipY = gY - 39.0 + pose.hipDropY - pose.hopY

        // 2. Left & Right MD-01 Diamond Legs (< >)
        drawMD01ArticulatedLeg(
            ctx: context,
            rx: rx,
            hipY: hipY,
            footGroundY: gY - pose.footLiftL,
            side: -1.0,
            kneeSpread: pose.kneeSpreadL,
            footTilt: pose.footTiltL
        )
        drawMD01ArticulatedLeg(
            ctx: context,
            rx: rx,
            hipY: hipY,
            footGroundY: gY - pose.footLiftR,
            side: 1.0,
            kneeSpread: pose.kneeSpreadR,
            footTilt: pose.footTiltR
        )

        // 3. Pelvis & Torso Assembly
        context.drawLayer { ctx in
            ctx.translateBy(x: rx, y: hipY)
            ctx.rotate(by: Angle(degrees: pose.body + pose.bodyRoll))

            // Pelvis & Dual Champagne U-Brackets ([∷•] [•∷])
            drawMD01PelvisAssembly(ctx: ctx)

            // Torso Shell with centered "SBdot"
            drawMD01TorsoPillow(ctx: ctx)

            // Segmented Neck Column with wire loops
            let torsoTop = -29.0
            ctx.translateBy(x: 0, y: torsoTop)
            ctx.rotate(by: Angle(degrees: pose.neckLean))
            ctx.translateBy(x: 0, y: -torsoTop)
            drawMD01NeckSegmentWithWires(ctx: ctx, torsoTop: torsoTop)

            // Head Rig (pitch + roll + yaw)
            let neckTop = torsoTop - 16.0
            ctx.translateBy(x: 0, y: neckTop + 2.0)
            ctx.rotate(by: Angle(degrees: pose.headRoll + pose.head * 0.35))
            ctx.scaleBy(x: 1.15, y: 1.15)
            ctx.translateBy(x: -62.0, y: -60.0 - pose.head * 0.35)

            drawMD01Head(
                ctx: ctx,
                jawDrop: pose.jaw * 15.0,
                turn: pose.turn,
                isSleeping: pose.isSleeping,
                drowsy: pose.drowsy,
                eyeOffsetX: pose.eyeOffsetX,
                eyeOffsetY: pose.eyeOffsetY
            )
        }
    }

    private func drawMD01ArticulatedLeg(
        ctx: GraphicsContext,
        rx: Double,
        hipY: Double,
        footGroundY: Double,
        side: Double,
        kneeSpread: Double,
        footTilt: Double
    ) {
        let frameColor = VoiceStationTokens.navy
        let champagne = VoiceStationTokens.headerBtnAmber
        let shellColor = VoiceStationTokens.inputCream
        let shadeColor = VoiceStationTokens.panelHeader
        let billColor = VoiceStationTokens.duckOrange
        let soleColor = VoiceStationTokens.gold

        let hipX = rx + side * 14.0
        let kneeOutX = rx + side * (25.5 + kneeSpread)
        let kneeY = hipY + 15.5
        let ankleX = rx + side * 16.5
        let ankleY = footGroundY - 9.5

        // 1. Dark lateral hip actuator
        let actX = side < 0 ? (hipX - 11.0) : (hipX - 1.0)
        let actRect = CGRect(x: actX, y: hipY - 4.5, width: 12.0, height: 10.0)
        ctx.fill(Path(roundedRect: actRect, cornerRadius: 3.0), with: .color(frameColor))

        // 2. Inward-angled metallic shin (\ /)
        ctx.drawLayer { shinCtx in
            let shinDX = ankleX - kneeOutX
            let shinDY = ankleY - kneeY
            let shinAngle = atan2(shinDY, shinDX) - Double.pi / 2.0
            let shinLen = hypot(shinDX, shinDY)

            shinCtx.translateBy(x: kneeOutX, y: kneeY)
            shinCtx.rotate(by: Angle(radians: shinAngle))

            let shinRect = CGRect(x: -4.5, y: -1.0, width: 9.0, height: shinLen + 2.0)
            shinCtx.fill(Path(roundedRect: shinRect, cornerRadius: 2.5), with: .color(champagne))
            let innerServo = CGRect(x: -5.2, y: shinLen * 0.22, width: 10.4, height: shinLen * 0.68)
            shinCtx.fill(Path(roundedRect: innerServo, cornerRadius: 2.2), with: .color(frameColor))
            let creamAccent = CGRect(x: -1.5, y: shinLen * 0.32, width: 2.0, height: 2.8)
            shinCtx.fill(Path(roundedRect: creamAccent, cornerRadius: 0.5), with: .color(shellColor))
        }

        // 3. Outward-angled White Thigh Fender Plate (/ \)
        ctx.drawLayer { thighCtx in
            let thighDX = kneeOutX - (hipX + side * 4.0)
            let thighDY = (kneeY + 3.0) - (hipY - 3.0)
            let thighAngle = atan2(thighDY, thighDX) - Double.pi / 2.0
            let thighLen = hypot(thighDX, thighDY) + 5.0

            thighCtx.translateBy(x: hipX + side * 5.0, y: hipY - 3.0)
            thighCtx.rotate(by: Angle(radians: thighAngle))

            let servoCore = CGRect(x: -6.0, y: -2.0, width: 12.0, height: thighLen)
            thighCtx.fill(Path(roundedRect: servoCore, cornerRadius: 4.0), with: .color(frameColor))

            let fenderX = side < 0 ? -7.5 : -4.5
            let fenderRect = CGRect(x: fenderX, y: -2.5, width: 12.0, height: thighLen + 1.0)
            thighCtx.fill(Path(roundedRect: fenderRect, cornerRadius: 5.5), with: .color(shellColor))
            thighCtx.stroke(Path(roundedRect: fenderRect, cornerRadius: 5.5), with: .color(frameColor), lineWidth: 1.2)

            let shadeX = side < 0 ? 1.5 : -4.5
            let shadeRect = CGRect(x: shadeX, y: -2.5, width: 3.0, height: thighLen + 1.0)
            thighCtx.fill(Path(roundedRect: shadeRect, cornerRadius: 2.0), with: .color(shadeColor.opacity(0.35)))

            let pinX = side < 0 ? -1.5 : 1.5
            thighCtx.fill(Path(ellipseIn: CGRect(x: pinX - 1.15, y: thighLen - 4.5 - 1.15, width: 2.3, height: 2.3)), with: .color(frameColor))
        }

        // 4. Pyramidal Two-Tone Boot (with toe-tap articulation!)
        ctx.drawLayer { bootCtx in
            bootCtx.translateBy(x: ankleX, y: ankleY)
            bootCtx.rotate(by: Angle(degrees: footTilt))

            var bootPath = Path()
            bootPath.move(to: CGPoint(x: -11.5, y: 6.5))
            bootPath.addLine(to: CGPoint(x: -9.5, y: 0.5))
            bootPath.addQuadCurve(to: CGPoint(x: -4.5, y: -2.5), control: CGPoint(x: -8.5, y: -2.5))
            bootPath.addLine(to: CGPoint(x: 4.5, y: -2.5))
            bootPath.addQuadCurve(to: CGPoint(x: 9.5, y: 0.5), control: CGPoint(x: 8.5, y: -2.5))
            bootPath.addLine(to: CGPoint(x: 11.5, y: 6.5))
            bootPath.closeSubpath()
            bootCtx.fill(bootPath, with: .color(billColor))
            bootCtx.stroke(bootPath, with: .color(frameColor), lineWidth: 1.1)

            // 3 Navy Dots
            bootCtx.fill(Path(ellipseIn: CGRect(x: -0.95, y: 0.2 - 0.95, width: 1.9, height: 1.9)), with: .color(frameColor))
            bootCtx.fill(Path(ellipseIn: CGRect(x: -3.2 - 0.95, y: 3.2 - 0.95, width: 1.9, height: 1.9)), with: .color(frameColor))
            bootCtx.fill(Path(ellipseIn: CGRect(x: 3.2 - 0.95, y: 3.2 - 0.95, width: 1.9, height: 1.9)), with: .color(frameColor))

            // Gold sole
            let soleRect = CGRect(x: -12.5, y: 5.5, width: 25.0, height: 4.2)
            bootCtx.fill(Path(roundedRect: soleRect, cornerRadius: 2.1), with: .color(soleColor))
            bootCtx.stroke(Path(roundedRect: soleRect, cornerRadius: 2.1), with: .color(frameColor), lineWidth: 1.0)
        }
    }

    private func drawMD01PelvisAssembly(ctx: GraphicsContext) {
        let frameColor = VoiceStationTokens.navy
        let champagne = VoiceStationTokens.headerBtnAmber
        let silverColor = VoiceStationTokens.footerMuted

        // Central dark pelvis block
        ctx.fill(
            Path(roundedRect: CGRect(x: -18, y: -7, width: 36, height: 15), cornerRadius: 3.5),
            with: .color(frameColor)
        )

        // Dual Champagne/Silver Horizontal Hip U-Brackets ([∷•] [•∷])
        for bx in [-9.5, 9.5] {
            let bRect = CGRect(x: bx - 7.5, y: -5.5, width: 15.0, height: 10.5)
            ctx.fill(Path(roundedRect: bRect, cornerRadius: 3.5), with: .color(champagne))
            ctx.stroke(Path(roundedRect: bRect, cornerRadius: 3.5), with: .color(frameColor.opacity(0.45)), lineWidth: 0.9)

            ctx.fill(Path(ellipseIn: CGRect(x: bx - 2.0, y: -0.2 - 2.0, width: 4.0, height: 4.0)), with: .color(frameColor))
            ctx.fill(Path(ellipseIn: CGRect(x: bx - 1.0, y: -0.2 - 1.0, width: 2.0, height: 2.0)), with: .color(silverColor))

            for dx in [-3.6, 3.6] {
                for dy in [-2.0, 1.6] {
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: bx + dx - 0.8, y: dy - 0.8, width: 1.6, height: 1.6)),
                        with: .color(frameColor)
                    )
                }
            }
        }
    }

    private func drawMD01TorsoPillow(ctx: GraphicsContext) {
        let frameColor = VoiceStationTokens.navy
        let shellColor = VoiceStationTokens.inputCream
        let shadeColor = VoiceStationTokens.panelHeader
        let dotColor = VoiceStationTokens.dotBlue

        let torsoW: Double = 42.0
        let torsoH: Double = 23.0
        let torsoTop: Double = -6.0 - torsoH // -29.0

        ctx.fill(
            Path(roundedRect: CGRect(x: -torsoW / 2.0, y: torsoTop, width: torsoW, height: torsoH), cornerRadius: 8.5),
            with: .color(shellColor)
        )
        ctx.fill(
            Path(roundedRect: CGRect(x: torsoW / 2.0 - 10.0, y: torsoTop, width: 10.0, height: torsoH), cornerRadius: 5.5),
            with: .color(shadeColor.opacity(0.35))
        )
        ctx.stroke(
            Path(roundedRect: CGRect(x: -torsoW / 2.0, y: torsoTop, width: torsoW, height: torsoH), cornerRadius: 8.5),
            with: .color(frameColor.opacity(0.85)),
            lineWidth: 1.1
        )

        // Top black servo neck recess
        ctx.fill(
            Path(roundedRect: CGRect(x: -6.5, y: torsoTop + 0.5, width: 13.0, height: 4.5), cornerRadius: 2.0),
            with: .color(frameColor)
        )
        ctx.fill(
            Path(ellipseIn: CGRect(x: -17.5 - 1.1, y: torsoTop + 6.5 - 1.1, width: 2.2, height: 2.2)),
            with: .color(frameColor)
        )

        // Centered "SBdot" wordmark
        let brandText = Text("SB").font(.system(size: 8.5, weight: .black, design: .monospaced)).foregroundColor(frameColor)
            + Text("dot").font(.system(size: 4.6, weight: .heavy, design: .monospaced)).foregroundColor(dotColor).baselineOffset(3.2)
        ctx.draw(brandText, at: CGPoint(x: -4.0, y: torsoTop + 12.5), anchor: .center)
        ctx.fill(
            Path(ellipseIn: CGRect(x: 10.5 - 2.1, y: torsoTop + 6.5 - 2.1, width: 4.2, height: 4.2)),
            with: .color(dotColor)
        )
    }

    private func drawMD01NeckSegmentWithWires(ctx: GraphicsContext, torsoTop: Double) {
        let frameColor = VoiceStationTokens.navy
        let champagne = VoiceStationTokens.headerBtnAmber
        let shellColor = VoiceStationTokens.inputCream
        let neckH: Double = 16.0
        let neckTop: Double = torsoTop - neckH

        // Left servo wire loops
        var wire1 = Path()
        wire1.addArc(
            center: CGPoint(x: -6.5, y: torsoTop - neckH * 0.45),
            radius: 5.5,
            startAngle: Angle(radians: 0.55 * .pi),
            endAngle: Angle(radians: 1.48 * .pi),
            clockwise: false
        )
        ctx.stroke(wire1, with: .color(frameColor), lineWidth: 1.6)

        var wire2 = Path()
        wire2.addArc(
            center: CGPoint(x: -6.0, y: torsoTop - neckH * 0.35),
            radius: 4.0,
            startAngle: Angle(radians: 0.60 * .pi),
            endAngle: Angle(radians: 1.42 * .pi),
            clockwise: false
        )
        ctx.stroke(wire2, with: .color(frameColor), lineWidth: 1.6)

        // Main segmented black column
        let colRect = CGRect(x: -6.2, y: neckTop, width: 12.4, height: neckH + 3.0)
        ctx.fill(Path(roundedRect: colRect, cornerRadius: 2.5), with: .color(frameColor))

        // Horizontal score line
        var scoreLine = Path()
        scoreLine.move(to: CGPoint(x: -6.0, y: neckTop + neckH * 0.52))
        scoreLine.addLine(to: CGPoint(x: 6.0, y: neckTop + neckH * 0.52))
        ctx.stroke(scoreLine, with: .color(Color.white.opacity(0.18)), lineWidth: 0.9)

        // Champagne servo bracket & cream connectors
        let plateRect = CGRect(x: -6.2, y: neckTop + 2.0, width: 3.8, height: neckH - 2.0)
        ctx.fill(Path(roundedRect: plateRect, cornerRadius: 1.2), with: .color(champagne))
        let pin1 = CGRect(x: -2.2, y: neckTop + 2.8, width: 2.2, height: 2.8)
        ctx.fill(Path(roundedRect: pin1, cornerRadius: 0.6), with: .color(shellColor))
        let pin2 = CGRect(x: -2.2, y: neckTop + neckH * 0.58, width: 2.2, height: 2.8)
        ctx.fill(Path(roundedRect: pin2, cornerRadius: 0.6), with: .color(shellColor))
    }

    private func drawMD01NeckSegment(ctx: GraphicsContext) {
        let frameColor = VoiceStationTokens.navy
        let silverColor = VoiceStationTokens.footerMuted
        let shellColor = VoiceStationTokens.inputCream

        // Left curved black servo cable loop
        var wirePath = Path()
        wirePath.move(to: CGPoint(x: -5.5, y: -9.5))
        wirePath.addQuadCurve(to: CGPoint(x: -5.5, y: -1.5), control: CGPoint(x: -11.5, y: -5.5))
        ctx.stroke(wirePath, with: .color(frameColor), lineWidth: 1.8)

        // Segmented black servo neck column
        let rect = CGRect(x: -6.5, y: -11.5, width: 13.0, height: 13.5)
        ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(frameColor))

        // Center silver servo horn pin
        let pin = CGRect(x: -2.2, y: -7.2, width: 4.4, height: 4.4)
        ctx.fill(Path(ellipseIn: pin), with: .color(silverColor))

        // White Molex connector housing on front-right of neck ([▪])
        let molexRect = CGRect(x: 2.2, y: -9.0, width: 4.8, height: 6.2)
        ctx.fill(Path(roundedRect: molexRect, cornerRadius: 1.0), with: .color(shellColor))
        ctx.stroke(Path(roundedRect: molexRect, cornerRadius: 1.0), with: .color(frameColor), lineWidth: 0.9)
        ctx.fill(Path(CGRect(x: 3.6, y: -7.6, width: 1.8, height: 1.3)), with: .color(frameColor))
        ctx.fill(Path(CGRect(x: 3.6, y: -5.2, width: 1.8, height: 1.3)), with: .color(frameColor))
    }

    // MARK: - MD-01 Fusion Sitting Duck (Sentado 2: Classic Seated Posture + MD-01 Fine Details)

    private func drawMD01SittingDuck(context: GraphicsContext, pose: DuckPose) {
        let frameColor = VoiceStationTokens.navy
        let metalColor = VoiceStationTokens.micHighlight
        let silverColor = VoiceStationTokens.footerMuted
        let champagne = VoiceStationTokens.headerBtnAmber
        let shellColor = VoiceStationTokens.inputCream
        let shadeColor = VoiceStationTokens.panelHeader
        let dotColor = VoiceStationTokens.dotBlue
        let billColor = VoiceStationTokens.duckOrange
        let billDeep = VoiceStationTokens.duckOrangeDeep
        let soleColor = VoiceStationTokens.gold

        let groundY = MicroduckKinematics.ground
        let cx = MicroduckKinematics.rx + pose.bodyShiftX

        let wPhase = pose.footWiggle
        let leftSway = sin(wPhase)
        let rightSway = sin(wPhase - 0.35)

        // 1. Wide Ground Shadow under seated body and folded feet
        let shadowRect = CGRect(x: cx - 44, y: groundY - 2, width: 88, height: 9.5)
        context.fill(Path(ellipseIn: shadowRect), with: .color(Color.black.opacity(0.38)))

        // 2. White outer thigh fenders folded back on the sides (with MD-01 lower pin hole)
        context.drawLayer { ctx in
            ctx.translateBy(x: cx - 30, y: groundY - 14)
            ctx.rotate(by: Angle(degrees: -22 + leftSway * 1.5))
            ctx.fill(Path(roundedRect: CGRect(x: -6, y: -4, width: 12, height: 14), cornerRadius: 3), with: .color(frameColor))
            ctx.fill(Path(roundedRect: CGRect(x: -8, y: -2, width: 16, height: 18), cornerRadius: 5), with: .color(shellColor))
            ctx.fill(Path(roundedRect: CGRect(x: -8, y: -2, width: 5, height: 18), cornerRadius: 3), with: .color(shadeColor.opacity(0.35)))
            ctx.stroke(Path(roundedRect: CGRect(x: -8, y: -2, width: 16, height: 18), cornerRadius: 5), with: .color(frameColor), lineWidth: 1.2)
            ctx.fill(Path(ellipseIn: CGRect(x: -2.2, y: 8.5, width: 4.4, height: 4.4)), with: .color(frameColor))
            ctx.fill(Path(ellipseIn: CGRect(x: -1.0, y: 9.7, width: 2.0, height: 2.0)), with: .color(silverColor))
        }

        context.drawLayer { ctx in
            ctx.translateBy(x: cx + 30, y: groundY - 14)
            ctx.rotate(by: Angle(degrees: 22 + rightSway * 1.5))
            ctx.fill(Path(roundedRect: CGRect(x: -6, y: -4, width: 12, height: 14), cornerRadius: 3), with: .color(frameColor))
            ctx.fill(Path(roundedRect: CGRect(x: -8, y: -2, width: 16, height: 18), cornerRadius: 5), with: .color(shellColor))
            ctx.fill(Path(roundedRect: CGRect(x: 3, y: -2, width: 5, height: 18), cornerRadius: 3), with: .color(shadeColor.opacity(0.35)))
            ctx.stroke(Path(roundedRect: CGRect(x: -8, y: -2, width: 16, height: 18), cornerRadius: 5), with: .color(frameColor), lineWidth: 1.2)
            ctx.fill(Path(ellipseIn: CGRect(x: -2.2, y: 8.5, width: 4.4, height: 4.4)), with: .color(frameColor))
            ctx.fill(Path(ellipseIn: CGRect(x: -1.0, y: 9.7, width: 2.0, height: 2.0)), with: .color(silverColor))
        }

        // 3. Pelvis resting low with MD-01 Champagne U-brackets ([∷•][•∷]) visible between feet
        let pelvisY = groundY - 18
        context.fill(Path(roundedRect: CGRect(x: cx - 24, y: pelvisY, width: 48, height: 14), cornerRadius: 4), with: .color(frameColor))
        for side in [-1.0, 1.0] {
            let bx = side < 0 ? (cx - 19.5) : (cx + 2.5)
            let bRect = CGRect(x: bx, y: pelvisY + 2.0, width: 17.0, height: 9.5)
            context.fill(Path(roundedRect: bRect, cornerRadius: 2.2), with: .color(champagne))
            context.stroke(Path(roundedRect: bRect, cornerRadius: 2.2), with: .color(frameColor), lineWidth: 1.1)
            let dotX = side < 0 ? bx + 4.5 : bx + 9.0
            context.fill(Path(ellipseIn: CGRect(x: dotX, y: pelvisY + 4.8, width: 3.6, height: 3.6)), with: .color(frameColor))
            context.fill(Path(ellipseIn: CGRect(x: dotX + 0.9, y: pelvisY + 5.7, width: 1.8, height: 1.8)), with: .color(silverColor))
        }

        // 4. White Torso Shell sitting proudly with optically centered "SBdot"
        let torsoY = pelvisY - 30
        context.fill(Path(roundedRect: CGRect(x: cx - 23, y: torsoY, width: 46, height: 32), cornerRadius: 10), with: .color(shellColor))
        context.fill(Path(roundedRect: CGRect(x: cx + 11, y: torsoY, width: 12, height: 32), cornerRadius: 6), with: .color(shadeColor.opacity(0.35)))
        context.stroke(Path(roundedRect: CGRect(x: cx - 23, y: torsoY, width: 46, height: 32), cornerRadius: 10), with: .color(frameColor), lineWidth: 1.3)

        let brandText = Text("SB").font(.system(size: 9.0, weight: .heavy, design: .monospaced)).foregroundColor(frameColor)
            + Text("dot").font(.system(size: 4.8, weight: .black, design: .monospaced)).foregroundColor(dotColor).baselineOffset(4.5)
        context.draw(brandText, at: CGPoint(x: cx - 6.0, y: torsoY + 15), anchor: .center)

        context.fill(Path(ellipseIn: CGRect(x: cx - 6.0 + 18.0 - 2.3, y: torsoY + 7.0 - 2.3, width: 4.6, height: 4.6)), with: .color(dotColor))

        // 5. Two Orange Feet Splayed Open in Front ("patitas abiertas" + 3-screw MD-01 detail)
        let leftX = (cx - 24.0) + leftSway * 5.0
        let leftY = groundY - 12.0 - abs(leftSway) * 2.5
        let leftAngle = -24.0 + leftSway * 14.0

        let rightX = (cx + 24.0) + rightSway * 5.0
        let rightY = groundY - 12.0 - abs(rightSway) * 2.5
        let rightAngle = 24.0 + rightSway * 14.0

        for (fx, fy, fAngle) in [(leftX, leftY, leftAngle), (rightX, rightY, rightAngle)] {
            context.drawLayer { ctx in
                ctx.translateBy(x: fx, y: fy)
                ctx.rotate(by: Angle(degrees: fAngle))

                let footRect = CGRect(x: -8.5, y: -9, width: 17, height: 21)
                ctx.fill(Path(roundedRect: footRect, cornerRadius: 5.5), with: .color(billColor))
                ctx.fill(Path(roundedRect: CGRect(x: -7.0, y: 1.5, width: 14, height: 5.5), cornerRadius: 2.0), with: .color(billDeep.opacity(0.45)))

                let soleRect = CGRect(x: -8.5, y: 7, width: 17, height: 5)
                ctx.fill(Path(roundedRect: soleRect, cornerRadius: 2.5), with: .color(soleColor))
                ctx.stroke(Path(roundedRect: footRect, cornerRadius: 5.5), with: .color(frameColor), lineWidth: 1.2)

                // Top ankle pivot + 2 lower MD-01 triangle screws
                ctx.fill(Path(ellipseIn: CGRect(x: -2.5, y: -7.5, width: 5, height: 5)), with: .color(frameColor))
                ctx.fill(Path(ellipseIn: CGRect(x: -1.2, y: -6.2, width: 2.4, height: 2.4)), with: .color(metalColor))
                ctx.fill(Path(ellipseIn: CGRect(x: -4.8, y: 0.5, width: 2.2, height: 2.2)), with: .color(frameColor))
                ctx.fill(Path(ellipseIn: CGRect(x: 2.6, y: 0.5, width: 2.2, height: 2.2)), with: .color(frameColor))
            }
        }

        // 6. Articulated MD-01 Neck Link (with Molex plug + wire) and MD-01 Head
        context.drawLayer { ctx in
            ctx.translateBy(x: cx, y: torsoY)
            ctx.rotate(by: Angle(degrees: pose.body))

            ctx.translateBy(x: 0, y: -2)
            let neckAngle = (pose.n.count > 0 ? pose.n[0] : 0) + (pose.n.count > 1 ? pose.n[1] * 0.5 : 0)
            ctx.rotate(by: Angle(degrees: neckAngle))
            drawMD01NeckSegment(ctx: ctx)

            ctx.translateBy(x: 0, y: -10)
            ctx.rotate(by: Angle(degrees: pose.head))
            ctx.scaleBy(x: 1.15, y: 1.15)
            ctx.translateBy(x: -62.0, y: -60)
            drawMD01Head(
                ctx: ctx,
                jawDrop: pose.jaw * 15.0,
                turn: pose.turn,
                isSleeping: pose.isSleeping,
                drowsy: pose.drowsy,
                eyeOffsetX: pose.eyeOffsetX,
                eyeOffsetY: pose.eyeOffsetY
            )
        }
    }

    // MARK: - Shared MD-01 Head (Golden Horizontal Sleep Bar, 3-Dot Jaw Hinges & 3D Inner Beak Plate)

    private func drawMD01Head(
        ctx: GraphicsContext,
        jawDrop: Double,
        turn: Double = 0.0,
        isSleeping: Bool = false,
        drowsy: Double = 0.0,
        eyeOffsetX: Double = 0.0,
        eyeOffsetY: Double = 0.0
    ) {
        var ctx = ctx
        let shellColor = VoiceStationTokens.inputCream
        let shadeColor = VoiceStationTokens.panelHeader
        let silverColor = VoiceStationTokens.footerMuted
        let frameColor = VoiceStationTokens.navy
        let eyeColor = VoiceStationTokens.gold
        let micHigh = VoiceStationTokens.micHighlight
        let dotColor = VoiceStationTokens.dotBlue
        let billColor = VoiceStationTokens.duckOrange
        let billDeep = VoiceStationTokens.duckOrangeDeep

        if turn != 0.0 {
            let clampedTurn = max(-14.0, min(14.0, turn))
            let shiftX = clampedTurn * 0.15
            ctx.translateBy(x: shiftX, y: 0)
            ctx.translateBy(x: 62, y: 44)
            ctx.rotate(by: Angle(degrees: clampedTurn * 0.95))
            ctx.translateBy(x: -62, y: -44)
        }

        // 1. Rounded TV helmet shell
        var shellPath = Path()
        shellPath.move(to: CGPoint(x: 32, y: 58))
        shellPath.addLine(to: CGPoint(x: 32, y: 36))
        shellPath.addCurve(to: CGPoint(x: 50, y: 20), control1: CGPoint(x: 32, y: 26), control2: CGPoint(x: 40, y: 20))
        shellPath.addLine(to: CGPoint(x: 74, y: 20))
        shellPath.addCurve(to: CGPoint(x: 92, y: 36), control1: CGPoint(x: 84, y: 20), control2: CGPoint(x: 92, y: 26))
        shellPath.addLine(to: CGPoint(x: 92, y: 58))
        shellPath.closeSubpath()
        ctx.fill(shellPath, with: .color(shellColor))
        ctx.stroke(shellPath, with: .color(frameColor), lineWidth: 1.4)

        // Visor plate
        ctx.fill(
            Path(roundedRect: CGRect(x: 37, y: 25, width: 50, height: 29), cornerRadius: 11),
            with: .color(shadeColor.opacity(0.32))
        )

        // Forehead shine
        var shinePath = Path()
        shinePath.move(to: CGPoint(x: 44, y: 23))
        shinePath.addCurve(to: CGPoint(x: 66, y: 21.3), control1: CGPoint(x: 50, y: 21.5), control2: CGPoint(x: 58, y: 21))
        ctx.stroke(shinePath, with: .color(Color.white.opacity(0.75)), lineWidth: 2)

        // Side orange ear brackets with metallic pin
        let leftEar = CGRect(x: 29.0, y: 44.5, width: 4.0, height: 11.0)
        let rightEar = CGRect(x: 91.0, y: 44.5, width: 4.0, height: 11.0)
        ctx.fill(Path(roundedRect: leftEar, cornerRadius: 1.8), with: .color(billColor))
        ctx.fill(Path(roundedRect: rightEar, cornerRadius: 1.8), with: .color(billColor))
        ctx.fill(Path(ellipseIn: CGRect(x: 30.1, y: 48.8, width: 1.8, height: 1.8)), with: .color(silverColor))
        ctx.fill(Path(ellipseIn: CGRect(x: 92.1, y: 48.8, width: 1.8, height: 1.8)), with: .color(silverColor))

        // 2. Center Camera Eye (Awake, Drowsy, or Golden Horizontal Sleep Line "—")
        let eyeX: Double = 62.0
        let eyeY: Double = 38.8
        if isSleeping {
            // Peaceful golden horizontal sleeping eye bar ("—") exactly as in approved mockup
            let sleepBar = CGRect(x: eyeX - 8.5, y: eyeY - 1.6, width: 17.0, height: 3.2)
            ctx.fill(Path(roundedRect: sleepBar, cornerRadius: 1.6), with: .color(eyeColor))

            // Coral cheek LED in sleep (#FF6B6B)
            let coralColor = VoiceStationTokens.sleepRed
            ctx.fill(
                Path(ellipseIn: CGRect(x: 43.5, y: 44.0, width: 3.5, height: 3.5)),
                with: .color(coralColor)
            )
        } else {
            // Awake Camera Eye
            ctx.fill(Path(ellipseIn: CGRect(x: eyeX - 11.0, y: eyeY - 10.8, width: 22.0, height: 22.0)), with: .color(eyeColor))
            ctx.fill(Path(ellipseIn: CGRect(x: eyeX - 7.5, y: eyeY - 7.3, width: 15.0, height: 15.0)), with: .color(frameColor))

            let shiftEyeX = max(-2.0, min(2.0, eyeOffsetX))
            let shiftEyeY = max(-2.0, min(2.0, eyeOffsetY))
            let highlightRect = CGRect(
                x: eyeX - 3.7 + shiftEyeX * 0.6,
                y: eyeY - 3.5 + shiftEyeY * 0.6,
                width: 7.4,
                height: 7.4
            )
            ctx.fill(Path(ellipseIn: highlightRect), with: .color(micHigh))

            let pupilRect = CGRect(
                x: eyeX - 1.8 + shiftEyeX,
                y: eyeY - 1.8 + shiftEyeY,
                width: 3.6,
                height: 3.6
            )
            ctx.fill(Path(ellipseIn: pupilRect), with: .color(dotColor))
            // Specular glint
            ctx.fill(
                Path(ellipseIn: CGRect(x: eyeX + 1.2 + shiftEyeX * 0.4, y: eyeY - 5.0 + shiftEyeY * 0.4, width: 2.0, height: 2.0)),
                with: .color(Color.white.opacity(0.9))
            )

            // Drowsy upper golden eyelid (when nodding off before sleep)
            if drowsy > 0.05 {
                let lidHeight = min(13.0, drowsy * 11.5)
                let lidRect = CGRect(x: eyeX - 7.5, y: eyeY - 7.3, width: 15.0, height: lidHeight)
                ctx.fill(Path(roundedRect: lidRect, cornerRadius: 3.0), with: .color(eyeColor))
            }

            // State LED (left cheek)
            ctx.fill(Path(ellipseIn: CGRect(x: 43.5, y: 44.0, width: 3.5, height: 3.5)), with: .color(ledColor))
        }

        // Sensor slot (right cheek)
        ctx.fill(Path(roundedRect: CGRect(x: 77, y: 37.8, width: 5, height: 2.4), cornerRadius: 1.2), with: .color(frameColor))

        // 3. Articulated Beak with 3D Inner Mouth Plate and 3-Dot Jaw Hinges
        let clampedDrop = max(0.0, min(14.0, jawDrop))
        if clampedDrop > 0.4 {
            // Dark acoustic mouth cavity + 3D inner orange tongue/plate
            let cavityRect = CGRect(x: 35.0, y: 58.5, width: 54.0, height: 4.5 + clampedDrop)
            ctx.fill(Path(roundedRect: cavityRect, cornerRadius: 2.5), with: .color(frameColor))
            let innerPlateRect = CGRect(
                x: 41.0,
                y: 60.0 + clampedDrop * 0.22,
                width: 42.0,
                height: max(2.2, clampedDrop * 0.55)
            )
            ctx.fill(Path(roundedRect: innerPlateRect, cornerRadius: 1.5), with: .color(billDeep))
        } else {
            ctx.fill(Path(roundedRect: CGRect(x: 35, y: 59, width: 54, height: 5), cornerRadius: 2), with: .color(frameColor))
        }

        // Upper bill
        var billPath = Path()
        billPath.move(to: CGPoint(x: 31.5, y: 56))
        billPath.addLine(to: CGPoint(x: 92.5, y: 56))
        billPath.addLine(to: CGPoint(x: 92.5, y: 59.5))
        billPath.addQuadCurve(to: CGPoint(x: 90, y: 62), control: CGPoint(x: 92.5, y: 62))
        billPath.addLine(to: CGPoint(x: 34, y: 62))
        billPath.addQuadCurve(to: CGPoint(x: 31.5, y: 59.5), control: CGPoint(x: 31.5, y: 62))
        billPath.closeSubpath()
        ctx.fill(billPath, with: .color(billColor))

        // 3-dot MD-01 hinge detail on left and right corners of upper bill
        for hx in [34.5, 36.8, 39.1, 84.9, 87.2, 89.5] {
            ctx.fill(Path(ellipseIn: CGRect(x: hx - 0.7, y: 58.3, width: 1.4, height: 1.4)), with: .color(frameColor.opacity(0.75)))
        }

        // Lower jaw (drops with speech level or quack)
        var jawPath = Path()
        jawPath.move(to: CGPoint(x: 34, y: 62 + clampedDrop))
        jawPath.addLine(to: CGPoint(x: 90, y: 62 + clampedDrop))
        jawPath.addLine(to: CGPoint(x: 88.5, y: 65 + clampedDrop))
        jawPath.addQuadCurve(to: CGPoint(x: 86.5, y: 66 + clampedDrop), control: CGPoint(x: 88, y: 66 + clampedDrop))
        jawPath.addLine(to: CGPoint(x: 37.5, y: 66 + clampedDrop))
        jawPath.addQuadCurve(to: CGPoint(x: 35.5, y: 65 + clampedDrop), control: CGPoint(x: 36, y: 66 + clampedDrop))
        jawPath.closeSubpath()
        ctx.fill(jawPath, with: .color(billDeep))
    }

    // MARK: - Classic Duck Preserved in Reserve (.classicReserve)

    private func drawClassicStandingDuck(context: GraphicsContext, pose: DuckPose) {
        let hopFactor = max(0.0, min(1.0, pose.hopY / 10.0))
        let shadowWidth = 64.0 - hopFactor * 14.0
        let shadowHeight = 8.0 - hopFactor * 2.0
        let shadowRect = CGRect(
            x: MicroduckKinematics.rx - shadowWidth / 2.0,
            y: (MicroduckKinematics.ground + 1.0) - shadowHeight / 2.0,
            width: shadowWidth,
            height: shadowHeight
        )
        context.fill(Path(ellipseIn: shadowRect), with: .color(Color.black.opacity(max(0.15, 0.35 - hopFactor * 0.15))))

        let hipY = MicroduckKinematics.hipY(pose: pose) - pose.hopY

        context.drawLayer { ctx in
            ctx.translateBy(x: MicroduckKinematics.rx - 13, y: hipY)
            drawClassicFrontLeg(ctx: ctx, thighAngle: pose.tF, kneeAngle: pose.kF)
        }
        context.drawLayer { ctx in
            ctx.translateBy(x: MicroduckKinematics.rx + 13, y: hipY)
            drawClassicFrontLeg(ctx: ctx, thighAngle: pose.tB, kneeAngle: pose.kB)
        }

        context.drawLayer { ctx in
            ctx.translateBy(x: MicroduckKinematics.rx, y: hipY)
            ctx.rotate(by: Angle(degrees: pose.body))
            drawClassicTorso(ctx: ctx, isFrontView: true)

            ctx.translateBy(x: 0, y: -36)
            let neckAngle = (pose.n.count > 0 ? pose.n[0] : 0) + (pose.n.count > 1 ? pose.n[1] * 0.5 : 0)
            ctx.rotate(by: Angle(degrees: neckAngle))
            drawClassicNeckSegment(ctx: ctx)

            ctx.translateBy(x: 0, y: -10)
            ctx.rotate(by: Angle(degrees: pose.head))
            ctx.scaleBy(x: 1.15, y: 1.15)
            ctx.translateBy(x: -62.0, y: -60)
            drawClassicHead(
                ctx: ctx,
                isSideView: false,
                jawDrop: pose.jaw * 16.0,
                turn: pose.turn,
                isSleeping: pose.isSleeping,
                eyeOffsetX: pose.eyeOffsetX,
                eyeOffsetY: pose.eyeOffsetY
            )
        }
    }

    private func drawClassicSittingDuck(context: GraphicsContext, pose: DuckPose) {
        let frameColor = VoiceStationTokens.navy
        let metalColor = VoiceStationTokens.micHighlight
        let shellColor = VoiceStationTokens.inputCream
        let shadeColor = VoiceStationTokens.panelHeader
        let dotColor = VoiceStationTokens.dotBlue
        let billColor = VoiceStationTokens.duckOrange
        let soleColor = VoiceStationTokens.gold

        let groundY = MicroduckKinematics.ground
        let cx = MicroduckKinematics.rx

        let wPhase = pose.footWiggle
        let leftSway = sin(wPhase)
        let rightSway = sin(wPhase - 0.35)

        let shadowRect = CGRect(x: cx - 44, y: groundY - 2, width: 88, height: 9.5)
        context.fill(Path(ellipseIn: shadowRect), with: .color(Color.black.opacity(0.38)))

        context.drawLayer { ctx in
            ctx.translateBy(x: cx - 30, y: groundY - 14)
            ctx.rotate(by: Angle(degrees: -22 + leftSway * 1.5))
            ctx.fill(Path(roundedRect: CGRect(x: -6, y: -4, width: 12, height: 14), cornerRadius: 3), with: .color(frameColor))
            ctx.fill(Path(ellipseIn: CGRect(x: -3, y: -2, width: 6, height: 6)), with: .color(metalColor))
            ctx.fill(Path(roundedRect: CGRect(x: -8, y: -2, width: 16, height: 18), cornerRadius: 5), with: .color(shellColor))
            ctx.fill(Path(roundedRect: CGRect(x: -8, y: -2, width: 5, height: 18), cornerRadius: 3), with: .color(shadeColor.opacity(0.35)))
        }

        context.drawLayer { ctx in
            ctx.translateBy(x: cx + 30, y: groundY - 14)
            ctx.rotate(by: Angle(degrees: 22 + rightSway * 1.5))
            ctx.fill(Path(roundedRect: CGRect(x: -6, y: -4, width: 12, height: 14), cornerRadius: 3), with: .color(frameColor))
            ctx.fill(Path(ellipseIn: CGRect(x: -3, y: -2, width: 6, height: 6)), with: .color(metalColor))
            ctx.fill(Path(roundedRect: CGRect(x: -8, y: -2, width: 16, height: 18), cornerRadius: 5), with: .color(shellColor))
            ctx.fill(Path(roundedRect: CGRect(x: 3, y: -2, width: 5, height: 18), cornerRadius: 3), with: .color(shadeColor.opacity(0.35)))
        }

        let pelvisY = groundY - 18
        context.fill(Path(roundedRect: CGRect(x: cx - 24, y: pelvisY, width: 48, height: 14), cornerRadius: 4), with: .color(frameColor))
        context.fill(Path(ellipseIn: CGRect(x: cx - 15, y: pelvisY + 3.5, width: 6, height: 6)), with: .color(metalColor))
        context.fill(Path(ellipseIn: CGRect(x: cx + 9, y: pelvisY + 3.5, width: 6, height: 6)), with: .color(metalColor))

        let torsoY = pelvisY - 30
        context.fill(Path(roundedRect: CGRect(x: cx - 23, y: torsoY, width: 46, height: 32), cornerRadius: 10), with: .color(shellColor))
        context.fill(Path(roundedRect: CGRect(x: cx + 11, y: torsoY, width: 12, height: 32), cornerRadius: 6), with: .color(shadeColor.opacity(0.35)))

        let brandText = Text("SB").font(.system(size: 9.0, weight: .heavy, design: .monospaced)).foregroundColor(frameColor)
            + Text("dot").font(.system(size: 4.8, weight: .black, design: .monospaced)).foregroundColor(dotColor).baselineOffset(4.5)
        context.draw(brandText, at: CGPoint(x: cx - 6.0, y: torsoY + 15), anchor: .center)

        context.fill(Path(ellipseIn: CGRect(x: cx - 6.0 + 18.0 - 2.3, y: torsoY + 7.0 - 2.3, width: 4.6, height: 4.6)), with: .color(dotColor))

        let leftX = (cx - 24.0) + leftSway * 5.0
        let leftY = groundY - 12.0 - abs(leftSway) * 2.5
        let leftAngle = -24.0 + leftSway * 14.0

        let rightX = (cx + 24.0) + rightSway * 5.0
        let rightY = groundY - 12.0 - abs(rightSway) * 2.5
        let rightAngle = 24.0 + rightSway * 14.0

        context.drawLayer { ctx in
            ctx.translateBy(x: leftX, y: leftY)
            ctx.rotate(by: Angle(degrees: leftAngle))

            let footRect = CGRect(x: -8.5, y: -9, width: 17, height: 21)
            ctx.fill(Path(roundedRect: footRect, cornerRadius: 5.5), with: .color(billColor))

            let soleRect = CGRect(x: -8.5, y: 7, width: 17, height: 5)
            ctx.fill(Path(roundedRect: soleRect, cornerRadius: 2.5), with: .color(soleColor))

            ctx.fill(Path(ellipseIn: CGRect(x: -2.5, y: -7.5, width: 5, height: 5)), with: .color(frameColor))
            ctx.fill(Path(ellipseIn: CGRect(x: -1.2, y: -6.2, width: 2.4, height: 2.4)), with: .color(metalColor))
        }

        context.drawLayer { ctx in
            ctx.translateBy(x: rightX, y: rightY)
            ctx.rotate(by: Angle(degrees: rightAngle))

            let footRect = CGRect(x: -8.5, y: -9, width: 17, height: 21)
            ctx.fill(Path(roundedRect: footRect, cornerRadius: 5.5), with: .color(billColor))

            let soleRect = CGRect(x: -8.5, y: 7, width: 17, height: 5)
            ctx.fill(Path(roundedRect: soleRect, cornerRadius: 2.5), with: .color(soleColor))

            ctx.fill(Path(ellipseIn: CGRect(x: -2.5, y: -7.5, width: 5, height: 5)), with: .color(frameColor))
            ctx.fill(Path(ellipseIn: CGRect(x: -1.2, y: -6.2, width: 2.4, height: 2.4)), with: .color(metalColor))
        }

        context.drawLayer { ctx in
            ctx.translateBy(x: cx, y: torsoY)
            ctx.rotate(by: Angle(degrees: pose.body))

            ctx.translateBy(x: 0, y: -2)
            let neckAngle = (pose.n.count > 0 ? pose.n[0] : 0) + (pose.n.count > 1 ? pose.n[1] * 0.5 : 0)
            ctx.rotate(by: Angle(degrees: neckAngle))
            drawClassicNeckSegment(ctx: ctx)

            ctx.translateBy(x: 0, y: -10)
            ctx.rotate(by: Angle(degrees: pose.head))
            ctx.scaleBy(x: 1.15, y: 1.15)
            ctx.translateBy(x: -62.0, y: -60)
            drawClassicHead(
                ctx: ctx,
                isSideView: false,
                jawDrop: pose.jaw * 16.0,
                turn: pose.turn,
                isSleeping: pose.isSleeping,
                eyeOffsetX: pose.eyeOffsetX,
                eyeOffsetY: pose.eyeOffsetY
            )
        }
    }

    private func drawClassicNeckSegment(ctx: GraphicsContext) {
        let frameColor = VoiceStationTokens.navy
        let metalColor = VoiceStationTokens.micHighlight
        let rect = CGRect(x: -6, y: -11, width: 12, height: 13)
        ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(frameColor))
        let pin = CGRect(x: -2, y: -7, width: 4, height: 4)
        ctx.fill(Path(ellipseIn: pin), with: .color(metalColor))
    }

    private func drawClassicTorso(ctx: GraphicsContext, isFrontView: Bool) {
        let frameColor = VoiceStationTokens.navy
        let metalColor = VoiceStationTokens.micHighlight
        let shellColor = VoiceStationTokens.inputCream
        let shadeColor = VoiceStationTokens.panelHeader
        let dotColor = VoiceStationTokens.dotBlue

        if isFrontView {
            ctx.fill(Path(roundedRect: CGRect(x: -24, y: -8, width: 48, height: 12), cornerRadius: 4), with: .color(frameColor))
            ctx.fill(Path(ellipseIn: CGRect(x: -16, y: -4.6, width: 5.2, height: 5.2)), with: .color(metalColor))
            ctx.fill(Path(ellipseIn: CGRect(x: 10.8, y: -4.6, width: 5.2, height: 5.2)), with: .color(metalColor))

            ctx.fill(Path(roundedRect: CGRect(x: -23, y: -38, width: 46, height: 32), cornerRadius: 10), with: .color(shellColor))
            ctx.fill(Path(roundedRect: CGRect(x: 11, y: -38, width: 12, height: 32), cornerRadius: 6), with: .color(shadeColor.opacity(0.35)))

            let brandText = Text("SB").font(.system(size: 9.0, weight: .heavy, design: .monospaced)).foregroundColor(frameColor)
                + Text("dot").font(.system(size: 4.8, weight: .black, design: .monospaced)).foregroundColor(dotColor).baselineOffset(4.5)
            ctx.draw(brandText, at: CGPoint(x: -6.0, y: -20), anchor: .center)

            ctx.fill(Path(ellipseIn: CGRect(x: -6.0 + 18.0 - 2.3, y: -28.0 - 2.3, width: 4.6, height: 4.6)), with: .color(dotColor))
        } else {
            ctx.fill(Path(roundedRect: CGRect(x: -20, y: -8, width: 40, height: 12), cornerRadius: 4), with: .color(frameColor))
            ctx.fill(Path(ellipseIn: CGRect(x: -11.6, y: -4.6, width: 5.2, height: 5.2)), with: .color(metalColor))
            ctx.fill(Path(ellipseIn: CGRect(x: 6.4, y: -4.6, width: 5.2, height: 5.2)), with: .color(metalColor))

            ctx.fill(Path(roundedRect: CGRect(x: -23, y: -38, width: 46, height: 32), cornerRadius: 10), with: .color(shellColor))
            ctx.fill(Path(roundedRect: CGRect(x: -23, y: -38, width: 14, height: 32), cornerRadius: 7), with: .color(shadeColor.opacity(0.45)))
            ctx.fill(Path(ellipseIn: CGRect(x: 10.8, y: -31.2, width: 4.4, height: 4.4)), with: .color(dotColor))

            let brandText = Text("SB").font(.system(size: 8.5, weight: .heavy, design: .monospaced)).foregroundColor(frameColor)
                + Text("dot").font(.system(size: 4.5, weight: .black, design: .monospaced)).foregroundColor(dotColor).baselineOffset(4.0)
            ctx.draw(brandText, at: CGPoint(x: 0, y: -20), anchor: .center)
        }
    }

    private func drawClassicFrontLeg(ctx: GraphicsContext, thighAngle: Double, kneeAngle: Double) {
        let frameColor = VoiceStationTokens.navy
        let metalColor = VoiceStationTokens.micHighlight
        let billColor = VoiceStationTokens.duckOrange
        let soleColor = VoiceStationTokens.gold
        let shellColor = VoiceStationTokens.inputCream

        ctx.drawLayer { thighCtx in
            thighCtx.rotate(by: Angle(degrees: thighAngle))
            thighCtx.fill(Path(roundedRect: CGRect(x: -6, y: -2, width: 12, height: 18), cornerRadius: 3.5), with: .color(frameColor))
            thighCtx.fill(Path(roundedRect: CGRect(x: -8, y: 0, width: 4, height: 15), cornerRadius: 2), with: .color(shellColor))
            thighCtx.fill(Path(ellipseIn: CGRect(x: -3, y: -2.5, width: 6, height: 6)), with: .color(metalColor))

            thighCtx.drawLayer { kneeCtx in
                kneeCtx.translateBy(x: 0, y: MicroduckKinematics.thigh)
                kneeCtx.rotate(by: Angle(degrees: kneeAngle))

                kneeCtx.fill(Path(roundedRect: CGRect(x: -5.5, y: -2, width: 11, height: 17), cornerRadius: 3), with: .color(frameColor))
                kneeCtx.fill(Path(ellipseIn: CGRect(x: -2.7, y: -2.2, width: 5.4, height: 5.4)), with: .color(metalColor))

                kneeCtx.drawLayer { footCtx in
                    footCtx.translateBy(x: 0, y: MicroduckKinematics.shin)
                    footCtx.rotate(by: Angle(degrees: -(thighAngle + kneeAngle)))

                    footCtx.fill(Path(roundedRect: CGRect(x: -11, y: 0, width: 22, height: 11), cornerRadius: 4), with: .color(billColor))
                    footCtx.fill(Path(roundedRect: CGRect(x: -11, y: 7.5, width: 22, height: 4), cornerRadius: 2), with: .color(soleColor))
                    footCtx.fill(Path(roundedRect: CGRect(x: -0.8, y: 2, width: 1.6, height: 5.5), cornerRadius: 0.8), with: .color(frameColor.opacity(0.35)))
                }
            }
        }
    }

    private func drawClassicHead(
        ctx: GraphicsContext,
        isSideView: Bool,
        jawDrop: Double,
        turn: Double = 0.0,
        isSleeping: Bool = false,
        eyeOffsetX: Double = 0.0,
        eyeOffsetY: Double = 0.0
    ) {
        var ctx = ctx
        let shellColor = VoiceStationTokens.inputCream
        let shadeColor = VoiceStationTokens.panelHeader
        let frameColor = VoiceStationTokens.navy
        let eyeColor = VoiceStationTokens.gold
        let micHigh = VoiceStationTokens.micHighlight
        let dotColor = VoiceStationTokens.dotBlue
        let billColor = VoiceStationTokens.duckOrange
        let billDeep = VoiceStationTokens.duckOrangeDeep

        if turn != 0.0 {
            let clampedTurn = max(-14.0, min(14.0, turn))
            let shiftX = clampedTurn * 0.15
            ctx.translateBy(x: shiftX, y: 0)
            ctx.translateBy(x: 62, y: 44)
            ctx.rotate(by: Angle(degrees: clampedTurn * 0.95))
            ctx.translateBy(x: -62, y: -44)
        }

        var shellPath = Path()
        shellPath.move(to: CGPoint(x: 32, y: 58))
        shellPath.addLine(to: CGPoint(x: 32, y: 36))
        shellPath.addCurve(to: CGPoint(x: 50, y: 20), control1: CGPoint(x: 32, y: 26), control2: CGPoint(x: 40, y: 20))
        shellPath.addLine(to: CGPoint(x: 74, y: 20))
        shellPath.addCurve(to: CGPoint(x: 92, y: 36), control1: CGPoint(x: 84, y: 20), control2: CGPoint(x: 92, y: 26))
        shellPath.addLine(to: CGPoint(x: 92, y: 58))
        shellPath.closeSubpath()
        ctx.fill(shellPath, with: .color(shellColor))

        ctx.fill(Path(roundedRect: CGRect(x: 37, y: 25, width: 50, height: 29), cornerRadius: 11), with: .color(shadeColor.opacity(0.32)))

        var shinePath = Path()
        shinePath.move(to: CGPoint(x: 44, y: 23))
        shinePath.addCurve(to: CGPoint(x: 66, y: 21.3), control1: CGPoint(x: 50, y: 21.5), control2: CGPoint(x: 58, y: 21))
        ctx.stroke(shinePath, with: .color(Color.white.opacity(0.7)), lineWidth: 2)

        ctx.fill(Path(roundedRect: CGRect(x: 29.5, y: 46, width: 3.5, height: 10), cornerRadius: 1.75), with: .color(billColor))
        ctx.fill(Path(roundedRect: CGRect(x: 91, y: 46, width: 3.5, height: 10), cornerRadius: 1.75), with: .color(billColor))

        if isSleeping {
            let eyeX: Double = 62.0
            let eyeY: Double = 38.8
            let sleepBar = CGRect(x: eyeX - 8.5, y: eyeY - 1.6, width: 17.0, height: 3.2)
            ctx.fill(Path(roundedRect: sleepBar, cornerRadius: 1.6), with: .color(eyeColor))
            ctx.fill(Path(ellipseIn: CGRect(x: 43.5, y: 44, width: 3.5, height: 3.5)), with: .color(VoiceStationTokens.sleepRed))
        } else {
            ctx.fill(Path(ellipseIn: CGRect(x: 51, y: 28, width: 22, height: 22)), with: .color(eyeColor))
            ctx.fill(Path(ellipseIn: CGRect(x: 55, y: 32, width: 14, height: 14)), with: .color(frameColor))

            let shiftEyeX = max(-2.0, min(2.0, eyeOffsetX))
            let shiftEyeY = max(-2.0, min(2.0, eyeOffsetY))
            let highlightRect = CGRect(x: 58.3 + shiftEyeX * 0.6, y: 35.3 + shiftEyeY * 0.6, width: 7.4, height: 7.4)
            ctx.fill(Path(ellipseIn: highlightRect), with: .color(micHigh))

            let pupilRect = CGRect(x: 57.8 + shiftEyeX, y: 34.8 + shiftEyeY, width: 3.4, height: 3.4)
            ctx.fill(Path(ellipseIn: pupilRect), with: .color(dotColor))
            ctx.fill(Path(ellipseIn: CGRect(x: 43.5, y: 44, width: 3.5, height: 3.5)), with: .color(ledColor))
        }

        ctx.fill(Path(roundedRect: CGRect(x: 77, y: 37.8, width: 5, height: 2.4), cornerRadius: 1.2), with: .color(frameColor))
        ctx.fill(Path(roundedRect: CGRect(x: 35, y: 59, width: 54, height: 5), cornerRadius: 2), with: .color(frameColor))

        var billPath = Path()
        billPath.move(to: CGPoint(x: 31.5, y: 56))
        billPath.addLine(to: CGPoint(x: 92.5, y: 56))
        billPath.addLine(to: CGPoint(x: 92.5, y: 59.5))
        billPath.addQuadCurve(to: CGPoint(x: 90, y: 62), control: CGPoint(x: 92.5, y: 62))
        billPath.addLine(to: CGPoint(x: 34, y: 62))
        billPath.addQuadCurve(to: CGPoint(x: 31.5, y: 59.5), control: CGPoint(x: 31.5, y: 62))
        billPath.closeSubpath()
        ctx.fill(billPath, with: .color(billColor))

        var jawPath = Path()
        jawPath.move(to: CGPoint(x: 34, y: 62 + jawDrop))
        jawPath.addLine(to: CGPoint(x: 90, y: 62 + jawDrop))
        jawPath.addLine(to: CGPoint(x: 88.5, y: 65 + jawDrop))
        jawPath.addQuadCurve(to: CGPoint(x: 86.5, y: 66 + jawDrop), control: CGPoint(x: 88, y: 66 + jawDrop))
        jawPath.addLine(to: CGPoint(x: 37.5, y: 66 + jawDrop))
        jawPath.addQuadCurve(to: CGPoint(x: 35.5, y: 65 + jawDrop), control: CGPoint(x: 36, y: 66 + jawDrop))
        jawPath.closeSubpath()
        ctx.fill(jawPath, with: .color(billDeep))
    }
}
