/// Which applications may receive a synthesized keystroke.
///
/// This lives in the core library rather than beside the AppKit call because it is the
/// one auto-paste decision that can be wrong silently. Keeping the rule here puts it under
/// automated checks instead of inside an untested executable target.
public enum PasteTarget {
    /// Applications that must never receive a synthesized keystroke (clipboard delivery only).
    /// The owner approves additions or removals by name.
    public static let clipboardOnlyBundleIdentifiers: Set<String> = [
        // VoiceFlow itself. If its own window holds focus the keystroke lands in
        // whatever field is focused there, which is never where the speaker was
        // dictating. Kept in sync with CFBundleIdentifier by an automated check.
        "dot.sanblue.voiceflow",
    ]

    /// Known terminal applications where text is pasted into an interactive shell.
    /// Explicitly approved by the owner on 2026-09-01 for auto-paste with newline trimming guards.
    public static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "com.github.wez.wezterm",
        "com.mitchellh.ghostty",
    ]

    /// Whether the focused application is a terminal emulator.
    public static func isTerminal(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return terminalBundleIdentifiers.contains(bundleIdentifier)
    }

    /// Whether the focused application must receive clipboard delivery only.
    ///
    /// An unidentifiable target returns `true`. A missing bundle identifier is not
    /// evidence of a safe target, and the cost of being wrong is asymmetric: a refused
    /// paste costs one keystroke, an executed one costs a command.
    public static func requiresClipboardDelivery(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return true }
        return clipboardOnlyBundleIdentifiers.contains(bundleIdentifier)
    }
}

