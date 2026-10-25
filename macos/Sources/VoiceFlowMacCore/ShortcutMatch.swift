import CoreGraphics

/// Which key event means what, as a decision a check can read.
///
/// This lived inside the event tap, where nothing could reach it, and it was wrong in a
/// way no test could have caught from the outside: cancellation required Escape with no
/// modifiers at all. The push-to-talk trigger is `Fn`, so every key pressed during a
/// recording carries `maskSecondaryFn` — meaning Escape was accepted only while no
/// recording was running, and refused for the entire window in which there was something
/// to take back. The capsule offered a way out at exactly the moment it could not work.
public enum ShortcutMatch {
    /// Escape's virtual key code.
    public static let escapeKeyCode: UInt16 = 53

    private static let relevant: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn,
    ]

    public static func expectedFlags(for modifiers: Set<ShortcutModifier>) -> CGEventFlags {
        var expected = CGEventFlags()
        for modifier in modifiers {
            switch modifier {
            case .command: expected.insert(.maskCommand)
            case .control: expected.insert(.maskControl)
            case .option: expected.insert(.maskAlternate)
            case .shift: expected.insert(.maskShift)
            case .fn: expected.insert(.maskSecondaryFn)
            }
        }
        return expected
    }

    /// Keys on which macOS sets `maskSecondaryFn` whether or not Fn is held: F1–F20 and
    /// the arrow and navigation keys. Apple documents this on
    /// `NSEvent.ModifierFlags.function`.
    private static let functionFlaggedKeyCodes: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
        105, 107, 113, 106, 64, 79, 80, 90,
        123, 124, 125, 126, 114, 115, 116, 117, 119, 121,
    ]

    /// Whether the held modifiers are exactly the chord's. On a key that always carries
    /// the Function flag, that flag is ignored unless the chord names `fn`, so a
    /// `command+shift+f8` chord is not refused for a flag nobody pressed.
    public static func flagsMatch(
        _ flags: CGEventFlags,
        _ modifiers: Set<ShortcutModifier>,
        keyCode: UInt16? = nil
    ) -> Bool {
        var held = flags.intersection(relevant)
        if let keyCode, functionFlaggedKeyCodes.contains(keyCode), !modifiers.contains(.fn) {
            held.remove(.maskSecondaryFn)
        }
        return held == expectedFlags(for: modifiers)
    }

    /// Whether this key event should take the recording back.
    ///
    /// Escape counts on its own, and it counts while the trigger's own modifiers are
    /// down — which for a held trigger is the only state a recording can be in. Nothing
    /// else does: a chord that ends in Escape carries modifiers the trigger does not,
    /// and must not be read as a cancellation.
    public static func isCancel(
        keyCode: UInt16,
        flags: CGEventFlags,
        trigger triggerModifiers: Set<ShortcutModifier>
    ) -> Bool {
        guard keyCode == escapeKeyCode else { return false }
        return flagsMatch(flags, []) || flagsMatch(flags, triggerModifiers)
    }
}
