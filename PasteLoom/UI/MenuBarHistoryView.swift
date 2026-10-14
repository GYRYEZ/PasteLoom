import AppKit
import SwiftUI

struct MenuBarHistoryView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject var runtime: AppRuntime
    @ObservedObject private var model: AppModel

    init(runtime: AppRuntime) {
        self.runtime = runtime
        self._model = ObservedObject(wrappedValue: runtime.model)
    }

    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("themePreset") private var themePreset = PaperTheme.macosNative.rawValue
    @AppStorage("accentColor") private var accentColor = PaperAccent.theme.rawValue
    @AppStorage("menuBarLayout") private var menuBarLayout = "list"
    @AppStorage("menuBarHoverEnabled") private var menuBarHoverEnabled = true
    @AppStorage("menuBarHoverDelay") private var menuBarHoverDelay = 0.5

    @State private var searchKeyword = ""
    @State private var historyItems: [HistoryItem] = []
    @State private var isLoadingHistory = false
    @State private var historyLoadGeneration = 0
    @State private var tagEditorItem: HistoryItem?
    @State private var tagInput = ""
    @State private var hoveredCardID: UUID? = nil

    private var effectiveColorScheme: ColorScheme {
        AppearanceManager.effectiveColorScheme(for: appearanceMode, environmentScheme: colorScheme)
    }

    private var palette: PaperPalette {
        let accent = PaperAccent(rawValue: accentColor)
        return (PaperTheme(rawValue: themePreset) ?? .macosNative)
            .palette(for: effectiveColorScheme, accentOverride: accent == .theme ? nil : accent)
    }

    private var filteredItems: [HistoryItem] {
        historyItems
    }

    var body: some View {
        VStack(spacing: 0) {
            topHeader
            searchBar
            Divider()

            if isLoadingHistory && filteredItems.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredItems.isEmpty {
                ContentUnavailableView(searchKeyword.isEmpty ? "暂无历史记录" : "未找到匹配项",
                                       systemImage: searchKeyword.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 40)
            } else {
                ScrollView {
                    if menuBarLayout == "grid" {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                VerticalTicketCard(
                                    item: item,
                                    model: model,
                                    palette: palette,
                                    cardIndex: index,
                                    isHovered: hoveredCardID == item.id,
                                    onHoverChanged: { isOver in
                                        if isOver {
                                            hoveredCardID = item.id
                                        } else if hoveredCardID == item.id {
                                            hoveredCardID = nil
                                        }
                                    },
                                    onPreview: { preview(item) },
                                    onCopy: { handleCardCopy(item: item) },
                                    onAnnotate: { annotate(item) },
                                    onTag: {
                                        tagInput = item.tags.joined(separator: ", ")
                                        tagEditorItem = item
                                    }
                                )
                            }
                        }
                        .padding(10)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredItems) { item in
                                PaperHistoryCard(
                                    item: item,
                                    model: model,
                                    palette: palette,
                                    onPreview: { preview(item) },
                                    onCopy: { handleCardCopy(item: item) },
                                    onAnnotate: { annotate(item) },
                                    onTag: {
                                        tagInput = item.tags.joined(separator: ", ")
                                        tagEditorItem = item
                                    },
                                    preferredArrowEdge: .trailing,
                                    showPerforation: false
                                )
                            }
                        }
                        .padding(10)
                    }
                }
            }

            Divider()
            bottomActions
        }
        .frame(width: 420, height: 560)
        .background(
            ZStack {
                VisualEffectBlur(material: palette.material, blendingMode: .behindWindow, alpha: palette.blurAlpha)
                palette.sidebarBackground.opacity(palette.backgroundOpacity)
            }
        )
        .foregroundStyle(palette.primaryText)
        .tint(palette.accent)
        .preferredColorScheme(appearanceMode == "light" ? .light : appearanceMode == "dark" ? .dark : (appearanceManager.isSystemDark ? .dark : .light))
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DismissMenuBarExtraWindow"))) { _ in
            dismiss()
        }
        // MenuBarExtra may remain alive while its window is hidden. Refresh on
        // each presentation so the panel always starts from the same persisted
        // history snapshot as the main drawer, including after background use.
        .onAppear {
            loadHistory()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loadHistory()
        }
        .onReceive(model.$items.dropFirst()) { _ in
            // Captures and card actions refresh the shared model. Re-query the
            // repository with this panel's own search instead of borrowing the
            // main drawer's currently filtered `items` page.
            loadHistory()
        }
        .onChange(of: searchKeyword) { _, _ in
            loadHistory()
        }
        .onChange(of: appearanceMode) { _, newMode in
            AppearanceManager.apply(mode: newMode)
        }
        .sheet(item: $tagEditorItem) { item in
            VStack(alignment: .leading, spacing: 16) {
                Text("编辑标签").font(.title3.weight(.semibold))
                Text("用逗号分隔多个标签。搜索可以按标签命中。")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("例如：工作, 灵感", text: $tagInput)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("取消") { tagEditorItem = nil }
                    Button("保存") {
                        model.setTags(tagInput.split(separator: ",").map(String.init), for: item)
                        tagEditorItem = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(width: 320)
        }
    }

    private var topHeader: some View {
        HStack(spacing: 8) {
            AppLogoView(size: 22, cornerRadius: 5, showShadow: true)
            Text("PasteLoom")
                .font(.headline.weight(.semibold))
            Spacer()

            Button {
                menuBarLayout = (menuBarLayout == "list") ? "grid" : "list"
            } label: {
                Image(systemName: menuBarLayout == "list" ? "square.grid.2x2" : "list.bullet")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .help(menuBarLayout == "list" ? "切换为网格视图" : "切换为列表视图")

            Button {
                model.setCaptureEnabled(!model.isCapturing)
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(model.isCapturing ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(model.isCapturing ? "监听中" : "已暂停")
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(palette.cardBackground, in: Capsule())
            }
            .buttonStyle(.plain)
            .help(model.isCapturing ? "点击暂停捕获" : "点击恢复捕获")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(palette.sidebarBackground)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("搜索...", text: $searchKeyword)
                .textFieldStyle(.plain)
                .font(.subheadline)
            if !searchKeyword.isEmpty {
                Button { searchKeyword = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.cardBorder))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var bottomActions: some View {
        HStack(spacing: 8) {
            // Primary Action 1: 主窗口
            Button {
                openWindow(id: "history")
                runtime.showMainWindow()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 11, weight: .medium))
                    Text("主窗口")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(palette.primaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.cardBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            // Primary Action 2: 快速粘贴
            Button {
                runtime.quickPaste.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "command")
                        .font(.system(size: 11, weight: .medium))
                    Text("快速粘贴")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(palette.primaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.cardBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Spacer()

            // Secondary & Destructive Actions in Gear Menu
            Menu {
                Button {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("设置…", systemImage: "gearshape")
                }

                Divider()

                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label("退出 PasteLoom", systemImage: "power")
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 26, height: 26)
                    .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.cardBorder, lineWidth: 0.5))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("设置与退出")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.sidebarBackground)
    }

    private func preview(_ item: HistoryItem) {
        HistoryPreviewWindowController.shared.show(item: item, model: model, palette: palette)
    }

    private func loadHistory() {
        historyLoadGeneration += 1
        let generation = historyLoadGeneration
        let query = searchKeyword
        isLoadingHistory = true
        Task { @MainActor in
            do {
                let results = try await model.quickSearch(query, limit: 80)
                guard generation == historyLoadGeneration else { return }
                historyItems = results
            } catch {
                guard generation == historyLoadGeneration else { return }
                historyItems = []
                model.errorMessage = "无法读取菜单栏历史：\(error.localizedDescription)"
            }
            guard generation == historyLoadGeneration else { return }
            isLoadingHistory = false
        }
    }

    private func annotate(_ item: HistoryItem) {
        Task {
            guard let data = await model.originalImageData(for: item) else {
                model.errorMessage = "找不到这张图片的原始资源。"
                return
            }
            let document = ScreenshotDocument(pngData: data)
            ScreenshotEditorWindowController.shared.show(document: document)
        }
    }

    private func handleCardCopy(item: HistoryItem) {
        dismiss()
        Task { @MainActor in
            let outcome = await runtime.pasteOrCopy(item: item)
            NotificationCenter.default.post(
                name: NSNotification.Name("CardPasteOutcomeReceived"),
                object: item.id,
                userInfo: ["outcome": outcome]
            )
        }
    }
}
