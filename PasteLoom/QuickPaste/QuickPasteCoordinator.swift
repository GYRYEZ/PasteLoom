import AppKit
import SwiftUI

enum QuickPasteKeyAction: Equatable {
    case escape
    case moveDown
    case moveUp
    case confirm
    case toggleSelect
    case number(Int)
    case passthrough

    init(keyCode: UInt16) {
        switch keyCode {
        case 53: self = .escape
        case 125: self = .moveDown
        case 126: self = .moveUp
        case 36, 76: self = .confirm
        case 49: self = .toggleSelect
        case 18, 83: self = .number(1)
        case 19, 84: self = .number(2)
        case 20, 85: self = .number(3)
        case 21, 86: self = .number(4)
        case 23, 87: self = .number(5)
        case 22, 88: self = .number(6)
        case 26, 89: self = .number(7)
        case 28, 91: self = .number(8)
        case 25, 92: self = .number(9)
        default: self = .passthrough
        }
    }
}

@MainActor
final class QuickPasteCoordinator {
    private let model: AppModel
    private let accessibility: any AccessibilityChecking
    private let focus: any FocusRestoring
    private let action: QuickPasteActionService
    private let viewModel: QuickPasteViewModel
    private let panel = QuickPastePanel()
    private var previousApplication: FocusTarget?
    private var keyMonitor: Any?
    private var isOpen = false
    private var isPerformingAction = false
    private var isNavigatingList = false
    private(set) var wasRecentlyActive = false
    private var recentlyActiveResetTask: Task<Void, Never>?

    var isQuickPasteActive: Bool {
        isOpen || panel.isPresenting || panel.isVisible || wasRecentlyActive
    }

    init(model: AppModel,
         accessibility: any AccessibilityChecking,
         focus: any FocusRestoring,
         autoPaste: any AutoPasting) {
        self.model = model
        self.accessibility = accessibility
        self.focus = focus
        viewModel = QuickPasteViewModel(history: model)
        action = QuickPasteActionService(history: model, accessibility: accessibility,
                                         focus: focus, autoPaste: autoPaste)
        panel.contentView = NSHostingView(rootView: QuickPasteView(
            model: viewModel,
            onConfirm: { [weak self] in self?.confirm(autoPaste: self?.model.autoPasteEnabled ?? false) },
            onCopyOnly: { [weak self] in self?.confirm(autoPaste: false) },
            onOpenAccessibilitySettings: { [weak self] in self?.accessibility.openSettings() },
            onDismiss: { [weak self] in self?.dismiss(restoreFocus: true) }
        ))
        panel.onLoseFocus = { [weak self] in self?.dismiss(restoreFocus: false) }
    }

    func toggle() {
        if isOpen { dismiss(restoreFocus: true) }
        else { show() }
    }

    func showAt(point: NSPoint) {
        if isOpen {
            panel.position(near: point)
            panel.orderFrontRegardless()
            panel.makeKeyAndOrderFront(nil)
            return
        }
        show(at: point)
    }

    func refreshPermissionState() {
        guard isOpen else { return }
        viewModel.updateMode(autoPasteEnabled: model.autoPasteEnabled,
                             accessibilityGranted: accessibility.isTrusted)
    }

    private func show(at point: NSPoint? = nil) {
        previousApplication = focus.captureTarget()
        viewModel.open()
        viewModel.updateMode(autoPasteEnabled: model.autoPasteEnabled,
                             accessibilityGranted: accessibility.isTrusted)
        installKeyMonitor()
        isOpen = true
        isNavigatingList = false
        panel.isPresenting = true
        let storedMode = UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"
        panel.appearance = AppearanceManager.currentWindowAppearance(for: storedMode)
        if let point {
            panel.position(near: point)
        } else {
            panel.positionOnPointerScreen()
        }
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.panel.isPresenting = false
        }
    }

    private func confirm(autoPaste: Bool) {
        guard !isPerformingAction else { return }
        let items = viewModel.itemsToPaste
        guard !items.isEmpty else { return }
        isPerformingAction = true
        let target = previousApplication ?? focus.captureTarget()
        Task {
            let result = await action.perform(items: items, autoPasteEnabled: autoPaste, target: target) { [weak self] in
                self?.dismiss(restoreFocus: false)
            }
            isPerformingAction = false
            if case .failed(let message) = result {
                viewModel.statusMessage = message
            }
        }
    }

    private func dismiss(restoreFocus: Bool) {
        guard isOpen else { return }
        isOpen = false
        isNavigatingList = false
        wasRecentlyActive = true
        recentlyActiveResetTask?.cancel()
        recentlyActiveResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self?.wasRecentlyActive = false
        }
        let target = previousApplication
        previousApplication = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel.orderOut(nil)
        viewModel.reset()
        ThumbnailImageCache.shared.clear()
        Task { [weak self] in
            await self?.model.clearThumbnailMemoryCache()
        }
        // Ensure main bottom drawer window does NOT pop up
        for window in NSApp.windows where window !== panel {
            let title = window.title
            let id = window.identifier?.rawValue
            if id == "history" || title.contains("PasteLoom") {
                window.orderOut(nil)
            }
        }
        if restoreFocus {
            Task { _ = await focus.restore(target) }
        } else {
            NSApp.deactivate()
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isOpen, event.window === self.panel else { return event }

            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "c" {
                self.confirm(autoPaste: false)
                return nil
            }

            switch QuickPasteKeyAction(keyCode: event.keyCode) {
            case .escape:
                self.dismiss(restoreFocus: true)
                return nil
            case .moveDown:
                self.isNavigatingList = true
                self.viewModel.moveSelection(by: 1)
                return nil
            case .moveUp:
                self.isNavigatingList = true
                self.viewModel.moveSelection(by: -1)
                return nil
            case .toggleSelect:
                if self.viewModel.query.isEmpty || self.isNavigatingList {
                    self.viewModel.toggleSelectCurrent()
                    return nil
                }
                return event
            case .confirm:
                self.confirm(autoPaste: self.model.autoPasteEnabled)
                return nil
            case .number(let num):
                if event.modifierFlags.contains(.command) || self.isNavigatingList || self.viewModel.query.isEmpty {
                    let index = num - 1
                    if self.viewModel.results.indices.contains(index) {
                        self.viewModel.selectIndex(index)
                        self.confirm(autoPaste: self.model.autoPasteEnabled)
                        return nil
                    }
                }
                return event
            case .passthrough:
                self.isNavigatingList = false
                return event
            }
        }
    }
}
