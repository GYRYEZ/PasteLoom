import AppKit
import CoreGraphics
import Carbon.HIToolbox

@MainActor
protocol AutoPasting: AnyObject {
    func paste(into target: FocusTarget) -> Bool
}

@MainActor
final class AutoPasteService: AutoPasting {
    func paste(into target: FocusTarget) -> Bool {
        guard target.processID != ProcessInfo.processInfo.processIdentifier,
              !target.application.isTerminated else { return false }

        // 1. Post native hardware Quartz events
        let posted = postHardwarePasteEvents()

        // 2. Fallback via AppleScript if Quartz event creation fails
        if !posted {
            return sendAppleScriptPaste(to: target)
        }
        return true
    }

    private func postHardwarePasteEvents() -> Bool {
        // Use clean .hidSystemState to avoid contamination by mouse drag or leftover session modifier flags
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }

        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        // Key code 55: kVK_Command, Key code 9: kVK_ANSI_V
        let cmdKeyCode: CGKeyCode = 55
        let vKeyCode: CGKeyCode = 9

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: false) else {
            return false
        }

        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        cmdUp.flags = []

        // Post Command Down
        postEvent(cmdDown)
        usleep(25_000) // 25ms

        // Post 'V' Down
        postEvent(vDown)
        usleep(35_000) // 35ms key hold

        // Post 'V' Up
        postEvent(vUp)
        usleep(25_000) // 25ms

        // Post Command Up
        postEvent(cmdUp)

        return true
    }

    private func postEvent(_ event: CGEvent) {
        // Post to both .cghidEventTap (hardware layer) and .cgSessionEventTap (session layer)
        event.post(tap: .cghidEventTap)
        event.post(tap: .cgSessionEventTap)
    }

    private func sendAppleScriptPaste(to target: FocusTarget) -> Bool {
        let script = "tell application \"System Events\" to keystroke \"v\" using command down"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        return error == nil
    }
}
