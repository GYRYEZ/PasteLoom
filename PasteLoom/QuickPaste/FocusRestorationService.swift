import AppKit

struct FocusTarget: Equatable {
    let application: NSRunningApplication
    let bundleIdentifier: String?
    var processID: pid_t { application.processIdentifier }

    static func == (lhs: FocusTarget, rhs: FocusTarget) -> Bool {
        lhs.processID == rhs.processID
    }
}

@MainActor
protocol FocusRestoring: AnyObject {
    func captureTarget() -> FocusTarget?
    func restore(_ target: FocusTarget?) async -> Bool
}

@MainActor
final class FocusRestorationService: FocusRestoring {
    private var lastExternalTarget: FocusTarget?
    private var activationObserver: NSObjectProtocol?

    private func isValidTargetApplication(_ app: NSRunningApplication) -> Bool {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !app.isTerminated else { return false }
        let ignoredBundleIDs: Set<String> = [
            "com.apple.controlcenter",
            "com.apple.dock",
            "com.apple.systemuiserver",
            "com.apple.WindowManager",
            "com.apple.notificationcenterui",
            "com.apple.loginwindow"
        ]
        if let bundleID = app.bundleIdentifier, ignoredBundleIDs.contains(bundleID) {
            return false
        }
        return app.activationPolicy == .regular
    }

    init() {
        if let current = NSWorkspace.shared.frontmostApplication,
           isValidTargetApplication(current) {
            lastExternalTarget = FocusTarget(application: current, bundleIdentifier: current.bundleIdentifier)
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if self.isValidTargetApplication(app) {
                self.lastExternalTarget = FocusTarget(application: app, bundleIdentifier: app.bundleIdentifier)
            }
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    func captureTarget() -> FocusTarget? {
        if let current = NSWorkspace.shared.frontmostApplication,
           isValidTargetApplication(current) {
            let target = FocusTarget(application: current, bundleIdentifier: current.bundleIdentifier)
            lastExternalTarget = target
            return target
        }
        if let target = lastExternalTarget, isValidTargetApplication(target.application) {
            return target
        }
        // Fallback: look for frontmost regular running application that is not self
        if let fallback = NSWorkspace.shared.runningApplications.first(where: { isValidTargetApplication($0) }) {
            let target = FocusTarget(application: fallback, bundleIdentifier: fallback.bundleIdentifier)
            lastExternalTarget = target
            return target
        }
        return nil
    }

    func restore(_ target: FocusTarget?) async -> Bool {
        guard let target, !target.application.isTerminated else { return false }

        // 1. Yield activation while PasteLoom is still active
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: target.application)
        }

        // 2. OpenConfiguration via NSWorkspace (official Apple modern activation API)
        if let bundleURL = target.application.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: config, completionHandler: nil)
        }

        // 3. AppleScript direct activation (tells target app to activate itself, bypassing background restrictions)
        if let bundleID = target.bundleIdentifier, !bundleID.isEmpty {
            let script = "tell application id \"\(bundleID)\" to activate"
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        } else {
            let script = "tell application \"System Events\" to set frontmost of (first process whose unix id is \(target.processID)) to true"
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        }

        // 4. Native running app activate
        let didActivate = target.application.activate(options: [.activateIgnoringOtherApps])
        NSApp.deactivate()

        // 5. Wait for target application to become frontmost
        for _ in 0..<16 {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier == target.processID ||
                (target.bundleIdentifier != nil && front?.bundleIdentifier == target.bundleIdentifier) {
                // Short stabilization sleep so the target window first responder text cursor settles
                try? await Task.sleep(for: .milliseconds(40))
                return true
            }
            try? await Task.sleep(for: .milliseconds(25))
        }

        let front = NSWorkspace.shared.frontmostApplication
        let matches = front?.processIdentifier == target.processID ||
            (target.bundleIdentifier != nil && front?.bundleIdentifier == target.bundleIdentifier)
        try? await Task.sleep(for: .milliseconds(30))
        return matches || didActivate || !target.application.isTerminated
    }
}
