import Carbon.HIToolbox
import AppKit
import Foundation

enum ShortcutAction: String, CaseIterable, Identifiable {
    case quickPaste = "quickPaste"
    case mainWindow = "mainWindow"
    case screenshotAnnotate = "screenshotAnnotate"
    case quickScreenshot = "quickScreenshot"

    var id: String { rawValue }

    var hotKeyID: UInt32 {
        switch self {
        case .quickPaste: return 1
        case .mainWindow: return 2
        case .screenshotAnnotate: return 3
        case .quickScreenshot: return 4
        }
    }

    var displayName: String {
        switch self {
        case .quickPaste: return "弹出快速粘贴浮窗"
        case .mainWindow: return "打开主窗口"
        case .screenshotAnnotate: return "截图标注"
        case .quickScreenshot: return "快速截图到剪贴板"
        }
    }

    var defaultShortcut: GlobalShortcut {
        switch self {
        case .quickPaste:
            return GlobalShortcut(keyCode: 9, modifiers: UInt32(cmdKey | optionKey), displayName: "⌥⌘V")
        case .mainWindow:
            return GlobalShortcut(keyCode: 9, modifiers: UInt32(cmdKey | shiftKey), displayName: "⇧⌘V")
        case .screenshotAnnotate:
            return GlobalShortcut(keyCode: 0, modifiers: UInt32(cmdKey | optionKey), displayName: "⌥⌘A")
        case .quickScreenshot:
            return GlobalShortcut(keyCode: 0, modifiers: UInt32(cmdKey | optionKey | shiftKey), displayName: "⌥⇧⌘A")
        }
    }

    var keyCodeKey: String {
        self == .quickPaste ? "quickPasteKeyCode" : "\(rawValue)KeyCode"
    }

    var modifiersKey: String {
        self == .quickPaste ? "quickPasteModifiers" : "\(rawValue)Modifiers"
    }

    var nameKey: String {
        self == .quickPaste ? "quickPasteShortcutName" : "\(rawValue)ShortcutName"
    }
}

enum ShortcutConflict: Error, Equatable {
    case inAppConflict(ShortcutAction)
    case systemConflict(OSStatus)

    var localizedDescription: String {
        switch self {
        case .inAppConflict(let action):
            return "快捷键与【\(action.displayName)】冲突，请选择其他按键组合。"
        case .systemConflict(let code):
            return "快捷键注册失败或已被系统占用（代码：\(code)），已回滚到原设置。"
        }
    }
}

struct GlobalShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let displayName: String

    static let quickPaste = ShortcutAction.quickPaste.defaultShortcut
    static let mainWindow = ShortcutAction.mainWindow.defaultShortcut
    static let screenshotAnnotate = ShortcutAction.screenshotAnnotate.defaultShortcut
    static let quickScreenshot = ShortcutAction.quickScreenshot.defaultShortcut

    static func load(for action: ShortcutAction = .quickPaste, from store: UserDefaults = .standard) -> GlobalShortcut {
        guard let keyCode = store.object(forKey: action.keyCodeKey) as? NSNumber,
              let modifiers = store.object(forKey: action.modifiersKey) as? NSNumber,
              let name = store.string(forKey: action.nameKey), !name.isEmpty else {
            return action.defaultShortcut
        }
        return GlobalShortcut(keyCode: keyCode.uint32Value, modifiers: modifiers.uint32Value,
                              displayName: name)
    }

    func save(for action: ShortcutAction = .quickPaste, to store: UserDefaults = .standard) {
        store.set(keyCode, forKey: action.keyCodeKey)
        store.set(modifiers, forKey: action.modifiersKey)
        store.set(displayName, forKey: action.nameKey)
    }

    static func clear(for action: ShortcutAction, in store: UserDefaults = .standard) {
        store.removeObject(forKey: action.keyCodeKey)
        store.removeObject(forKey: action.modifiersKey)
        store.removeObject(forKey: action.nameKey)
    }

    static func from(_ event: NSEvent) -> GlobalShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control),
              let characters = event.charactersIgnoringModifiers?.uppercased(),
              characters.count == 1,
              characters.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
            return nil
        }
        var modifiers: UInt32 = 0
        var name = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); name += "⌃" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); name += "⌥" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); name += "⇧" }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); name += "⌘" }
        return GlobalShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers,
                              displayName: name + characters)
    }
}

@MainActor
final class GlobalShortcutService {
    var onTrigger: (() -> Void)?
    var onActionTrigger: ((ShortcutAction) -> Void)?

    private var hotKeys: [ShortcutAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    init() {
        installHandler()
    }

    private func installHandler() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        _ = InstallEventHandler(GetApplicationEventTarget(), Self.eventCallback,
                                1, &eventType,
                                Unmanaged.passUnretained(self).toOpaque(),
                                &eventHandler)
    }

    func registerAll(from store: UserDefaults = .standard) -> [ShortcutAction: OSStatus] {
        var results: [ShortcutAction: OSStatus] = [:]
        for action in ShortcutAction.allCases {
            let shortcut = GlobalShortcut.load(for: action, from: store)
            results[action] = registerHotKey(shortcut, for: action)
        }
        return results
    }

    @discardableResult
    func register(_ shortcut: GlobalShortcut = .quickPaste) -> OSStatus {
        let res = updateShortcut(shortcut, for: .quickPaste)
        switch res {
        case .success: return noErr
        case .failure(.systemConflict(let code)): return code
        case .failure(.inAppConflict): return OSStatus(eventHotKeyExistsErr)
        }
    }

    func updateShortcut(_ candidate: GlobalShortcut,
                        for action: ShortcutAction = .quickPaste,
                        store: UserDefaults = .standard) -> Result<Void, ShortcutConflict> {
        // 1. In-app conflict check
        for other in ShortcutAction.allCases where other != action {
            let otherShortcut = GlobalShortcut.load(for: other, from: store)
            if otherShortcut.keyCode == candidate.keyCode && otherShortcut.modifiers == candidate.modifiers {
                return .failure(.inAppConflict(other))
            }
        }

        // 2. Unregister previous
        let previous = GlobalShortcut.load(for: action, from: store)
        unregisterHotKey(for: action)

        // 3. Register with Carbon
        let status = registerHotKey(candidate, for: action)
        guard status == noErr else {
            _ = registerHotKey(previous, for: action)
            return .failure(.systemConflict(status))
        }

        candidate.save(for: action, to: store)
        return .success(())
    }

    func resetToDefault(for action: ShortcutAction, store: UserDefaults = .standard) -> Result<Void, ShortcutConflict> {
        updateShortcut(action.defaultShortcut, for: action, store: store)
    }

    private func registerHotKey(_ shortcut: GlobalShortcut, for action: ShortcutAction) -> OSStatus {
        installHandler()
        let identifier = EventHotKeyID(signature: 0x504C4E58, id: action.hotKeyID) // PLNX
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                         identifier, GetApplicationEventTarget(),
                                         0, &ref)
        if status == noErr, let ref {
            hotKeys[action] = ref
        }
        return status
    }

    private func unregisterHotKey(for action: ShortcutAction) {
        if let ref = hotKeys[action] {
            UnregisterEventHotKey(ref)
            hotKeys.removeValue(forKey: action)
        }
    }

    deinit {
        MainActor.assumeIsolated {
            unregister()
        }
    }

    func unregister() {
        for (_, ref) in hotKeys {
            UnregisterEventHotKey(ref)
        }
        hotKeys.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private static let eventCallback: EventHandlerUPP = { _, event, userData in
        guard let userData, let event else { return OSStatus(eventNotHandledErr) }
        let service = Unmanaged<GlobalShortcutService>.fromOpaque(userData).takeUnretainedValue()

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(event,
                                       EventParamName(kEventParamDirectObject),
                                       EventParamType(typeEventHotKeyID),
                                       nil,
                                       MemoryLayout<EventHotKeyID>.size,
                                       nil,
                                       &hotKeyID)
        guard status == noErr, hotKeyID.signature == 0x504C4E58 else {
            DispatchQueue.main.async { service.onTrigger?() }
            return noErr
        }

        let action = ShortcutAction.allCases.first(where: { $0.hotKeyID == hotKeyID.id }) ?? .quickPaste
        DispatchQueue.main.async {
            service.onActionTrigger?(action)
            if action == .quickPaste {
                service.onTrigger?()
            }
        }
        return noErr
    }
}
