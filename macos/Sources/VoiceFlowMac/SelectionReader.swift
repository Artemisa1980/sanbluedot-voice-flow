import ApplicationServices
import AppKit
import Foundation

public enum SelectionReader {
    /// Read the currently selected text in the active frontmost application.
    ///
    /// Uses a dual-strategy approach:
    /// 1. Direct Accessibility API query for `kAXSelectedTextAttribute`.
    /// 2. Synthetic `⌘C` copy fallback for web views, Electron, and non-native apps.
    public static func getSelectedText() -> String? {
        // Strategy 1: Direct Accessibility
        if let axText = readViaAccessibility(), !axText.isEmpty {
            return axText
        }

        // Strategy 2: Fast synthetic copy fallback
        return readViaCopyKeystroke()
    }

    private static func readViaAccessibility() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementValue: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementValue
        )
        guard focusedResult == .success, let focusedElement = focusedElementValue else {
            return nil
        }
        // Conditional, not forced. `.success` says the attribute was returned, not that it
        // is an `AXUIElement`; a crash here would take the whole app down mid-recording
        // over an application that answered with something else.
        guard CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else { return nil }
        let element = focusedElement as! AXUIElement
        var selectedTextValue: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedTextValue
        )
        guard textResult == .success, let selectedText = selectedTextValue as? String else {
            return nil
        }
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Read the selection by copying it, then put back what the speaker had.
    ///
    /// The synthetic `⌘C` overwrites the general pasteboard. A dictation that completes
    /// overwrites it again with its own result, so the loss was invisible there — but a
    /// recording the speaker cancels with ESC produces no result at all, and what was on
    /// the clipboard before the press was gone with nothing to show for it. The previous
    /// contents are captured item by item and restored, so a copied image or file
    /// survives the read as well as text.
    private static func readViaCopyKeystroke() -> String? {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return nil }

        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount
        let preserved = snapshot(pasteboard)

        let cKeyCode: CGKeyCode = 8 // 'c' key
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false) else {
            return nil
        }

        keyDown.flags = .maskCommand
        keyUp.flags = []

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        // Give the target application 45ms to process the copy event
        usleep(45_000)

        guard pasteboard.changeCount != initialChangeCount else { return nil }

        let copied = pasteboard.string(forType: .string)
        restore(preserved, to: pasteboard)

        guard let copied else { return nil }
        let trimmed = copied.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Copy every item and representation currently on the pasteboard.
    ///
    /// The items themselves cannot be re-written: an `NSPasteboardItem` already owned by
    /// a pasteboard is rejected when offered to one again, so each type's data is read
    /// out into a fresh item here.
    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }
}
