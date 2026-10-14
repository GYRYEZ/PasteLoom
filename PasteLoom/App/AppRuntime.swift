import AppKit
import Carbon.HIToolbox
import Darwin

@MainActor
final class AppRuntime: ObservableObject {
    let model: AppModel
    let accessibility: AccessibilityService
    let focus: FocusRestorationService
    let autoPaste: AutoPasteService
    let actionService: QuickPasteActionService
    let quickPaste: QuickPasteCoordinator
    let shortcut = GlobalShortcutService()
    let edgeHover = EdgeHoverMonitor()
    let cursorAssistant = CursorAssistantMonitor()

    private var captureOwner: CaptureOwner?
    private var started = false
    private var activationObserver: NSObjectProtocol?
    @Published private(set) var shortcutRegistrationStatus: OSStatus = 0
    @Published private(set) var currentShortcut = GlobalShortcut.load(for: .quickPaste)

    init() {
        let model = AppModel()
        let accessibility = AccessibilityService()
        let focus = FocusRestorationService()
        let autoPaste = AutoPasteService()
        let actionService = QuickPasteActionService(history: model,
                                                   accessibility: accessibility,
                                                   focus: focus,
                                                   autoPaste: autoPaste)
        self.model = model
        self.accessibility = accessibility
        self.focus = focus
        self.autoPaste = autoPaste
        self.actionService = actionService
        self.quickPaste = QuickPasteCoordinator(model: model,
                                                accessibility: accessibility,
                                                focus: focus,
                                                autoPaste: autoPaste)

        shortcut.onActionTrigger = { [weak self] action in
            guard let self else { return }
            switch action {
            case .quickPaste:
                self.quickPaste.toggle()
            case .mainWindow:
                _ = self.focus.captureTarget()
                self.showMainWindow()
            case .screenshotAnnotate, .quickScreenshot:
                // Notification for screenshot actions
                NotificationCenter.default.post(name: NSNotification.Name("TriggerScreenshotAction"),
                                                object: action.rawValue)
            }
        }
        shortcut.onTrigger = { [weak self] in self?.quickPaste.toggle() }

        edgeHover.onTrigger = { [weak self] in
            _ = self?.focus.captureTarget()
            self?.showMainWindow()
        }

        cursorAssistant.onTrigger = { [weak self] point in
            self?.quickPaste.showAt(point: point)
        }

        for notifName in ["com.gyryez.pasteloom.toggleQuickPaste", "com.gyryez.pasteloom.next.toggleQuickPaste"] {
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(notifName),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.quickPaste.toggle()
            }
        }

        AppDelegate.runtime = self
        DispatchQueue.main.async { [weak self] in
            self?.start()
        }
    }

    func start() {
        guard !started else { return }
        started = true
        // The XCTest host launches the app executable beside the acceptance build.
        // It has no clipboard monitor to own and must not terminate the test runner.
        if NSClassFromString("XCTestCase") != nil { return }
        let owner = CaptureOwner()
        guard owner.acquire() else {
            activateExistingOrExplain()
            return
        }
        let ownLaunch = NSRunningApplication.current.launchDate ?? .distantFuture
        let targetIDs = Set(["com.gyryez.pasteloom", "com.gyryez.pasteloom.next", Bundle.main.bundleIdentifier ?? ""])
        let older = targetIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
            .filter { ($0.launchDate ?? .distantPast) < ownLaunch }
            .min { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
        if let older {
            owner.release()
            _ = older.activate()
            NSApp.terminate(nil)
            return
        }
        captureOwner = owner
        model.beginCaptureAsOwner()

        // Apply Dock visibility policy
        let showInDock = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true
        DockVisibilityService.apply(showInDock: showInDock)

        // Register all configured shortcuts
        _ = shortcut.registerAll()
        shortcutRegistrationStatus = shortcut.register(currentShortcut)

        // Start edge hover and cursor assistant monitors
        edgeHover.start()
        cursorAssistant.start()

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissionState()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.model.trimMemory()
        }
    }

    func showMainWindow() {
        guard !quickPaste.isQuickPasteActive && !quickPaste.wasRecentlyActive else { return }
        _ = focus.captureTarget()
        NotificationCenter.default.post(name: NSNotification.Name("EdgeHoverExpandDrawer"), object: nil)
        if let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "history" ||
            ($0.title.contains("PasteLoom") && !($0 is NSPanel))
        }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func refreshPermissionState() {
        quickPaste.refreshPermissionState()
    }

    func dismissMenuBar() {
        NotificationCenter.default.post(name: NSNotification.Name("DismissMenuBarExtraWindow"), object: nil)
        for window in NSApp.windows {
            let className = String(describing: type(of: window))
            if className.contains("MenuBarExtra") || className.contains("StatusBarWindow") || className.contains("NSPopover") || className.contains("NSStatusBarWindow") {
                window.orderOut(nil)
            }
        }
    }

    @discardableResult
    func pasteOrCopy(item: HistoryItem, forceCopyOnly: Bool = false) async -> QuickPasteOutcome {
        let isAutoPaste = !forceCopyOnly && model.autoPasteEnabled
        let target = focus.captureTarget()
        let outcome = await actionService.perform(
            items: [item],
            autoPasteEnabled: isAutoPaste,
            target: target
        ) { [weak self] in
            if isAutoPaste {
                NotificationCenter.default.post(
                    name: NSNotification.Name("CollapseDrawerForAutoPaste"),
                    object: nil
                )
                self?.dismissMenuBar()
            }
        }
        if outcome == .pasted {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
        return outcome
    }

    func updateShortcut(_ candidate: GlobalShortcut, for action: ShortcutAction = .quickPaste) -> Result<Void, ShortcutConflict> {
        let result = shortcut.updateShortcut(candidate, for: action)
        if action == .quickPaste {
            switch result {
            case .success:
                currentShortcut = candidate
                shortcutRegistrationStatus = noErr
            case .failure(.systemConflict(let code)):
                shortcutRegistrationStatus = code
            case .failure(.inAppConflict):
                shortcutRegistrationStatus = OSStatus(eventHotKeyExistsErr)
            }
        }
        return result
    }

    func resetShortcutToDefault(for action: ShortcutAction) -> Result<Void, ShortcutConflict> {
        let result = shortcut.resetToDefault(for: action)
        if action == .quickPaste, case .success = result {
            currentShortcut = action.defaultShortcut
            shortcutRegistrationStatus = noErr
        }
        return result
    }

    @discardableResult
    func updateShortcut(_ candidate: GlobalShortcut) -> Bool {
        let result = updateShortcut(candidate, for: .quickPaste)
        switch result {
        case .success: return true
        case .failure: return false
        }
    }

    private func activateExistingOrExplain() {
        let targetIDs = Set(["com.gyryez.pasteloom", "com.gyryez.pasteloom.next", Bundle.main.bundleIdentifier ?? ""])
        if let existing = targetIDs.flatMap({ NSRunningApplication.runningApplications(withBundleIdentifier: $0) })
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }) {
            _ = existing.activate()
        } else {
            let alert = NSAlert()
            alert.messageText = "PasteLoom 已在运行"
            alert.informativeText = "此实例不会启动第二个剪贴板监听器。"
            alert.runModal()
        }
        NSApp.terminate(nil)
    }
}

private final class CaptureOwner {
    private var descriptor: Int32 = -1

    func acquire() -> Bool {
        guard let databaseURL = try? SQLiteHistoryRepository.defaultURL() else { return false }
        let lockURL = databaseURL.deletingLastPathComponent().appendingPathComponent(".capture-owner.lock")
        descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return false }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            release()
            return false
        }
        return true
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit { release() }
}
