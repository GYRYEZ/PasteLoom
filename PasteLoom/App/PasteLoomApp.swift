import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var runtime: AppRuntime?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.runtime?.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let runtime = AppDelegate.runtime else { return true }
        guard !runtime.quickPaste.isQuickPasteActive && !runtime.quickPaste.wasRecentlyActive else { return true }
        runtime.showMainWindow()
        return true
    }
}

@main
struct PasteLoomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var runtime = AppRuntime()
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @AppStorage("appearanceMode") private var appearanceMode = "system"

    init() {
        // Keep the system Dock icon sourced from the bundled PasteLoom asset catalog.
        // Runtime overrides can diverge from the Launch Services icon used by Dock Door.
        applyFirstLaunchLayoutDefaults()
        let storedMode = UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"
        AppearanceManager.apply(mode: storedMode)
    }

    private func applyFirstLaunchLayoutDefaults() {
        let key = "hasAppliedFirstLaunchLayoutDefaults_v2"
        if !UserDefaults.standard.bool(forKey: key) {
            let edge = UserDefaults.standard.string(forKey: "drawerEdge") ?? "left"
            let initialLayout: String
            if edge == "bottom" || edge == "top" {
                initialLayout = "horizontal" // 底部或顶部默认网格卡片展示
            } else {
                initialLayout = "list" // 左右两侧默认列表显示
            }
            UserDefaults.standard.set(initialLayout, forKey: "historyLayout")
            UserDefaults.standard.set(true, forKey: key)
            UserDefaults.standard.synchronize()
        }
    }

    var body: some Scene {
        WindowGroup("PasteLoom", id: "history") {
            HistoryView(model: runtime.model, runtime: runtime)
                .preferredColorScheme(colorScheme)
                .ignoresSafeArea()
                .onAppear {
                    AppearanceManager.apply(mode: appearanceMode)
                    runtime.start()
                }
        }
        .defaultSize(width: 340, height: 800)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarHistoryView(runtime: runtime)
                .preferredColorScheme(colorScheme)
                .onAppear {
                    AppearanceManager.apply(mode: appearanceMode)
                    runtime.start()
                }
        } label: {
            if let img = menuBarImage {
                Image(nsImage: img)
            } else {
                Image(systemName: "square.on.square")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(runtime: runtime)
                .preferredColorScheme(colorScheme)
                .onAppear {
                    AppearanceManager.apply(mode: appearanceMode)
                }
        }
    }

    private var menuBarImage: NSImage? {
        if let url = Bundle.main.url(forResource: "menu_bar_2x", withExtension: "png") ?? Bundle.main.url(forResource: "menu_bar_1x", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            return img
        }
        return nil
    }

    private var colorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": .light
        case "dark": .dark
        default: (appearanceManager.isSystemDark ? .dark : .light)
        }
    }
}
