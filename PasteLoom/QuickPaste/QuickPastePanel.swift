import AppKit

@MainActor
final class QuickPastePanel: NSPanel, NSWindowDelegate {
    var onLoseFocus: (() -> Void)?
    var isPresenting = false

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 480, height: 580),
                   styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        delegate = self
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isExcludedFromWindowsMenu = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func positionOnPointerScreen() {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
                ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let proposedX = visible.midX - frame.width / 2
        let proposedY = visible.minY + visible.height * 0.58 - frame.height / 2
        let x = min(max(proposedX, visible.minX + 12), visible.maxX - frame.width - 12)
        let y = min(max(proposedY, visible.minY + 12), visible.maxY - frame.height - 12)
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func position(near point: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) })
                ?? NSScreen.main ?? NSScreen.screens.first else {
            positionOnPointerScreen()
            return
        }
        let visible = screen.visibleFrame
        let proposedX = point.x - frame.width / 2
        let proposedY = point.y - frame.height / 2
        let x = min(max(proposedX, visible.minX + 12), visible.maxX - frame.width - 12)
        let y = min(max(proposedY, visible.minY + 12), visible.maxY - frame.height - 12)
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isPresenting else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            guard !self.isPresenting else { return }
            if let keyWin = NSApp.keyWindow, keyWin === self || keyWin.parent === self {
                return
            }
            if NSApp.isActive && self.isVisible {
                return
            }
            self.onLoseFocus?()
        }
    }
}
