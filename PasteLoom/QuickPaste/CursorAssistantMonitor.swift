import AppKit
import Foundation

@MainActor
final class CursorAssistantMonitor {
    var onTrigger: ((NSPoint) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var shiftPressTimestamps: [Date] = []
    private var wasShiftDown = false

    func start() {
        stop()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                self?.handleFlagsChanged(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        shiftPressTimestamps = []
        wasShiftDown = false
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    func handleFlagsChanged(_ event: NSEvent) {
        guard UserDefaults.standard.object(forKey: "cursorAssistantEnabled") as? Bool ?? true else { return }

        let flags = event.modifierFlags
        let forbiddenModifiers: NSEvent.ModifierFlags = [.command, .option, .control]

        // Only track pure Shift key taps without Command/Option/Control
        if !flags.intersection(forbiddenModifiers).isEmpty {
            wasShiftDown = false
            shiftPressTimestamps.removeAll()
            return
        }

        let isShiftDown = flags.contains(.shift)

        // Detect clean Shift press down (rising edge)
        if isShiftDown && !wasShiftDown {
            wasShiftDown = true
            let now = Date()
            recordShiftTap(at: now, mouseLocation: NSEvent.mouseLocation)
        } else if !isShiftDown && wasShiftDown {
            // Shift release (falling edge)
            wasShiftDown = false
        }
    }

    func recordShiftTap(at now: Date, mouseLocation: NSPoint) {
        // If pause between consecutive taps is > 0.85s, reset sequence
        if let last = shiftPressTimestamps.last, now.timeIntervalSince(last) > 0.85 {
            shiftPressTimestamps.removeAll()
        }
        // Keep taps within 2.0 seconds window
        shiftPressTimestamps = shiftPressTimestamps.filter { now.timeIntervalSince($0) <= 2.0 }
        shiftPressTimestamps.append(now)

        if shiftPressTimestamps.count >= 3 {
            shiftPressTimestamps.removeAll()
            wasShiftDown = false
            onTrigger?(mouseLocation)
        }
    }

    static func shouldTrigger(timestamps: [Date], intervalLimit: TimeInterval = 1.5) -> Bool {
        guard timestamps.count >= 3 else { return false }
        guard let first = timestamps.first, let last = timestamps.last else { return false }
        return last.timeIntervalSince(first) <= intervalLimit
    }
}
