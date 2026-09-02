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
    private let onPressed: () -> Void
    private let onReleased: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyIsDown = false

    init(shortcut: Shortcut, onPressed: @escaping () -> Void, onReleased: @escaping () -> Void) {
        self.shortcut = shortcut
        self.onPressed = onPressed
        self.onReleased = onReleased
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

    private func modifiersMatch(_ flags: CGEventFlags) -> Bool {
        var expected = CGEventFlags()
        for modifier in shortcut.modifiers {
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
