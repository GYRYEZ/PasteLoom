import AppKit
import ApplicationServices

@MainActor
protocol AccessibilityChecking: AnyObject {
    var isTrusted: Bool { get }
    func openSettings()
}

@MainActor
final class AccessibilityService: AccessibilityChecking {
    var isTrusted: Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
