import ApplicationServices
import AppKit
import Foundation
import VoiceFlowMacCore

@MainActor
enum AutoPaste {
    /// Paste the clipboard at the active cursor, reporting the real outcome.
    ///
    /// `CGEvent.post` delivers to whatever application holds focus at post time, not to
    /// the one that held it when the call was made. Checking the target once and then
    /// posting 40ms later therefore proves nothing: a focus change inside that window
    /// routes the keystroke somewhere the check never approved, which for a terminal
    /// means executing dictated text. The exclusion is re-checked immediately before the
    /// keystroke leaves, and that second check is the one that decides.
    ///
    /// The result is delivered through `completion` for the same reason: the outcome is
    /// not known until the deferred work runs, so a synchronous `Bool` could only ever
    /// be a guess. `completion` is always called exactly once, on the main queue.
    static func paste(
        after delay: TimeInterval = 0.015,
        frontmostApplication: @escaping () -> NSRunningApplication? = {
            NSWorkspace.shared.frontmostApplication
        },
        completion: @escaping @MainActor (Bool, String?) -> Void
    ) {
        // Checked without the system prompt: asking on every paste could raise it each
        // time permission is missing (D-46). The prompt belongs to the explicit request.
        guard AXIsProcessTrusted() else {
            completion(false, nil)
            return
        }

        let vKeyCode: CGKeyCode = 9 // 'v' key
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            completion(false, nil)
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = []

        // The delay lets the hotkey release and window focus settle in the window server
        // before the decisive target check and synthetic keystroke are executed.
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // Decisive check: this is the application that will actually receive it.
            let targetBundleID = frontmostApplication()?.bundleIdentifier
            guard !PasteTarget.requiresClipboardDelivery(
                bundleIdentifier: targetBundleID
            ) else {
                completion(false, nil)
                return
            }

            // If pasting into a terminal emulator, flatten multi-line text into a single
            // line and trim whitespace to guarantee safe prompt insertion without accidental execution.
            // The delivered text is handed back, so History records what the terminal
            // received rather than the multi-line original (D-12).
            var delivered: String?
            if PasteTarget.isTerminal(bundleIdentifier: targetBundleID) {
                let pasteboard = NSPasteboard.general
                if let current = pasteboard.string(forType: .string) {
                    let singleLine = PasteTarget.terminalSafe(current)
                    if singleLine != current {
                        pasteboard.clearContents()
                        pasteboard.setString(singleLine, forType: .string)
                        delivered = singleLine
                    }
                }
            }

            keyDown.post(tap: .cghidEventTap)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.010) {
                keyUp.post(tap: .cghidEventTap)
                completion(true, delivered)
            }
        }
    }

    /// Check whether Accessibility permission is currently active without prompting.
    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }
}
