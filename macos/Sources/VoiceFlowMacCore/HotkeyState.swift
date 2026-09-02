/// Whether an active chord must release when its modifier flags change.
///
/// Keeping this transition in the dependency-free core makes the stuck-recording
/// scenario executable without requiring an Accessibility event tap in tests.
public func chordReleaseRequired(
    isActive: Bool,
    modifiersStillMatch: Bool
) -> Bool {
    isActive && !modifiersStillMatch
}
