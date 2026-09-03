import CoreFoundation

/// The floating capsule's measurements, declared once.
///
/// The window was sized in two places that had to agree and did not. `FloatingHUDPanel`
/// created it at the redesigned `330 × 88`, and `positionPanel()` — called on every path
/// that shows the capsule — resized it back to the `295 × 74` the previous design used.
/// The window the speaker saw was therefore always the old one, 17pt narrower than the
/// three-row content asks for, so the right edge of the capsule was clipped every time.
///
/// Both constants were correct on the day they were written, which is why nothing failed:
/// the redesign changed one and left the other. They live here now so there is one value
/// to change, and `VoiceFlowMacCoreChecks` fails the build if the window is ever smaller
/// than the content it has to carry.
public enum HUDLayout {
    /// The microphone disc at the leading edge.
    public static let micDisc: CGFloat = 44
    /// Space between the disc and the three-row column.
    public static let discToColumn: CGFloat = 14
    /// The column carrying status, meter and telemetry.
    public static let contentColumn: CGFloat = 226
    public static let horizontalPadding: CGFloat = 14
    public static let verticalPadding: CGFloat = 10
    /// Meter and telemetry rows; the status row is sized by its own text.
    public static let rowHeight: CGFloat = 14
    public static let rowSpacing: CGFloat = 5
    public static let rowCount: CGFloat = 3

    public static let panelWidth: CGFloat = 330
    public static let panelHeight: CGFloat = 88

    /// What the capsule's content actually occupies.
    public static var contentWidth: CGFloat {
        micDisc + discToColumn + contentColumn + horizontalPadding * 2
    }

    public static var contentHeight: CGFloat {
        let rows = rowHeight * rowCount + rowSpacing * (rowCount - 1)
        return max(micDisc, rows) + verticalPadding * 2
    }
}
