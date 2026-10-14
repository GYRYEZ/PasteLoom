import SwiftUI
import AppKit

enum PaperTheme: String, CaseIterable, Identifiable {
    case macosNative = "macos_native"

    init?(rawValue: String) {
        switch rawValue {
        case "macos_native":
            self = .macosNative
        default:
            // Gracefully migrate any legacy theme key to macosNative
            self = .macosNative
        }
    }

    var id: String { rawValue }
    var name: String { "macOS 原生毛玻璃" }
    var subtitle: String { "100% 遵循 Apple HIG 规范与通透磨砂底板" }

    func palette(for scheme: ColorScheme, accentOverride: PaperAccent?) -> PaperPalette {
        let colors: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)
        let backgroundOpacity: Double
        let cardOpacity: Double
        let isFrostedGlass: Bool = true
        let material: NSVisualEffectView.Material = .popover
        let blurAlpha: CGFloat

        if scheme == .dark {
            // 100% Apple HIG Sequoia/Sonoma Dark Mode Frosted Translucent Glass
            colors = (0x1C1C1E, 0x141416, 0x2C2C2E, 0x38383A, 0x0A84FF, 0xF2F2F7)
            backgroundOpacity = 0.22
            cardOpacity = 0.85
            blurAlpha = 0.95
        } else {
            // 100% Apple HIG Sequoia/Sonoma Light Mode Frosted Translucent Glass
            colors = (0xFFFFFF, 0xF2F2F7, 0xFFFFFF, 0xD1D1D6, 0x007AFF, 0x1C1C1E)
            backgroundOpacity = 0.20
            cardOpacity = 0.82
            blurAlpha = 0.94
        }
        let accentHex = accentOverride?.hex ?? colors.4
        return PaperPalette(
            background: colors.0,
            sidebar: colors.1,
            card: colors.2,
            border: colors.3,
            accent: accentHex,
            text: colors.5,
            isDark: scheme == .dark,
            backgroundOpacity: backgroundOpacity,
            cardOpacity: cardOpacity,
            isFrostedGlass: isFrostedGlass,
            material: material,
            blurAlpha: blurAlpha
        )
    }

    var palette: PaperPalette {
        palette(for: .light, accentOverride: nil)
    }
}

enum PaperAccent: String, CaseIterable, Identifiable {
    case theme, sage, terracotta, amber, lavender, teal, blue
    var id: String { rawValue }
    var name: String {
        switch self {
        case .theme: "跟随主题"
        case .sage: "鼠尾草"
        case .terracotta: "陶土"
        case .amber: "琥珀"
        case .lavender: "雾紫"
        case .teal: "雾青"
        case .blue: "经典蓝"
        }
    }
    var hex: UInt32 {
        switch self {
        case .theme: 0x007AFF
        case .sage: 0x488B5E
        case .terracotta: 0xDE634D
        case .amber: 0xD48E33
        case .lavender: 0x8C65D6
        case .teal: 0x3B9CA7
        case .blue: 0x2478E2
        }
    }

    var color: Color {
        Color(hex: hex)
    }
}

struct PaperPalette {
    var appBackground: Color { background }
    var drawerBackground: Color { background }
    let background: Color
    let sidebarBackground: Color
    let cardBackground: Color
    let cardBorder: Color
    var accent: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let divider: Color
    let shadow: Color
    let destructive = Color(red: 0.86, green: 0.31, blue: 0.30)
    let success = Color(red: 0.20, green: 0.62, blue: 0.40)
    let warning = Color(red: 0.87, green: 0.57, blue: 0.20)
    let cardCornerRadius: CGFloat = 16
    let controlCornerRadius: CGFloat = 12
    let sectionSpacing: CGFloat = 22
    let rowHeight: CGFloat = 58
    let sidebarWidth: CGFloat = 238
    let settingsContentWidth: CGFloat = 750
    let isDark: Bool
    let backgroundOpacity: Double
    let isFrostedGlass: Bool
    let material: NSVisualEffectView.Material
    let blurAlpha: CGFloat

    init(background: UInt32, sidebar: UInt32, card: UInt32, border: UInt32, accent: UInt32, text: UInt32,
         isDark: Bool = false,
         backgroundOpacity: Double = 0.82,
         cardOpacity: Double = 1.0,
         isFrostedGlass: Bool = false,
         material: NSVisualEffectView.Material = .sidebar,
         blurAlpha: CGFloat = 1.0) {
        self.isDark = isDark
        self.backgroundOpacity = backgroundOpacity
        self.isFrostedGlass = isFrostedGlass
        self.material = material
        self.blurAlpha = blurAlpha
        self.background = Color(hex: background)
        self.sidebarBackground = Color(hex: sidebar)
        self.cardBackground = Color(hex: card).opacity(cardOpacity)
        self.cardBorder = Color(hex: border)
        self.accent = Color(hex: accent)
        self.primaryText = Color(hex: text)
        self.secondaryText = Color(hex: text).opacity(0.70)
        self.tertiaryText = Color(hex: text).opacity(0.48)
        self.divider = Color(hex: border).opacity(0.72)
        self.shadow = Color.black.opacity(isDark ? 0.24 : 0.09)
    }

    func withAccent(_ accent: UInt32) -> PaperPalette {
        var copy = self
        copy.accent = Color(hex: accent)
        return copy
    }
}

// MARK: - Visual Effect Blur (Frosted Glass NSViewRepresentable)
public struct VisualEffectBlur: NSViewRepresentable {
    public var material: NSVisualEffectView.Material = .popover
    public var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    public var state: NSVisualEffectView.State = .active
    public var alpha: CGFloat = 1.0

    public init(material: NSVisualEffectView.Material = .popover,
                blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
                state: NSVisualEffectView.State = .active,
                alpha: CGFloat = 1.0) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
        self.alpha = alpha
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.alphaValue = alpha
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if nsView.material != material { nsView.material = material }
        if nsView.blendingMode != blendingMode { nsView.blendingMode = blendingMode }
        if nsView.state != state { nsView.state = state }
        if nsView.alphaValue != alpha { nsView.alphaValue = alpha }
    }
}

// MARK: - App-wide Appearance Manager
@MainActor
public final class AppearanceManager: ObservableObject {
    public static let shared = AppearanceManager()

    @Published public private(set) var isSystemDark: Bool = false

    private var distributedObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?

    private init() {
        updateSystemState()
        setupObservers()
    }

    public func updateSystemState() {
        var isDark = false
        let app = NSApplication.shared
        if let appearance = app.effectiveAppearance as NSAppearance? {
            let names: [NSAppearance.Name] = [.darkAqua, .aqua]
            if let best = appearance.bestMatch(from: names) {
                isDark = (best == .darkAqua)
            } else if let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") {
                isDark = (style == "Dark")
            }
        } else if let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") {
            isDark = (style == "Dark")
        }
        if isSystemDark != isDark {
            isSystemDark = isDark
            NotificationCenter.default.post(name: NSNotification.Name("SystemAppearanceDidChange"), object: nil)
        }
    }

    private func setupObservers() {
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateSystemState()
            }
        }

        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateSystemState()
            }
        }
    }

    public static func apply(mode: String) {
        let app = NSApplication.shared
        switch mode {
        case "dark":
            app.appearance = NSAppearance(named: .darkAqua)
        case "light":
            app.appearance = NSAppearance(named: .aqua)
        default:
            app.appearance = nil
            shared.updateSystemState()
        }
        NotificationCenter.default.post(name: NSNotification.Name("SystemAppearanceDidChange"), object: nil)
    }

    public static func effectiveColorScheme(for mode: String, environmentScheme: ColorScheme? = nil) -> ColorScheme {
        switch mode {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            // "system" - 严格遵循 macOS 系统选择
            if let environmentScheme {
                return environmentScheme
            }
            return shared.isSystemDark ? .dark : .light
        }
    }

    public static func currentWindowAppearance(for mode: String) -> NSAppearance? {
        switch mode {
        case "light":
            return NSAppearance(named: .aqua)
        case "dark":
            return NSAppearance(named: .darkAqua)
        default:
            return shared.isSystemDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}

// MARK: - Adaptive Media Card Presentation (HIG-compliant Light & Dark Mode Edge Separation)

public struct AdaptiveCardMediaFrameModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    var cornerRadius: CGFloat
    var shadowRadius: CGFloat
    var shadowY: CGFloat

    private var isDarkMode: Bool {
        AppearanceManager.effectiveColorScheme(for: appearanceMode, environmentScheme: colorScheme) == .dark
    }

    public init(cornerRadius: CGFloat = 6, shadowRadius: CGFloat = 5, shadowY: CGFloat = 2.5) {
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.shadowY = shadowY
    }

    public func body(content: Content) -> some View {
        content
            .background(
                isDarkMode
                    ? Color(nsColor: .controlBackgroundColor).opacity(0.85)
                    : Color(white: 0.98),
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        isDarkMode
                            ? Color.white.opacity(0.18)
                            : Color.black.opacity(0.13),
                        lineWidth: 0.75
                    )
            )
            .shadow(
                color: Color.black.opacity(isDarkMode ? 0.38 : 0.14),
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
            .shadow(
                color: Color.black.opacity(isDarkMode ? 0.20 : 0.08),
                radius: max(1, shadowRadius * 0.3),
                x: 0,
                y: max(0.5, shadowY * 0.25)
            )
    }
}

extension View {
    public func adaptiveCardMediaFrame(
        cornerRadius: CGFloat = 6,
        shadowRadius: CGFloat = 5,
        shadowY: CGFloat = 2.5
    ) -> some View {
        modifier(AdaptiveCardMediaFrameModifier(
            cornerRadius: cornerRadius,
            shadowRadius: shadowRadius,
            shadowY: shadowY
        ))
    }
}
