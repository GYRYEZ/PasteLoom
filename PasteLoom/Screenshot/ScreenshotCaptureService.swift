import AppKit
import ScreenCaptureKit

enum ScreenshotPermission {
    static var isGranted: Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        if canCaptureScreen() {
            return true
        }
        return false
    }

    static func canCaptureScreen() -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let myPID = ProcessInfo.processInfo.processIdentifier
        for window in windowList {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != myPID else { continue }
            if window[kCGWindowName as String] != nil {
                return true
            }
        }
        return false
    }

    @discardableResult
    static func requestAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openSettings() {
        _ = CGRequestScreenCaptureAccess()
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct ScreenshotDocument: Identifiable {
    let id = UUID()
    let pngData: Data
}

enum ScreenshotCaptureError: LocalizedError {
    case noDisplay
    case encodingFailed
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDisplay: "找不到可截图的显示器。"
        case .encodingFailed: "无法将截图保存为 PNG。"
        case .captureFailed(let msg): "截图执行失败：\(msg)"
        }
    }
}

struct ScreenshotCaptureService {
    func captureCurrentDisplay() async throws -> ScreenshotDocument {
        let (image, _) = try await captureCurrentDisplayCGImage()
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw ScreenshotCaptureError.encodingFailed
        }
        return ScreenshotDocument(pngData: data)
    }

    func captureCurrentDisplayCGImage() async throws -> (cgImage: CGImage, display: SCDisplay?) {
        // Try ScreenCaptureKit first
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let mouse = NSEvent.mouseLocation
            let display = content.displays.first(where: { $0.frame.contains(mouse) }) ?? content.displays.first
            if let display {
                let own = Bundle.main.bundleIdentifier ?? "com.gyryez.pasteloom"
                let ownWindows = content.windows.filter {
                    let bid = $0.owningApplication?.bundleIdentifier
                    return bid == own || bid == "com.gyryez.pasteloom" || bid == "com.gyryez.pasteloom.next"
                }
                let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
                let configuration = SCStreamConfiguration()
                configuration.width = Int(display.width)
                configuration.height = Int(display.height)
                configuration.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                       configuration: configuration)
                return (image, display)
            }
        } catch {
            // ScreenCaptureKit failed, fallback to CoreGraphics
        }

        // Robust CoreGraphics Fallback
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { throw ScreenshotCaptureError.noDisplay }
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()

        if let cgImage = CGDisplayCreateImage(displayID) {
            return (cgImage, nil)
        }

        let rect = screen.frame
        if let cgImage = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution, .nominalResolution]) {
            return (cgImage, nil)
        }

        throw ScreenshotCaptureError.captureFailed("无法捕获屏幕图像，请检查屏幕录制权限。")
    }

    func fetchShareableWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let own = Bundle.main.bundleIdentifier ?? "com.gyryez.pasteloom"
        return content.windows.filter {
            let bid = $0.owningApplication?.bundleIdentifier
            return bid != own && bid != "com.gyryez.pasteloom" && bid != "com.gyryez.pasteloom.next" &&
            $0.frame.width > 50 && $0.frame.height > 50
        }
    }

    func captureWindow(window: SCWindow) async throws -> ScreenshotDocument {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width)
        configuration.height = Int(window.frame.height)
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                               configuration: configuration)
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw ScreenshotCaptureError.encodingFailed
        }
        return ScreenshotDocument(pngData: data)
    }

    func captureRegion(_ rect: CGRect, display: SCDisplay? = nil) async throws -> ScreenshotDocument {
        let (fullImage, fullDisplay) = try await captureCurrentDisplayCGImage()
        let targetDisplay = display ?? fullDisplay
        let targetWidth = CGFloat(targetDisplay?.width ?? fullImage.width)
        let targetHeight = CGFloat(targetDisplay?.height ?? fullImage.height)
        let scaleX = CGFloat(fullImage.width) / targetWidth
        let scaleY = CGFloat(fullImage.height) / targetHeight
        let pixelRect = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.size.width * scaleX,
            height: rect.size.height * scaleY
        ).integral
        guard let cropped = fullImage.cropping(to: pixelRect) else {
            throw ScreenshotCaptureError.captureFailed("无法裁切选区。")
        }
        guard let data = NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:]) else {
            throw ScreenshotCaptureError.encodingFailed
        }
        return ScreenshotDocument(pngData: data)
    }
}
