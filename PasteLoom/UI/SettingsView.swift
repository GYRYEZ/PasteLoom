import AppKit
import SwiftUI

private enum SettingsCategory: String, CaseIterable, Identifiable {
    // 常规与外观
    case appearance = "外观与布局"
    case windowAndBehavior = "窗口与行为"
    case panelAndPreview = "面板与预览"

    // 快捷键与权限
    case shortcuts = "快捷键绑定"
    case accessibility = "辅助功能权限"

    // 截图标注
    case screenshot = "截图标注"

    // 数据与存储
    case capture = "剪贴板捕获"
    case captureFilter = "捕获与过滤"
    case sensitiveContent = "内容保护"
    case merge = "合并行为"
    case retention = "存储与保留"
    case sync = "数据同步"
    case importExport = "导入与导出"

    // 规则与自动化
    case rules = "规则与脚本"
    case logs = "运行记录"

    // 智能 AI
    case mcpServers = "MCP 服务"
    case aiClients = "AI 客户端"
    case availableTools = "可用工具"

    // 系统
    case about = "关于"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .appearance: "paintpalette"
        case .windowAndBehavior: "macwindow"
        case .panelAndPreview: "square.grid.2x2"
        case .shortcuts: "keyboard"
        case .accessibility: "checkmark.shield"
        case .screenshot: "viewfinder"
        case .capture: "waveform"
        case .captureFilter: "line.3.horizontal.decrease.circle"
        case .sensitiveContent: "shield.lefthalf.filled"
        case .merge: "arrow.triangle.merge"
        case .retention: "archivebox"
        case .sync: "arrow.triangle.2.circlepath"
        case .importExport: "square.and.arrow.up"
        case .rules: "bolt.badge.a"
        case .logs: "clock.arrow.circlepath"
        case .mcpServers: "network"
        case .aiClients: "sparkles"
        case .availableTools: "wrench.and.screwdriver"
        case .about: "info.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance: "选择纸张风格、明暗外观和界面布局"
        case .windowAndBehavior: "配置边缘悬停呼出、Dock 显示与开机启动"
        case .panelAndPreview: "设置主抽屉、快速粘贴和菜单栏面板布局与悬停预览"
        case .shortcuts: "自定义全局热键与快捷面板操作"
        case .accessibility: "检测自动粘贴需要的系统授权"
        case .screenshot: "屏幕截图标注、快捷键与 Vision 离线文字识别"
        case .capture: "查看本地存储与剪贴板监听状态"
        case .captureFilter: "配置黑名单应用、排除文本规则与内容类型"
        case .sensitiveContent: "本地敏感信息脱敏遮蔽与防泄漏保护"
        case .merge: "多条目拼接与批量文本合并设置"
        case .retention: "自动淘汰清理、保护策略与复制使用统计"
        case .sync: "配置多端同步适配器 (iCloud、WebDAV、S3、本地目录)"
        case .importExport: "SQLite 数据库物理备份、通用 JSON 导出与数据合并恢复"
        case .rules: "配置条件动作自动化规则与 JavaScript 脚本沙盒"
        case .logs: "查看自动化规则触发与脚本运行日志"
        case .mcpServers: "配置轻量级本地 MCP (Model Context Protocol) 监听服务"
        case .aiClients: "配置并探测 Claude Desktop、DeepSeek Harness、Cursor 及 VSCode 本地接入"
        case .availableTools: "查看向本地 AI 智能体开放的剪贴板历史搜索与整理工具"
        case .about: "版本信息与关于 PasteLoom"
        }
    }
}

private struct SettingsSection: Identifiable {
    let id: String
    let title: String
    let categories: [SettingsCategory]
}

private let settingsSections: [SettingsSection] = [
    SettingsSection(id: "general", title: "常规与外观", categories: [.appearance, .windowAndBehavior, .panelAndPreview]),
    SettingsSection(id: "shortcuts", title: "快捷键与权限", categories: [.shortcuts, .accessibility]),
    SettingsSection(id: "screenshot", title: "截图标注", categories: [.screenshot]),
    SettingsSection(id: "data", title: "数据与存储", categories: [.capture, .captureFilter, .sensitiveContent, .merge, .retention, .sync, .importExport]),
    SettingsSection(id: "automation", title: "自动化与扩展", categories: [.rules, .logs]),
    SettingsSection(id: "ai", title: "智能 AI", categories: [.mcpServers, .aiClients, .availableTools]),
    SettingsSection(id: "about", title: "系统", categories: [.about])
]

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var runtime: AppRuntime
    private var model: AppModel { runtime.model }
    private var accessibility: AccessibilityService { runtime.accessibility }

    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("themePreset") private var themePreset = PaperTheme.macosNative.rawValue
    @AppStorage("accentColor") private var accentColor = PaperAccent.theme.rawValue
    @AppStorage("drawerEdge") private var drawerEdge = "left"
    @AppStorage("historyLayout") private var historyLayout = "list"
    @AppStorage("quickPasteLayout") private var quickPasteLayout = "list"
    @AppStorage("cleanURLs") private var cleanURLs = false
    @AppStorage("excludeTextCapture") private var excludeTextCapture = false
    @AppStorage("excludeURLCapture") private var excludeURLCapture = false
    @AppStorage("excludeImageCapture") private var excludeImageCapture = false
    @AppStorage("excludeFileCapture") private var excludeFileCapture = false
    @AppStorage("tagMatchMode") private var tagMatchMode = TagMatchMode.any.rawValue

    // Window and behavior settings (Stage 2)
    @AppStorage("windowAlwaysOnTop") private var windowAlwaysOnTop = true
    @AppStorage("edgeAutoHide") private var edgeAutoHide = true
    @AppStorage("edgeHoverEnabled") private var edgeHoverEnabled = true
    @AppStorage("edgeHoverSide") private var edgeHoverSide = "follow"
    @AppStorage("edgeHoverDelay") private var edgeHoverDelay = 0.4
    @AppStorage("showInDock") private var showInDock = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("doubleClickToPaste") private var doubleClickToPaste = true
    @AppStorage("cleanTrailingWhitespace") private var cleanTrailingWhitespace = false
    @AppStorage("cursorAssistantEnabled") private var cursorAssistantEnabled = true

    // Panel and preview settings (Stage 2)
    @AppStorage("menuBarLayout") private var menuBarLayout = "list"
    @AppStorage("menuBarHoverEnabled") private var menuBarHoverEnabled = true
    @AppStorage("menuBarHoverDelay") private var menuBarHoverDelay = 0.5
    @AppStorage("quickPasteHoverEnabled") private var quickPasteHoverEnabled = true
    @AppStorage("quickPasteHoverDelay") private var quickPasteHoverDelay = 0.5

    // Media and OCR settings (Stage 3)
    @AppStorage("autoOCR") private var autoOCR = true
    @AppStorage("captureScreenshotsToHistory") private var captureScreenshotsToHistory = true

    // Stage 4 services & states
    @ObservedObject private var filterService = CaptureFilterService.shared
    @ObservedObject private var retentionEngine = RetentionEngine.shared
    @AppStorage("sensitive_masking_enabled") private var sensitiveMaskingEnabled = true
    @AppStorage("defaultMergeSeparator") private var defaultMergeSeparator = "\n"
    @AppStorage("defaultMergeAutoCopy") private var defaultMergeAutoCopy = true
    @ObservedObject private var localizationService = LocalizationService.shared

    @State private var showAddAppSheet = false
    @State private var newAppName = ""
    @State private var newAppBundleID = ""

    @State private var showAddRuleSheet = false
    @State private var newRuleName = ""
    @State private var newRulePattern = ""
    @State private var newRuleKind: TextMatchKind = .contains

    @State private var testSensitiveInput = "手机 13812345678, 邮箱 dev@example.com, 身份证 110101199003072345, Token: Bearer sk-secret1234567890abcdef"
    @State private var retentionAlertMessage: String?
    @State private var isRunningRetention = false

    @State private var selectedCategory: SettingsCategory = .appearance
    @State private var accessibilityGranted = false
    @State private var screenshotGranted = false

    @State private var recordingAction: ShortcutAction?
    @State private var shortcutMonitor: Any?
    @State private var shortcutHint = ""
    @State private var shortcutConflictMessage: String?

    private var effectiveColorScheme: ColorScheme {
        AppearanceManager.effectiveColorScheme(for: appearanceMode, environmentScheme: colorScheme)
    }

    private var palette: PaperPalette {
        let accent = PaperAccent(rawValue: accentColor)
        return (PaperTheme(rawValue: themePreset) ?? .macosNative)
            .palette(for: effectiveColorScheme, accentOverride: accent == .theme ? nil : accent)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(palette.divider).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    pageHeader
                    pageContent
                }
                .frame(maxWidth: palette.settingsContentWidth, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(palette.background.opacity(0.73))
        }
        .frame(minWidth: 860, idealWidth: 1040, minHeight: 620, idealHeight: 760)
        .background(palette.background)
        .background {
            SettingsWindowTitleBridge(title: "PasteLoom 设置")
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .foregroundStyle(palette.primaryText)
        .tint(palette.accent)
        .preferredColorScheme(appearanceMode == "light" ? .light : appearanceMode == "dark" ? .dark : (appearanceManager.isSystemDark ? .dark : .light))
        .onChange(of: appearanceMode) { _, newMode in
            AppearanceManager.apply(mode: newMode)
        }
        .onAppear {
            AppearanceManager.apply(mode: appearanceMode)
            refreshPermissions()
            launchAtLogin = LaunchAtLoginService.isEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
        .onDisappear { stopShortcutRecording() }
        .sheet(isPresented: $showAddAppSheet) { addAppSheet }
        .sheet(isPresented: $showAddRuleSheet) { addRuleSheet }
        .alert("保留清理结果", isPresented: Binding(
            get: { retentionAlertMessage != nil },
            set: { if !$0 { retentionAlertMessage = nil } }
        )) {
            Button("好") { retentionAlertMessage = nil }
        } message: {
            Text(retentionAlertMessage ?? "")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                AppLogoView(size: 24, cornerRadius: 6, showShadow: true)
                Text("PasteLoom")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Rectangle().fill(palette.divider).frame(height: 1)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(settingsSections) { section in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.secondaryText)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 2)

                            ForEach(section.categories) { cat in
                                sidebarItem(cat)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
        }
        .frame(width: palette.sidebarWidth)
        .background(palette.sidebarBackground)
    }

    private func sidebarItem(_ cat: SettingsCategory) -> some View {
        Button {
            selectedCategory = cat
        } label: {
            HStack(spacing: 9) {
                Image(systemName: cat.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18, alignment: .center)
                    .foregroundStyle(selectedCategory == cat ? palette.accent : palette.secondaryText)
                Text(cat.rawValue)
                    .font(.system(size: 13, weight: selectedCategory == cat ? .semibold : .regular))
                    .foregroundStyle(selectedCategory == cat ? palette.primaryText : palette.primaryText.opacity(0.85))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                selectedCategory == cat
                    ? palette.accent.opacity(0.14)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cat.rawValue)
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedCategory.rawValue)
                .font(.title2.weight(.bold))
                .foregroundStyle(palette.primaryText)
            Text(selectedCategory.subtitle)
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder private var pageContent: some View {
        switch selectedCategory {
        case .appearance:
            appearancePage
        case .windowAndBehavior:
            windowAndBehaviorPage
        case .panelAndPreview:
            panelPage
        case .shortcuts:
            shortcutPage
        case .accessibility:
            accessibilityPage
        case .screenshot:
            screenshotUnifiedPage
        case .capture:
            capturePage
        case .captureFilter:
            captureFilterPage
        case .sensitiveContent:
            sensitiveContentPage
        case .merge:
            mergeSettingsPage
        case .retention:
            retentionAndStatsPage
        case .sync:
            SyncSettingsView(repository: model.repository, palette: palette)
        case .importExport:
            ImportExportSettingsView(repository: model.repository, palette: palette)
        case .rules:
            RulesAndScriptsView(palette: palette)
        case .logs:
            ExecutionLogsView(palette: palette)
        case .mcpServers:
            MCPServerConfigView(palette: palette)
        case .aiClients:
            AIClientsConfigView(palette: palette)
        case .availableTools:
            MCPAvailableToolsView(palette: palette)
        case .about:
            AboutSettingsView(palette: palette, repository: model.repository)
        }
    }

    private var appearancePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("设计系统与外观主题")
                sectionCard {
                    let tp = PaperTheme.macosNative.palette(for: effectiveColorScheme, accentOverride: nil)
                    HStack(spacing: 14) {
                        // macOS 原生磨砂质感卡片微缩预览
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(tp.background)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(tp.cardBorder.opacity(0.85), lineWidth: 1))

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Circle().fill(palette.accent).frame(width: 6, height: 6)
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(tp.primaryText.opacity(0.55))
                                        .frame(width: 24, height: 3)
                                }
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(tp.primaryText.opacity(0.30))
                                    .frame(width: 36, height: 2.5)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(tp.cardBackground, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(tp.cardBorder, lineWidth: 0.8))
                            .padding(.leading, 8)
                        }
                        .frame(width: 68, height: 42)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(PaperTheme.macosNative.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(palette.primaryText)
                                Text("原生磨砂")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(palette.accent.opacity(0.15), in: Capsule())
                                    .foregroundStyle(palette.accent)
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(palette.accent)
                            }
                            Text(PaperTheme.macosNative.subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                    .padding(4)
                }
            }
            sectionCard {
                settingRow("屏幕边缘停靠", detail: "主抽屉会移动到所选屏幕边缘", icon: "rectangle.split.2x1") {
                    Picker("屏幕边缘停靠", selection: Binding(
                        get: { drawerEdge },
                        set: { value in
                            drawerEdge = value
                            edgeHoverSide = value
                            let targetLayout = (value == "bottom" || value == "top") ? "horizontal" : "list"
                            historyLayout = targetLayout
                            UserDefaults.standard.set(value, forKey: "drawerEdge")
                            UserDefaults.standard.set(value, forKey: "edgeHoverSide")
                            UserDefaults.standard.set(targetLayout, forKey: "historyLayout")
                            UserDefaults.standard.synchronize()
                            NotificationCenter.default.post(name: NSNotification.Name("DrawerEdgeDidChange"), object: value)
                            NotificationCenter.default.post(name: NSNotification.Name("SnapDrawerEdge"), object: value)
                        }
                    )) {
                        Text("左侧").tag("left")
                        Text("右侧").tag("right")
                        Text("顶侧").tag("top")
                        Text("底侧").tag("bottom")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }
                rowDivider
                settingRow("外观模式", detail: "明暗外观立即生效；选择“跟随系统”或“设计系统”时严格遵循 macOS", icon: "circle.lefthalf.filled") {
                    Picker("外观模式", selection: $appearanceMode) {
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                        Text("跟随系统").tag("system")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 210)
                }
                rowDivider
                settingRow("强调色", detail: "用于按钮、高亮与当前选中指示", icon: "paintpalette") {
                    HStack(spacing: 8) {
                        ForEach(PaperAccent.allCases) { accent in
                            Button { accentColor = accent.rawValue } label: {
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 22, height: 22)
                                    .overlay(Circle().stroke(palette.cardBackground, lineWidth: 2))
                                    .overlay(accentColor == accent.rawValue ?
                                             Circle().stroke(palette.accent, lineWidth: 2) : nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                rowDivider
                settingRow("界面语言", detail: "切换应用显示语言 (Language)", icon: "character.book.closed") {
                    Picker("语言", selection: $localizationService.language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
            }
        }
    }

    private var windowAndBehaviorPage: some View {
        VStack(spacing: 20) {
            sectionCard {
                settingRow("保持窗口置于最顶层", detail: "开启时呼出主窗口悬浮在所有程序之上；关闭时仅在无其他窗口遮挡时保持在 Dock 栏之上", icon: "square.stack.3d.up.fill") {
                    Toggle("置于最顶层", isOn: Binding(
                        get: { windowAlwaysOnTop },
                        set: { newValue in
                            windowAlwaysOnTop = newValue
                            NotificationCenter.default.post(name: NSNotification.Name("WindowAlwaysOnTopDidChange"), object: newValue)
                        }
                    )).labelsHidden()
                }
                rowDivider
                settingRow("靠边自动隐藏", detail: "抽屉贴靠屏幕边缘时，鼠标移出后自动折叠入边缘，靠近时自动滑出", icon: "arrow.left.and.right.square") {
                    Toggle("靠边自动隐藏", isOn: $edgeAutoHide).labelsHidden()
                }
                rowDivider
                settingRow("启用边缘悬停呼出", detail: "鼠标指针在屏幕边缘停留后自动滑出主窗口", icon: "cursorarrow.rays") {
                    Toggle("边缘悬停", isOn: $edgeHoverEnabled).labelsHidden()
                }
                rowDivider
                settingRow("触发悬停位置", detail: "选择呼出主窗口的屏幕边缘（默认跟随停靠方位）", icon: "rectangle.split.2x1") {
                    Picker("悬停位置", selection: Binding(
                        get: { edgeHoverSide },
                        set: { newSide in
                            edgeHoverSide = newSide
                            UserDefaults.standard.set(newSide, forKey: "edgeHoverSide")
                            if newSide != "follow" {
                                drawerEdge = newSide
                                UserDefaults.standard.set(newSide, forKey: "drawerEdge")
                                let targetLayout = (newSide == "bottom" || newSide == "top") ? "horizontal" : "list"
                                historyLayout = targetLayout
                                UserDefaults.standard.set(targetLayout, forKey: "historyLayout")
                                UserDefaults.standard.synchronize()
                                NotificationCenter.default.post(name: NSNotification.Name("DrawerEdgeDidChange"), object: newSide)
                                NotificationCenter.default.post(name: NSNotification.Name("SnapDrawerEdge"), object: newSide)
                            }
                        }
                    )) {
                        ForEach(EdgeHoverSide.allCases) { side in
                            Text(side.displayName).tag(side.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 135)
                }
                rowDivider
                settingRow("触发悬停时长", detail: "控制需持续停留的时间，减少误触", icon: "timer") {
                    Picker("悬停时长", selection: $edgeHoverDelay) {
                        Text("0.2 秒").tag(0.2)
                        Text("0.4 秒（推荐）").tag(0.4)
                        Text("0.6 秒").tag(0.6)
                        Text("1.0 秒").tag(1.0)
                    }
                    .labelsHidden()
                    .frame(width: 135)
                }
            }

            sectionCard {
                settingRow("开机自启", detail: "登录系统时自动在后台启动 PasteLoom", icon: "power") {
                    Toggle("开机自启", isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            do {
                                try LaunchAtLoginService.setEnabled(newValue)
                                launchAtLogin = newValue
                            } catch {
                                shortcutConflictMessage = "设置开机自启失败：\(error.localizedDescription)"
                            }
                        }
                    )).labelsHidden()
                }
                rowDivider
                settingRow("在 Dock 中显示", detail: "开启后在 Dock 栏保留图标，关闭后仅保留菜单栏入口", icon: "dock.rectangle") {
                    Toggle("在 Dock 中显示", isOn: Binding(
                        get: { showInDock },
                        set: { newValue in
                            showInDock = newValue
                            DockVisibilityService.apply(showInDock: newValue)
                        }
                    )).labelsHidden()
                }
                rowDivider
                settingRow("光标助手", detail: "连按三次 Shift 键在打字光标附近呼出快捷浮窗", icon: "hand.tap") {
                    Toggle("光标助手", isOn: $cursorAssistantEnabled).labelsHidden()
                }
                rowDivider
                settingRow("双击卡片直接粘贴", detail: "开启时双击自动粘贴并关闭；关闭时双击预览", icon: "cursorarrow.click.2") {
                    Toggle("双击粘贴", isOn: $doubleClickToPaste).labelsHidden()
                }
                rowDivider
                settingRow("复制时清理末尾空白", detail: "从历史中再次复制文本时自动剔除结尾多余空白符", icon: "text.badge.minus") {
                    Toggle("清理空白", isOn: $cleanTrailingWhitespace).labelsHidden()
                }
            }
        }
    }

    private var capturePage: some View {
        VStack(spacing: 20) {
            sectionCard {
                settingRow("监听状态", detail: "控制是否自动记录复制内容", icon: "waveform") {
                    Toggle("剪贴板监听", isOn: Binding(
                        get: { model.isCapturing },
                        set: { model.setCaptureEnabled($0) }
                    )).labelsHidden()
                }
                rowDivider
                settingRow("监听间隔", detail: "检测剪贴板变更的轮询周期", icon: "clock") {
                    Picker("监听间隔", selection: Binding(
                        get: { model.pollInterval },
                        set: { model.setPollInterval($0) }
                    )) {
                        Text("0.2 秒（最灵敏）").tag(0.2)
                        Text("0.3 秒").tag(0.3)
                        Text("0.5 秒（标准）").tag(0.5)
                        Text("1.0 秒（节能）").tag(1.0)
                    }
                    .labelsHidden()
                    .frame(width: 135)
                }
                rowDivider
                settingRow("本机存储", detail: "历史保存在 Application Support 中", icon: "externaldrive") {
                    Text("仅此 Mac").foregroundStyle(palette.secondaryText)
                }
            }
        }
    }

    private var captureFilterPage: some View {
        VStack(spacing: 20) {
            sectionCard {
                settingRow("净化链接", detail: "新复制的网页链接移除 utm_*、fbclid、gclid 等追踪参数；保留其他参数", icon: "link") {
                    Toggle("净化链接", isOn: $cleanURLs).labelsHidden()
                }
                rowDivider
                settingRow("标签匹配", detail: "选择多个标签时，匹配任一标签或全部标签", icon: "tag") {
                    Picker("标签匹配", selection: $tagMatchMode) {
                        Text("任一").tag(TagMatchMode.any.rawValue)
                        Text("全部").tag(TagMatchMode.all.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                sectionLabel("排除的类型")
                sectionCard {
                    settingRow("文本", detail: "不保存新复制的纯文本", icon: "doc.text") {
                        Toggle("排除文本", isOn: $excludeTextCapture).labelsHidden()
                    }
                    rowDivider
                    settingRow("链接", detail: "不保存新复制的网页链接", icon: "link") {
                        Toggle("排除链接", isOn: $excludeURLCapture).labelsHidden()
                    }
                    rowDivider
                    settingRow("图片", detail: "不保存新复制的图片", icon: "photo") {
                        Toggle("排除图片", isOn: $excludeImageCapture).labelsHidden()
                    }
                    rowDivider
                    settingRow("文件", detail: "不保存新复制的单个或多个文件引用", icon: "folder") {
                        Toggle("排除文件", isOn: $excludeFileCapture).labelsHidden()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    sectionLabel("排除的应用黑名单")
                    Spacer()
                    Button {
                        newAppName = ""
                        newAppBundleID = ""
                        showAddAppSheet = true
                    } label: {
                        Label("添加应用", systemImage: "plus")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }
                sectionCard {
                    if filterService.excludedApps.isEmpty {
                        Text("暂无排除的应用").font(.caption).foregroundStyle(palette.secondaryText).padding(16)
                    } else {
                        ForEach(filterService.excludedApps) { app in
                            settingRow(app.name, detail: app.bundleIdentifier.isEmpty ? "依名称匹配" : app.bundleIdentifier, icon: "app.badge.checkmark") {
                                HStack(spacing: 12) {
                                    Toggle("", isOn: Binding(
                                        get: { app.isEnabled },
                                        set: { _ in filterService.toggleApp(id: app.id) }
                                    )).labelsHidden()
                                    Button {
                                        filterService.removeApp(id: app.id)
                                    } label: {
                                        Image(systemName: "trash").font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(palette.destructive)
                                }
                            }
                            if app.id != filterService.excludedApps.last?.id {
                                rowDivider
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    sectionLabel("排除的文本匹配规则")
                    Spacer()
                    Button {
                        newRuleName = ""
                        newRulePattern = ""
                        newRuleKind = .contains
                        showAddRuleSheet = true
                    } label: {
                        Label("添加规则", systemImage: "plus")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }
                sectionCard {
                    if filterService.excludedTextRules.isEmpty {
                        Text("暂无文本排除规则").font(.caption).foregroundStyle(palette.secondaryText).padding(16)
                    } else {
                        ForEach(filterService.excludedTextRules) { rule in
                            settingRow(rule.name.isEmpty ? rule.pattern : rule.name,
                                       detail: "匹配模式：\(rule.matchKind.rawValue) · 规则：\(rule.pattern)",
                                       icon: "text.badge.xmark") {
                                HStack(spacing: 12) {
                                    Toggle("", isOn: Binding(
                                        get: { rule.isEnabled },
                                        set: { _ in filterService.toggleTextRule(id: rule.id) }
                                    )).labelsHidden()
                                    Button {
                                        filterService.removeTextRule(id: rule.id)
                                    } label: {
                                        Image(systemName: "trash").font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(palette.destructive)
                                }
                            }
                            if rule.id != filterService.excludedTextRules.last?.id {
                                rowDivider
                            }
                        }
                    }
                }
            }
        }
    }

    private var sensitiveContentPage: some View {
        VStack(spacing: 20) {
            sectionCard {
                settingRow("启用敏感信息遮蔽", detail: "在历史列表与卡片中实时遮蔽手机号、身份证、银行卡、邮箱与 API Key", icon: "shield.lefthalf.filled") {
                    Toggle("脱敏遮蔽", isOn: $sensitiveMaskingEnabled).labelsHidden()
                }
            }

            sectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("支持遮蔽的敏感数据类型").font(.subheadline.weight(.semibold))
                    HStack(spacing: 8) {
                        ForEach(SensitiveKind.allCases, id: \.rawValue) { kind in
                            Label(kind.rawValue, systemImage: "checkmark.seal.fill")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(palette.accent.opacity(0.12), in: Capsule())
                                .foregroundStyle(palette.accent)
                        }
                    }
                    Text("• 纯本地端侧脱敏：使用本地正则引擎计算，不发起任何网络请求。")
                        .font(.caption).foregroundStyle(palette.secondaryText)
                    Text("• 数据安全：脱敏仅影响界面呈现与防窥视，本地 SQLite 数据库中的原始内容完整无损。")
                        .font(.caption).foregroundStyle(palette.secondaryText)
                }
                .padding(18)
            }

            VStack(alignment: .leading, spacing: 9) {
                sectionLabel("实时脱敏效果预览")
                sectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("输入测试文本：").font(.caption.weight(.semibold))
                        TextField("测试文本", text: $testSensitiveInput)
                            .textFieldStyle(.roundedBorder)

                        Text("脱敏处理后：").font(.caption.weight(.semibold))
                        let maskedResult = SensitiveContentService.shared.mask(text: testSensitiveInput)
                        Text(maskedResult.maskedText)
                            .font(.callout.monospaced())
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))

                        if maskedResult.hasSensitive {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.shield.fill").foregroundStyle(palette.warning)
                                Text("检测到敏感项：\(maskedResult.detectedKinds.map(\.rawValue).joined(separator: "、"))")
                                    .font(.caption).foregroundStyle(palette.warning)
                            }
                        }
                    }
                    .padding(18)
                }
            }
        }
    }

    private var mergeSettingsPage: some View {
        VStack(spacing: 20) {
            sectionCard {
                settingRow("默认合并分隔符", detail: "多条目合并时默认使用的文本连接符", icon: "arrow.triangle.merge") {
                    Picker("分隔符", selection: $defaultMergeSeparator) {
                        Text("换行 (\\n)").tag("\n")
                        Text("段落 (\\n\\n)").tag("\n\n")
                        Text("空格").tag(" ")
                        Text("逗号").tag("，")
                    }
                    .frame(width: 140)
                    .labelsHidden()
                }
                rowDivider
                settingRow("合并后自动复制", detail: "完成多条目拼接后立即将生成的新条目写入系统剪贴板", icon: "doc.on.clipboard") {
                    Toggle("自动复制", isOn: $defaultMergeAutoCopy).labelsHidden()
                }
            }

            sectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("如何使用多条目合并").font(.subheadline.weight(.semibold))
                    Text("1. 在主历史窗口点击右上角“多选”按钮开启选择模式。")
                    Text("2. 勾选 2 个或更多条目，底栏将自动出现“合并”操作。")
                    Text("3. 点击合并可选择连接分隔符并预览条目，合并后自动生成独立历史记录，原条目不受影响。")
                }
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .padding(18)
            }
        }
    }

    private var retentionAndStatsPage: some View {
        VStack(spacing: 20) {
            sectionCard {
                settingRow("自动淘汰清理", detail: "定期清理超出保留期限的未保护历史条目", icon: "timer") {
                    Toggle("自动清理", isOn: $retentionEngine.autoRunEnabled).labelsHidden()
                }
                rowDivider
                settingRow("历史保留天数", detail: "常规未保护历史保留期限，超出后移入回收站或彻底清除", icon: "calendar") {
                    Picker("保留天数", selection: $retentionEngine.retentionDays) {
                        Text("30 天（推荐）").tag(30)
                        Text("60 天").tag(60)
                        Text("90 天").tag(90)
                        Text("180 天").tag(180)
                        Text("永久保留").tag(0)
                    }
                    .frame(width: 135)
                    .labelsHidden()
                }
                rowDivider
                settingRow("回收站保留天数", detail: "已放入回收站的条目彻底清除前的保留天数", icon: "trash") {
                    Picker("回收站期限", selection: $retentionEngine.trashRetentionDays) {
                        Text("7 天（推荐）").tag(7)
                        Text("14 天").tag(14)
                        Text("30 天").tag(30)
                    }
                    .frame(width: 135)
                    .labelsHidden()
                }
                rowDivider
                settingRow("立即执行清理", detail: "按当前保留策略立即执行一次全面淘汰清理", icon: "arrow.clockwise") {
                    Button("立即清理") {
                        isRunningRetention = true
                        Task {
                            if let report = await model.runRetentionNow() {
                                retentionAlertMessage = "清理完成：已淘汰清理 \(report.purgedItemsCount) 条过期历史条目。"
                            } else {
                                retentionAlertMessage = "保留清理未能完成，请检查日志。"
                            }
                            isRunningRetention = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunningRetention)
                }
            }

            sectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill").foregroundStyle(palette.success)
                        Text("核心数据保护承诺").font(.subheadline.weight(.semibold)).foregroundStyle(palette.success)
                    }
                    Text("所有标记为【置顶 (Pinned)】、【收藏 (Favorite)】或【常用片段 (Snippet)】的历史记录，均享有永久绝对保留豁免权。无论设置多短的保留期限，自动清理引擎绝对不会删除任何受保护条目。")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
                .padding(18)
            }

            StatisticsDashboardView(model: model, palette: palette)
        }
    }

    private var addAppSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加排除应用").font(.title3.weight(.bold))
            Text("输入应用名称或 Bundle Identifier。处于黑名单中的应用，其复制内容将不会被 PasteLoom 记录。")
                .font(.caption).foregroundStyle(palette.secondaryText)

            TextField("应用名称（例如：1Password）", text: $newAppName)
                .textFieldStyle(.roundedBorder)

            TextField("Bundle ID（可选，例如：com.agilebits.onepassword7）", text: $newAppBundleID)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("取消") { showAddAppSheet = false }
                    .buttonStyle(.bordered)
                Button("添加") {
                    if !newAppName.isEmpty || !newAppBundleID.isEmpty {
                        filterService.addApp(bundleIdentifier: newAppBundleID, name: newAppName.isEmpty ? newAppBundleID : newAppName)
                    }
                    showAddAppSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newAppName.isEmpty && newAppBundleID.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(palette.background)
    }

    private var addRuleSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加排除文本规则").font(.title3.weight(.bold))
            Text("当新复制的文本满足此规则时，将被静默排除，不加入剪贴板历史。")
                .font(.caption).foregroundStyle(palette.secondaryText)

            TextField("规则名称（例如：密码前缀）", text: $newRuleName)
                .textFieldStyle(.roundedBorder)

            TextField("匹配文本或正则表达式", text: $newRulePattern)
                .textFieldStyle(.roundedBorder)

            Picker("匹配模式", selection: $newRuleKind) {
                ForEach(TextMatchKind.allCases, id: \.rawValue) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
                Button("取消") { showAddRuleSheet = false }
                    .buttonStyle(.bordered)
                Button("添加") {
                    if !newRulePattern.isEmpty {
                        filterService.addTextRule(name: newRuleName.isEmpty ? newRulePattern : newRuleName,
                                                  pattern: newRulePattern,
                                                  matchKind: newRuleKind)
                    }
                    showAddRuleSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newRulePattern.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(palette.background)
    }

    private var panelPage: some View {
        VStack(spacing: 20) {
            sectionCard {
                settingRow("历史主抽屉", detail: "切换历史记录的单卡列表、双列网格或横向展示", icon: "rectangle.split.2x1") {
                    layoutControl(selection: $historyLayout, isDrawer: true)
                }
                rowDivider
                settingRow("快速粘贴浮窗", detail: "切换搜索结果的单卡列表或双列网格展示", icon: "keyboard") {
                    layoutControl(selection: $quickPasteLayout)
                }
                rowDivider
                settingRow("菜单栏面板", detail: "切换菜单栏弹出历史的列表或网格排列", icon: "menubar.rectangle") {
                    layoutControl(selection: $menuBarLayout)
                }
            }

            sectionCard {
                settingRow("菜单栏悬停预览", detail: "鼠标悬停在条目上时弹出完整卡片预览", icon: "eye") {
                    Toggle("菜单栏悬停预览", isOn: $menuBarHoverEnabled).labelsHidden()
                }
                if menuBarHoverEnabled {
                    rowDivider
                    settingRow("菜单栏悬停延时", detail: "悬停触发预览的等待时间", icon: "timer") {
                        Picker("悬停延时", selection: $menuBarHoverDelay) {
                            Text("0.3 秒").tag(0.3)
                            Text("0.5 秒（标准）").tag(0.5)
                            Text("1.0 秒").tag(1.0)
                        }
                        .labelsHidden()
                        .frame(width: 135)
                    }
                }
            }
        }
    }

    private func layoutControl(selection: Binding<String>, isDrawer: Bool = false) -> some View {
        Picker("布局模式", selection: selection) {
            Text("单卡列表").tag("list")
            Text("双列网格").tag("grid")
            if isDrawer {
                Text("横向网格").tag("horizontal")
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: isDrawer ? 240 : 170)
    }

    private var shortcutPage: some View {
        VStack(spacing: 20) {
            sectionCard {
                ForEach(ShortcutAction.allCases) { action in
                    let current = GlobalShortcut.load(for: action)
                    settingRow(action.displayName, detail: actionDescription(action), icon: actionIcon(action)) {
                        HStack(spacing: 8) {
                            Button(recordingAction == action ? "请按组合键…" : current.displayName) {
                                if recordingAction == action {
                                    stopShortcutRecording()
                                } else {
                                    startShortcutRecording(for: action)
                                }
                            }
                            .buttonStyle(.bordered)
                            .foregroundStyle(recordingAction == action ? palette.accent : palette.primaryText)

                            Button {
                                resetShortcut(for: action)
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .buttonStyle(.bordered)
                            .help("恢复默认 \(action.defaultShortcut.displayName)")
                        }
                    }
                    if action != ShortcutAction.allCases.last {
                        rowDivider
                    }
                }
            }

            sectionCard {
                settingRow("自动粘贴", detail: "呼出主窗口点击卡片，或呼出快速粘贴后按下回车，自动粘贴到原应用输入框；需辅助功能权限", icon: "return") {
                    Toggle("自动粘贴", isOn: Binding(
                        get: { model.autoPasteEnabled }, set: { model.setAutoPasteEnabled($0) }
                    )).labelsHidden()
                }
            }

            if let conflict = shortcutConflictMessage {
                Text(conflict).font(.caption).foregroundStyle(palette.warning)
            } else if !shortcutHint.isEmpty {
                Text(shortcutHint).font(.caption).foregroundStyle(palette.secondaryText)
            }

            sectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("快速粘贴面板快捷键说明").font(.subheadline.weight(.semibold))
                    HStack(spacing: 20) {
                        Label("Return 粘贴或复制", systemImage: "return")
                        Label("Space 增减多选", systemImage: "space")
                        Label("↑ / ↓ 移动光标", systemImage: "arrow.up.and.down")
                        Label("Esc 收起浮窗", systemImage: "escape")
                    }
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                }
                .padding(16)
            }
        }
    }

    private func actionDescription(_ action: ShortcutAction) -> String {
        switch action {
        case .quickPaste: return "在当前光标位置呼出快速粘贴浮窗"
        case .mainWindow: return "激活并展示主历史抽屉窗口"
        case .screenshotAnnotate: return "截取屏幕并进入图片标注编辑器"
        case .quickScreenshot: return "静默截图并直接复制到系统剪贴板"
        }
    }

    private func actionIcon(_ action: ShortcutAction) -> String {
        switch action {
        case .quickPaste: return "bolt.fill"
        case .mainWindow: return "sidebar.left"
        case .screenshotAnnotate: return "viewfinder"
        case .quickScreenshot: return "camera"
        }
    }

    private func startShortcutRecording(for action: ShortcutAction) {
        stopShortcutRecording()
        recordingAction = action
        shortcutHint = "请按下包含 Command、Option 或 Control 的组合键；按 Esc 取消。"
        shortcutConflictMessage = nil
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopShortcutRecording()
                return nil
            }
            guard let candidate = GlobalShortcut.from(event) else {
                shortcutHint = "按键无效：需包含修饰键（⌘ / ⌥ / ⌃）与一个字母或数字。"
                return nil
            }
            let result = runtime.updateShortcut(candidate, for: action)
            stopShortcutRecording()
            switch result {
            case .success:
                shortcutConflictMessage = nil
                shortcutHint = "快捷键设置成功。"
            case .failure(let conflict):
                shortcutConflictMessage = conflict.localizedDescription
            }
            return nil
        }
    }

    private func stopShortcutRecording() {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = nil
        recordingAction = nil
    }

    private func resetShortcut(for action: ShortcutAction) {
        let result = runtime.resetShortcutToDefault(for: action)
        switch result {
        case .success:
            shortcutConflictMessage = nil
            shortcutHint = "已恢复为默认快捷键。"
        case .failure(let conflict):
            shortcutConflictMessage = conflict.localizedDescription
        }
    }

    private var accessibilityPage: some View {
        sectionCard {
            settingRow("辅助功能权限", detail: "自动粘贴需要系统授权；搜索和仅复制无需授权", icon: "checkmark.shield") {
                Text(accessibilityGranted ? "已授权" : "未授权")
                    .foregroundStyle(accessibilityGranted ? palette.success : palette.warning)
                Button("重新检测") { accessibilityGranted = accessibility.isTrusted }
                    .buttonStyle(.bordered)
                if !accessibilityGranted {
                    Button("打开系统设置") { accessibility.openSettings() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var screenshotUnifiedPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionCard {
                settingRow("屏幕与系统录制", detail: "使用系统截图服务捕获屏幕与选区。若系统设置已开启但显示未授权，请将开关关闭后再开启一次以刷新绑定", icon: "record.circle") {
                    Text(screenshotGranted ? "已授权" : "当前构建未授权")
                        .foregroundStyle(screenshotGranted ? palette.success : palette.warning)
                    Button("重新检测") {
                        ScreenshotPermission.requestAccess()
                        screenshotGranted = ScreenshotPermission.isGranted
                    }
                    .buttonStyle(.bordered)
                    if !screenshotGranted {
                        Button("打开系统设置") { ScreenshotPermission.openSettings() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                rowDivider
                settingRow("自动图片识字 (OCR)", detail: "捕获图片与截图时，使用本地 Vision 引擎识别文字并建立搜索索引", icon: "text.viewfinder") {
                    Toggle("自动识字", isOn: $autoOCR).labelsHidden()
                }
                rowDivider
                settingRow("截图加入历史", detail: "快速截图与完成标注的图片自动加入本地历史记录", icon: "photo.badge.plus") {
                    Toggle("截图入库", isOn: $captureScreenshotsToHistory).labelsHidden()
                }
            }
            sectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("截图与识字说明").font(.subheadline.weight(.semibold))
                    Text("• 截图标注（默认 ⌥⌘A）：拖拽框选任意区域，完成后进入画板标注。")
                    Text("• 快速截图（默认 ⌥⇧⌘A）：框选后直接复制到剪贴板。")
                    Text("• 纯本地离线 OCR：支持简体中文、繁体中文与英文识别，可在搜索栏直接搜索图内文字。")
                }
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .padding(16)
            }
            sectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("标注工具与画板").font(.subheadline.weight(.semibold))
                    Text("从主窗口截图，或在图片历史卡片中点击“标注图片”，即可使用裁剪、矩形、椭圆、箭头、直线、画笔、文字与马赛克。标注器内可选择颜色、线宽、撤销和重做。")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
                .padding(16)
            }
            sectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("保存与输出").font(.subheadline.weight(.semibold))
                    Text("标注器可将结果保存为 PNG，或作为图片复制到系统剪贴板。取消操作不会改动历史原图或剪贴板。")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
                .padding(16)
            }
            Text("若系统列表中 PasteLoom 已开启，但这里仍显示未授权，请在系统设置中移除旧条目，再添加当前正在运行的 PasteLoom.app。授权后退出并重新打开应用。")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
        }
    }

    private func refreshPermissions() {
        accessibilityGranted = accessibility.isTrusted
        screenshotGranted = ScreenshotPermission.isGranted
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.cardBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    private func settingRow<Content: View>(_ title: String, detail: String, icon: String,
                                           @ViewBuilder control: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(palette.accent)
                .frame(width: 20, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(palette.secondaryText)
            }
            Spacer(minLength: 12)
            control()
        }
        .frame(minHeight: 48)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private var rowDivider: some View {
        Rectangle().fill(palette.divider).frame(height: 1).padding(.leading, 48)
    }
    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(palette.secondaryText)
    }
}

private struct SettingsWindowTitleBridge: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        WindowTitleView(title: title)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowTitleView)?.title = title
        nsView.window?.title = title
    }

    private final class WindowTitleView: NSView {
        var title: String

        init(title: String) {
            self.title = title
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.title = title
        }
    }
}
