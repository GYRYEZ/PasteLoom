import Foundation

enum QuickPasteOutcome: Equatable {
    case copied
    case pasted
    case copiedPermissionRequired
    case copiedNoTarget
    case copiedActivationFailed
    case copiedPasteEventFailed
    case failed(String)
}

enum QuickPasteDecision: Equatable {
    case copyOnly
    case permissionRequired
    case noTarget
    case activationFailed
    case sendPaste

    static func make(autoPasteEnabled: Bool, accessibilityGranted: Bool,
                     targetValid: Bool, targetActivated: Bool) -> QuickPasteDecision {
        guard autoPasteEnabled else { return .copyOnly }
        guard accessibilityGranted else { return .permissionRequired }
        guard targetValid else { return .noTarget }
        guard targetActivated else { return .activationFailed }
        return .sendPaste
    }
}

@MainActor
final class QuickPasteActionService {
    private let history: any QuickPasteHistoryProviding
    private let accessibility: any AccessibilityChecking
    private let focus: any FocusRestoring
    private let autoPaste: any AutoPasting

    init(history: any QuickPasteHistoryProviding,
         accessibility: any AccessibilityChecking,
         focus: any FocusRestoring,
         autoPaste: any AutoPasting) {
        self.history = history
        self.accessibility = accessibility
        self.focus = focus
        self.autoPaste = autoPaste
    }

    func perform(item: HistoryItem,
                 autoPasteEnabled: Bool,
                 target: FocusTarget?,
                 dismiss: () -> Void) async -> QuickPasteOutcome {
        await perform(items: [item], autoPasteEnabled: autoPasteEnabled, target: target, dismiss: dismiss)
    }

    func perform(items: [HistoryItem],
                 autoPasteEnabled: Bool,
                 target: FocusTarget?,
                 dismiss: () -> Void) async -> QuickPasteOutcome {
        guard !items.isEmpty else { return .failed("未选择任何词条") }
        do {
            if items.count == 1, let item = items.first {
                try await history.copyForQuickPaste(item)
            } else {
                try await history.copyMultipleForQuickPaste(items)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
        dismiss()

        let effectiveTarget = target ?? focus.captureTarget()
        let validTarget = effectiveTarget.flatMap { candidate -> FocusTarget? in
            guard candidate.processID > 0,
                  candidate.processID != ProcessInfo.processInfo.processIdentifier,
                  !candidate.application.isTerminated else { return nil }
            return candidate
        }
        let activated = await focus.restore(validTarget)
        let decision = QuickPasteDecision.make(autoPasteEnabled: autoPasteEnabled,
                                               accessibilityGranted: accessibility.isTrusted,
                                               targetValid: validTarget != nil,
                                               targetActivated: activated)
        switch decision {
        case .copyOnly: return .copied
        case .permissionRequired:
            if let validTarget {
                try? await Task.sleep(for: .milliseconds(80))
                let script = "tell application \"System Events\" to keystroke \"v\" using command down"
                var err: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&err)
                if err == nil {
                    return .pasted
                }
            }
            return .copiedPermissionRequired
        case .noTarget: return .copiedNoTarget
        case .activationFailed:
            if let validTarget {
                try? await Task.sleep(for: .milliseconds(80))
                if autoPaste.paste(into: validTarget) {
                    return .pasted
                }
            }
            return .copiedActivationFailed
        case .sendPaste:
            guard let validTarget else { return .copiedNoTarget }
            try? await Task.sleep(for: .milliseconds(60))
            return autoPaste.paste(into: validTarget) ? .pasted : .copiedPasteEventFailed
        }
    }
}
