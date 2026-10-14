import AppKit
import Foundation

enum EdgeHoverSide: String, CaseIterable, Identifiable {
    case follow = "follow"
    case left = "left"
    case right = "right"
    case top = "top"
    case bottom = "bottom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .follow: "跟随磁吸方位"
        case .left: "左侧"
        case .right: "右侧"
        case .top: "顶侧"
        case .bottom: "底侧"
        }
    }
}

@MainActor
final class EdgeHoverMonitor {
    var onTrigger: (() -> Void)?

    private var timer: Timer?
    private var hoverStartTime: Date?
    private var didTriggerInCurrentHover = false
    private let thresholdDistance: CGFloat = 4.0
    private var isDrawerExpanded = false
    private var drawerStateObserver: Any?
    private var drawerEdgeObserver: Any?

    init() {
        drawerStateObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DrawerStateDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] notif in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isDrawerExpanded = notif.object as? Bool ?? false
                if self.isDrawerExpanded {
                    self.hoverStartTime = nil
                    self.didTriggerInCurrentHover = false
                }
            }
        }

        drawerEdgeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DrawerEdgeDidChange"),
            object: nil,
            queue: .main
        ) { notif in
            if let edge = notif.object as? String {
                let configured = UserDefaults.standard.string(forKey: "edgeHoverSide") ?? "follow"
                if configured != "follow" {
                    UserDefaults.standard.set(edge, forKey: "edgeHoverSide")
                }
            }
        }
    }

    func start() {
        stop()
        let newTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkPointer()
            }
        }
        newTimer.tolerance = 0.02
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        hoverStartTime = nil
        didTriggerInCurrentHover = false
    }

    deinit {
        timer?.invalidate()
        if let drawerStateObserver {
            NotificationCenter.default.removeObserver(drawerStateObserver)
        }
        if let drawerEdgeObserver {
            NotificationCenter.default.removeObserver(drawerEdgeObserver)
        }
    }

    func checkPointer() {
        autoreleasepool {
            if isDrawerExpanded {
                hoverStartTime = nil
                didTriggerInCurrentHover = false
                return
            }
            if AppDelegate.runtime?.quickPaste.isQuickPasteActive == true || AppDelegate.runtime?.quickPaste.wasRecentlyActive == true {
                hoverStartTime = nil
                didTriggerInCurrentHover = false
                return
            }

            let hoverEnabled = UserDefaults.standard.object(forKey: "edgeHoverEnabled") == nil ? true : UserDefaults.standard.bool(forKey: "edgeHoverEnabled")
            let autoHideEnabled = UserDefaults.standard.object(forKey: "edgeAutoHide") == nil ? true : UserDefaults.standard.bool(forKey: "edgeAutoHide")
            guard hoverEnabled || autoHideEnabled else {
                hoverStartTime = nil
                didTriggerInCurrentHover = false
                return
            }

            let mouse = NSEvent.mouseLocation
            let screen: NSScreen
            if let main = NSScreen.main, main.frame.insetBy(dx: -4, dy: -4).contains(mouse) {
                screen = main
            } else if let matched = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -4, dy: -4).contains(mouse) }) {
                screen = matched
            } else if let main = NSScreen.main {
                screen = main
            } else {
                hoverStartTime = nil
                didTriggerInCurrentHover = false
                return
            }

            let configuredSide = UserDefaults.standard.string(forKey: "edgeHoverSide") ?? "follow"
            let drawerEdge = UserDefaults.standard.string(forKey: "drawerEdge") ?? "bottom"
            let effectiveSide: String = (configuredSide == "follow" || configuredSide.isEmpty) ? drawerEdge : configuredSide

            let frame = screen.frame
            let visible = screen.visibleFrame
            let isAtEdge: Bool
            switch effectiveSide {
            case "left":
                isAtEdge = (mouse.x <= frame.minX + 8.0)
            case "right":
                isAtEdge = (mouse.x >= frame.maxX - 8.0)
            case "top":
                // Strict physical screen top / menu bar edge detection
                isAtEdge = (mouse.y >= frame.maxY - 5.0 || mouse.y >= visible.maxY - 5.0)
            case "bottom":
                // Strict physical screen bottom detection: cursor must be completely pressed against screen bottom bezel (not above Dock)
                isAtEdge = (mouse.y <= frame.minY + 1.5)
            default:
                isAtEdge = (mouse.y <= frame.minY + 1.5)
            }

            if isAtEdge {
                if hoverStartTime == nil {
                    hoverStartTime = Date()
                }
                let delay = UserDefaults.standard.double(forKey: "edgeHoverDelay")
                let requiredDelay = delay > 0.05 ? delay : 0.35
                if let start = hoverStartTime, Date().timeIntervalSince(start) >= requiredDelay {
                    if !didTriggerInCurrentHover {
                        didTriggerInCurrentHover = true
                        onTrigger?()
                        NotificationCenter.default.post(name: NSNotification.Name("EdgeHoverExpandDrawer"), object: nil)
                    }
                }
            } else {
                hoverStartTime = nil
                didTriggerInCurrentHover = false
            }
        }
    }

    static func isPointNearEdge(_ point: NSPoint, in frame: NSRect, side: String, threshold: CGFloat = 4.0) -> Bool {
        switch side {
        case "left": return point.x <= frame.minX + threshold
        case "right": return point.x >= frame.maxX - threshold
        case "top": return point.y >= frame.maxY - max(threshold, 18.0)
        case "bottom": return point.y <= frame.minY + threshold
        default: return point.x <= frame.minX + threshold
        }
    }
}
