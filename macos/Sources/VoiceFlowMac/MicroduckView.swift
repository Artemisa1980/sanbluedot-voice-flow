import SwiftUI
import VoiceFlowMacCore

// MARK: - Microduck Mascot Poses (Newton robot rig: Standing & Sitting per owner direction)

public struct DuckPose: Equatable, Sendable {
    public var tF: Double   // Thigh Front angle
    public var kF: Double   // Knee Front angle
    public var tB: Double   // Thigh Back angle
    public var kB: Double   // Knee Back angle
    public var body: Double // Body angle
    public var n: [Double]  // Neck 3-link angles [n0, n1, n2]
    public var head: Double // Head angle (negative = head high / looking up)
    public var jaw: Double  // Jaw drop factor (0.0 to 1.0)
    public var isSideView: Bool // false = front facing (per owner instruction)
    public var isSitting: Bool  // true = sitting pose (when recording per owner instruction)
    public var footWiggle: Double // Foot wiggle phase for playful kid-like swinging

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
            footWiggle: footWiggle + (target.footWiggle - footWiggle) * f
        )
    }
}

public enum MicroduckKinematics {
    public static let ground: Double = 188.0
    public static let rx: Double = 78.0
    public static let thigh: Double = 16.0
    public static let shin: Double = 16.0
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

    public init(pose: DuckPose, audioLevel: Float, ledColor: Color) {
        self.pose = pose
        self.audioLevel = audioLevel
        self.ledColor = ledColor
    }

    // Geometry box 170 × 200, scaled into 60 × 82 pt
    public var body: some View {
        Canvas { context, size in
            let scaleX = size.width / 170.0
            let scaleY = size.height / 200.0
            context.scaleBy(x: scaleX, y: scaleY)

            if pose.isSitting {
                drawSittingDuck(context: context, pose: pose)
            } else {
                drawStandingDuck(context: context, pose: pose)
            }
        }
        .frame(width: HUDLayout.duckWidth, height: HUDLayout.duckHeight)
    }

    // MARK: - Standing Duck (Parado: when not recording, completed or error)
    private func drawStandingDuck(context: GraphicsContext, pose: DuckPose) {
        let shadowRect = CGRect(x: MicroduckKinematics.rx - 32, y: MicroduckKinematics.ground + 1 - 4, width: 64, height: 8)
        context.fill(Path(ellipseIn: shadowRect), with: .color(Color.black.opacity(0.35)))

        let hipY = MicroduckKinematics.hipY(pose: pose)

        // Left standing leg
        context.drawLayer { ctx in
            ctx.translateBy(x: MicroduckKinematics.rx - 13, y: hipY)
            drawFrontLeg(ctx: ctx, thighAngle: pose.tF, kneeAngle: pose.kF)
        }
        // Right standing leg
        context.drawLayer { ctx in
            ctx.translateBy(x: MicroduckKinematics.rx + 13, y: hipY)
            drawFrontLeg(ctx: ctx, thighAngle: pose.tB, kneeAngle: pose.kB)
        }

        // Torso and Neck
        context.drawLayer { ctx in
            ctx.translateBy(x: MicroduckKinematics.rx, y: hipY)
            ctx.rotate(by: Angle(degrees: pose.body))
            drawTorso(ctx: ctx, isFrontView: true)

            // Neck Link (compact single joint reduced by 2 sizes)
            ctx.translateBy(x: 0, y: -36)
            let neckAngle = (pose.n.count > 0 ? pose.n[0] : 0) + (pose.n.count > 1 ? pose.n[1] * 0.5 : 0)
            ctx.rotate(by: Angle(degrees: neckAngle))
            drawNeckSegment(ctx: ctx)

            // Head (centered, head high)
            ctx.translateBy(x: 0, y: -10)
            ctx.rotate(by: Angle(degrees: pose.head))
            ctx.scaleBy(x: 1.15, y: 1.15)
            ctx.translateBy(x: -62.0, y: -60)
            drawHead(ctx: ctx, isSideView: false, jawDrop: pose.jaw * 16.0)
        }
    }

    // MARK: - Sitting Duck (Sentado: "patitas abiertas" + foot swinging like a kid)
    private func drawSittingDuck(context: GraphicsContext, pose: DuckPose) {
        let frameColor = VoiceStationTokens.navy
        let metalColor = VoiceStationTokens.micHighlight
        let shellColor = VoiceStationTokens.inputCream
        let shadeColor = VoiceStationTokens.panelHeader
        let dotColor = VoiceStationTokens.dotBlue
        let billColor = VoiceStationTokens.duckOrange
        let soleColor = VoiceStationTokens.gold

        let groundY = MicroduckKinematics.ground
        let cx = MicroduckKinematics.rx

        // Active foot swinging motion ("de un lado al otro" like a kid playing)
        let wPhase = pose.footWiggle
        let leftSway = sin(wPhase)
        let rightSway = sin(wPhase - 0.35)

        // 1. Wide Ground Shadow under seated body and folded feet
        let shadowRect = CGRect(x: cx - 44, y: groundY - 2, width: 88, height: 9.5)
        context.fill(Path(ellipseIn: shadowRect), with: .color(Color.black.opacity(0.38)))

        // 2. White outer thigh stabilizers folded back on the sides (from photo 2)
        // Left thigh stabilizer
        context.drawLayer { ctx in
            ctx.translateBy(x: cx - 30, y: groundY - 14)
            ctx.rotate(by: Angle(degrees: -22 + leftSway * 1.5))
            ctx.fill(Path(roundedRect: CGRect(x: -6, y: -4, width: 12, height: 14), cornerRadius: 3), with: .color(frameColor))
            ctx.fill(Path(ellipseIn: CGRect(x: -3, y: -2, width: 6, height: 6)), with: .color(metalColor))
            ctx.fill(Path(roundedRect: CGRect(x: -8, y: -2, width: 16, height: 18), cornerRadius: 5), with: .color(shellColor))
            ctx.fill(Path(roundedRect: CGRect(x: -8, y: -2, width: 5, height: 18), cornerRadius: 3), with: .color(shadeColor.opacity(0.35)))
        }

        // Right thigh stabilizer
        context.drawLayer { ctx in
            ctx.translateBy(x: cx + 30, y: groundY - 14)
            ctx.rotate(by: Angle(degrees: 22 + rightSway * 1.5))
            ctx.fill(Path(roundedRect: CGRect(x: -6, y: -4, width: 12, height: 14), cornerRadius: 3), with: .color(frameColor))
            ctx.fill(Path(ellipseIn: CGRect(x: -3, y: -2, width: 6, height: 6)), with: .color(metalColor))
            ctx.fill(Path(roundedRect: CGRect(x: -8, y: -2, width: 16, height: 18), cornerRadius: 5), with: .color(shellColor))
            ctx.fill(Path(roundedRect: CGRect(x: 3, y: -2, width: 5, height: 18), cornerRadius: 3), with: .color(shadeColor.opacity(0.35)))
        }

        // 3. Pelvis resting low
        let pelvisY = groundY - 18
        context.fill(Path(roundedRect: CGRect(x: cx - 24, y: pelvisY, width: 48, height: 14), cornerRadius: 4), with: .color(frameColor))
        context.fill(Path(ellipseIn: CGRect(x: cx - 15, y: pelvisY + 3.5, width: 6, height: 6)), with: .color(metalColor))
        context.fill(Path(ellipseIn: CGRect(x: cx + 9, y: pelvisY + 3.5, width: 6, height: 6)), with: .color(metalColor))

        // 4. White Torso Shell sitting proudly with "SBᵈᵒᵗ"
        let torsoY = pelvisY - 30
        context.fill(Path(roundedRect: CGRect(x: cx - 23, y: torsoY, width: 46, height: 32), cornerRadius: 10), with: .color(shellColor))
        context.fill(Path(roundedRect: CGRect(x: cx + 11, y: torsoY, width: 12, height: 32), cornerRadius: 6), with: .color(shadeColor.opacity(0.35)))

        // Chest letters: "SBᵈᵒᵗ" (SB heavy monospaced + dot superscript in dotBlue)
        let brandText = Text("SB").font(.system(size: 9.0, weight: .heavy, design: .monospaced)).foregroundColor(frameColor)
            + Text("dot").font(.system(size: 4.8, weight: .black, design: .monospaced)).foregroundColor(dotColor).baselineOffset(4.5)
        context.draw(brandText, at: CGPoint(x: cx, y: torsoY + 14), anchor: .center)

        // 5. Two Orange Feet Splayed Open in Front ("patitas abiertas" + moving side to side like a child swinging feet)
        let leftX = (cx - 24.0) + leftSway * 5.0
        let leftY = groundY - 12.0 - abs(leftSway) * 2.5
        let leftAngle = -24.0 + leftSway * 14.0

        let rightX = (cx + 24.0) + rightSway * 5.0
        let rightY = groundY - 12.0 - abs(rightSway) * 2.5
        let rightAngle = 24.0 + rightSway * 14.0

        // Left foot (splayed out & swinging playfully from one side to the other)
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

        // Right foot (splayed out & swinging playfully from one side to the other)
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

        // 6. Articulated Neck Link rising from chest top (compact single joint reduced by 2 sizes)
        context.drawLayer { ctx in
            ctx.translateBy(x: cx, y: torsoY)
            ctx.rotate(by: Angle(degrees: pose.body))

            // Neck Link (compact single joint)
            ctx.translateBy(x: 0, y: -2)
            let neckAngle = (pose.n.count > 0 ? pose.n[0] : 0) + (pose.n.count > 1 ? pose.n[1] * 0.5 : 0)
            ctx.rotate(by: Angle(degrees: neckAngle))
            drawNeckSegment(ctx: ctx)

            // Head (sitting, looking up at Sandy with head high)
            ctx.translateBy(x: 0, y: -10)
            ctx.rotate(by: Angle(degrees: pose.head))
            ctx.scaleBy(x: 1.15, y: 1.15)
            ctx.translateBy(x: -62.0, y: -60)
            drawHead(ctx: ctx, isSideView: false, jawDrop: pose.jaw * 16.0)
        }
    }

    private func drawNeckSegment(ctx: GraphicsContext) {
        let frameColor = VoiceStationTokens.navy
        let metalColor = VoiceStationTokens.micHighlight
        let rect = CGRect(x: -6, y: -11, width: 12, height: 13)
        ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(frameColor))
        let pin = CGRect(x: -2, y: -7, width: 4, height: 4)
        ctx.fill(Path(ellipseIn: pin), with: .color(metalColor))
    }

    private func drawTorso(ctx: GraphicsContext, isFrontView: Bool) {
        let frameColor = VoiceStationTokens.navy
        let metalColor = VoiceStationTokens.micHighlight
        let shellColor = VoiceStationTokens.inputCream
        let shadeColor = VoiceStationTokens.panelHeader
        let dotColor = VoiceStationTokens.dotBlue

        if isFrontView {
            // Symmetrical front pelvis
            ctx.fill(Path(roundedRect: CGRect(x: -24, y: -8, width: 48, height: 12), cornerRadius: 4), with: .color(frameColor))
            ctx.fill(Path(ellipseIn: CGRect(x: -16, y: -4.6, width: 5.2, height: 5.2)), with: .color(metalColor))
            ctx.fill(Path(ellipseIn: CGRect(x: 10.8, y: -4.6, width: 5.2, height: 5.2)), with: .color(metalColor))

            // Front torso shell (centered)
            ctx.fill(Path(roundedRect: CGRect(x: -24, y: -38, width: 48, height: 32), cornerRadius: 10), with: .color(shellColor))
            // Subtle right side shading
            ctx.fill(Path(roundedRect: CGRect(x: 12, y: -38, width: 12, height: 32), cornerRadius: 7), with: .color(shadeColor.opacity(0.35)))

            // Center chest wordmark: "SBᵈᵒᵗ" (SB heavy monospaced + dot superscript in dotBlue)
            let brandText = Text("SB").font(.system(size: 9.0, weight: .heavy, design: .monospaced)).foregroundColor(frameColor)
                + Text("dot").font(.system(size: 4.8, weight: .black, design: .monospaced)).foregroundColor(dotColor).baselineOffset(4.5)
            ctx.draw(brandText, at: CGPoint(x: 0, y: -20), anchor: .center)
        } else {
            // Pelvis frame
            ctx.fill(Path(roundedRect: CGRect(x: -20, y: -8, width: 40, height: 12), cornerRadius: 4), with: .color(frameColor))
            ctx.fill(Path(ellipseIn: CGRect(x: -11.6, y: -4.6, width: 5.2, height: 5.2)), with: .color(metalColor))
            ctx.fill(Path(ellipseIn: CGRect(x: 6.4, y: -4.6, width: 5.2, height: 5.2)), with: .color(metalColor))

            // Torso shell
            ctx.fill(Path(roundedRect: CGRect(x: -23, y: -38, width: 46, height: 32), cornerRadius: 10), with: .color(shellColor))
            ctx.fill(Path(roundedRect: CGRect(x: -23, y: -38, width: 14, height: 32), cornerRadius: 7), with: .color(shadeColor.opacity(0.45)))
            ctx.fill(Path(ellipseIn: CGRect(x: 10.8, y: -31.2, width: 4.4, height: 4.4)), with: .color(dotColor))

            // Chest letters: "SBᵈᵒᵗ"
            let brandText = Text("SB").font(.system(size: 8.5, weight: .heavy, design: .monospaced)).foregroundColor(frameColor)
                + Text("dot").font(.system(size: 4.5, weight: .black, design: .monospaced)).foregroundColor(dotColor).baselineOffset(4.0)
            ctx.draw(brandText, at: CGPoint(x: 0, y: -20), anchor: .center)
        }
    }

    private func drawFrontLeg(ctx: GraphicsContext, thighAngle: Double, kneeAngle: Double) {
        let frameColor = VoiceStationTokens.navy
        let metalColor = VoiceStationTokens.micHighlight
        let billColor = VoiceStationTokens.duckOrange
        let soleColor = VoiceStationTokens.gold
        let shellColor = VoiceStationTokens.inputCream

        ctx.drawLayer { thighCtx in
            thighCtx.rotate(by: Angle(degrees: thighAngle))

            // Thigh (front)
            thighCtx.fill(Path(roundedRect: CGRect(x: -6, y: -2, width: 12, height: 18), cornerRadius: 3.5), with: .color(frameColor))
            // White outer thigh armor guard (matching Newton robot photos)
            thighCtx.fill(Path(roundedRect: CGRect(x: -8, y: 0, width: 4, height: 15), cornerRadius: 2), with: .color(shellColor))
            thighCtx.fill(Path(ellipseIn: CGRect(x: -3, y: -2.5, width: 6, height: 6)), with: .color(metalColor))

            // Knee
            thighCtx.drawLayer { kneeCtx in
                kneeCtx.translateBy(x: 0, y: MicroduckKinematics.thigh)
                kneeCtx.rotate(by: Angle(degrees: kneeAngle))

                kneeCtx.fill(Path(roundedRect: CGRect(x: -5.5, y: -2, width: 11, height: 17), cornerRadius: 3), with: .color(frameColor))
                kneeCtx.fill(Path(ellipseIn: CGRect(x: -2.7, y: -2.2, width: 5.4, height: 5.4)), with: .color(metalColor))

                // Foot (facing forward, flat on floor)
                kneeCtx.drawLayer { footCtx in
                    footCtx.translateBy(x: 0, y: MicroduckKinematics.shin)
                    footCtx.rotate(by: Angle(degrees: -(thighAngle + kneeAngle)))

                    // Orange foot
                    footCtx.fill(Path(roundedRect: CGRect(x: -11, y: 0, width: 22, height: 11), cornerRadius: 4), with: .color(billColor))
                    // Gold sole
                    footCtx.fill(Path(roundedRect: CGRect(x: -11, y: 7.5, width: 22, height: 4), cornerRadius: 2), with: .color(soleColor))
                    // Subtle middle toe seam
                    footCtx.fill(Path(roundedRect: CGRect(x: -0.8, y: 2, width: 1.6, height: 5.5), cornerRadius: 0.8), with: .color(frameColor.opacity(0.35)))
                }
            }
        }
    }

    private func drawHead(ctx: GraphicsContext, isSideView: Bool, jawDrop: Double) {
        let shellColor = VoiceStationTokens.inputCream
        let shadeColor = VoiceStationTokens.panelHeader
        let frameColor = VoiceStationTokens.navy
        let eyeColor = VoiceStationTokens.gold
        let micHigh = VoiceStationTokens.micHighlight
        let dotColor = VoiceStationTokens.dotBlue
        let billColor = VoiceStationTokens.duckOrange
        let billDeep = VoiceStationTokens.duckOrangeDeep

        // Front view (facing user with camera eye centered and head high)
        var shellPath = Path()
        shellPath.move(to: CGPoint(x: 32, y: 58))
        shellPath.addLine(to: CGPoint(x: 32, y: 36))
        shellPath.addCurve(to: CGPoint(x: 50, y: 20), control1: CGPoint(x: 32, y: 26), control2: CGPoint(x: 40, y: 20))
        shellPath.addLine(to: CGPoint(x: 74, y: 20))
        shellPath.addCurve(to: CGPoint(x: 92, y: 36), control1: CGPoint(x: 84, y: 20), control2: CGPoint(x: 92, y: 26))
        shellPath.addLine(to: CGPoint(x: 92, y: 58))
        shellPath.closeSubpath()
        ctx.fill(shellPath, with: .color(shellColor))

        // Visor plate
        ctx.fill(Path(roundedRect: CGRect(x: 37, y: 25, width: 50, height: 29), cornerRadius: 11), with: .color(shadeColor.opacity(0.32)))

        // Forehead shine
        var shinePath = Path()
        shinePath.move(to: CGPoint(x: 44, y: 23))
        shinePath.addCurve(to: CGPoint(x: 66, y: 21.3), control1: CGPoint(x: 50, y: 21.5), control2: CGPoint(x: 58, y: 21))
        ctx.stroke(shinePath, with: .color(Color.white.opacity(0.7)), lineWidth: 2)

        // Side brackets (ears/antennas)
        ctx.fill(Path(roundedRect: CGRect(x: 29.5, y: 46, width: 3.5, height: 10), cornerRadius: 1.75), with: .color(billColor))
        ctx.fill(Path(roundedRect: CGRect(x: 91, y: 46, width: 3.5, height: 10), cornerRadius: 1.75), with: .color(billColor))

        // Big Eye Camera (centered golden-yellow ring + dark lens + blue pupil from photos)
        ctx.fill(Path(ellipseIn: CGRect(x: 51, y: 28, width: 22, height: 22)), with: .color(eyeColor))
        ctx.fill(Path(ellipseIn: CGRect(x: 55, y: 32, width: 14, height: 14)), with: .color(frameColor))
        ctx.fill(Path(ellipseIn: CGRect(x: 58.3, y: 35.3, width: 7.4, height: 7.4)), with: .color(micHigh))
        ctx.fill(Path(ellipseIn: CGRect(x: 57.8, y: 34.8, width: 3.4, height: 3.4)), with: .color(dotColor))

        // Sensor slot (right cheek)
        ctx.fill(Path(roundedRect: CGRect(x: 77, y: 37.8, width: 5, height: 2.4), cornerRadius: 1.2), with: .color(frameColor))

        // State LED (left cheek)
        ctx.fill(Path(ellipseIn: CGRect(x: 43.5, y: 44, width: 3.5, height: 3.5)), with: .color(ledColor))

        // Mouth frame
        ctx.fill(Path(roundedRect: CGRect(x: 35, y: 59, width: 54, height: 5), cornerRadius: 2), with: .color(frameColor))

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

        // Lower jaw (drops with speech level)
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
