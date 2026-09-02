import CoreGraphics
import Foundation
import VoiceFlowMacCore

enum HotkeyMonitorError: LocalizedError {
    case eventTapUnavailable

    var errorDescription: String? {
        "Global keyboard monitoring is unavailable. Grant Input Monitoring permission and retry."
    }
}

final class HotkeyMonitor {
    private let shortcut: Shortcut
    /// The chord that advances the processing mode. It shares this tap rather than
    /// opening a second one, so the app asks for Input Monitoring once.
    private let modeShortcut: Shortcut?
    private let onPressed: () -> Void
    private let onReleased: () -> Void
    private let onModeCycle: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyIsDown = false

    init(
        shortcut: Shortcut,
        modeShortcut: Shortcut? = nil,
        onPressed: @escaping () -> Void,
        onReleased: @escaping () -> Void,
        onModeCycle: @escaping () -> Void = {}
    ) {
        self.shortcut = shortcut
        // A modifier-only chord is a hold, and the mode switch is a tap. Configuration
        // now refuses one, so this is a defensive floor rather than the enforcement
        // point: dropping it silently here is what left the switch dead while the menu
        // bar still named the chord.
        self.modeShortcut = modeShortcut?.keyCode == nil ? nil : modeShortcut
        self.onPressed = onPressed
        self.onReleased = onReleased
        self.onModeCycle = onModeCycle
    }

    func start() throws {
        let eventMask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, context in
                guard let context else {
                    return Unmanaged.passUnretained(event)
                }
                let monitor = Unmanaged<HotkeyMonitor>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: context
        ) else {
            throw HotkeyMonitorError.eventTapUnavailable
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
        keyIsDown = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            // The tap observed nothing while it was disabled. A release inside that
            // window is lost, which would otherwise leave a recording running forever.
            resyncHeldState()
            return Unmanaged.passUnretained(event)
        }

        // The mode switch is checked first: with a modifier-only trigger the record
        // path only ever looks at `.flagsChanged`, so a plain key press would never
        // reach a check placed after it.
        if type == .keyDown, cycleModeRequested(event) {
            onModeCycle()
            return Unmanaged.passUnretained(event)
        }

        if shortcut.keyCode == nil {
            return handleModifierOnly(type: type, event: event)
        }

        if type == .flagsChanged,
           chordReleaseRequired(
               isActive: keyIsDown,
               modifiersStillMatch: modifiersMatch(event.flags)
           ) {
            keyIsDown = false
            onReleased()
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == shortcut.keyCode else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            guard !isRepeat, !keyIsDown, modifiersMatch(event.flags) else {
                return Unmanaged.passUnretained(event)
            }
            keyIsDown = true
            onPressed()
        } else if type == .keyUp, keyIsDown {
            keyIsDown = false
            onReleased()
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleModifierOnly(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let isPressed = event.flags.contains(.maskSecondaryFn)
        if isPressed, !keyIsDown {
            keyIsDown = true
            onPressed()
        } else if !isPressed, keyIsDown {
            keyIsDown = false
            onReleased()
        }
        return Unmanaged.passUnretained(event)
    }

    /// Reconcile the remembered hold against the keyboard's real state. Only a stale
    /// "still held" is correctable here; a missed press simply waits for the next one.
    private func resyncHeldState() {
        guard keyIsDown else { return }
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let stillHeld: Bool
        if let keyCode = shortcut.keyCode {
            stillHeld = modifiersMatch(flags) && CGEventSource.keyState(
                .combinedSessionState,
                key: CGKeyCode(keyCode)
            )
        } else {
            stillHeld = flags.contains(.maskSecondaryFn)
        }
        guard !stillHeld else { return }
        keyIsDown = false
        onReleased()
    }

    /// Whether this key-down is the mode chord: the right key, held with exactly the
    /// right modifiers, and not the keyboard repeating a key already held down.
    private func cycleModeRequested(_ event: CGEvent) -> Bool {
        guard let modeShortcut, let expectedKey = modeShortcut.keyCode else { return false }
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return false }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == expectedKey else { return false }
        return flagsMatch(event.flags, modeShortcut.modifiers)
    }

    private func modifiersMatch(_ flags: CGEventFlags) -> Bool {
        flagsMatch(flags, shortcut.modifiers)
    }

    private func flagsMatch(_ flags: CGEventFlags, _ modifiers: Set<ShortcutModifier>) -> Bool {
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

        let relevant: CGEventFlags = [
            .maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn,
        ]
        return flags.intersection(relevant) == expected
    }
}
