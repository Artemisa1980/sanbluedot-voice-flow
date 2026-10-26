import CoreFoundation

/// The floating Microduck HUD layout and measurements (I-82).
///
/// Approved by the owner from `docs/hud-redesign-02-bubble.html` (capsule) and
/// `docs/microduck-mascot-01.html` §2–3 (the articulated duck). Every value is in points.
public enum HUDLayout {
    // Microduck articulated mascot dimensions
    public static let duckWidth: CGFloat = 60
    public static let duckHeight: CGFloat = 82
    public static let duckToBubble: CGFloat = 60
    public static let duckToBubbleY: CGFloat = 48

    // Bubble capsule sizes (trimmed width by 2 sizes to eliminate empty void)
    public static let capsuleMinSize = CGSize(width: 40, height: 18)
    public static let capsuleShortSize = CGSize(width: 120, height: 24)
    public static let capsuleFullSize = CGSize(width: 126, height: 35)

    // HUD window bounds containing duck and thought-bubble
    public static let panelWidth: CGFloat = 196
    public static let panelHeight: CGFloat = 92

    public static var contentWidth: CGFloat { panelWidth }
    public static var contentHeight: CGFloat { panelHeight }

    // Column and typography metrics inside the bubble
    public static let bubbleWidth: CGFloat = 126
    public static let contentColumn: CGFloat = 106 // 126 - 20 (horizontal padding 10*2)
    public static let horizontalPadding: CGFloat = 10
    public static let verticalPadding: CGFloat = 3.5
    public static let rowSpacing: CGFloat = 2.2
    public static let rowCount: CGFloat = 3
}
