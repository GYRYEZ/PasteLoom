import AppKit
import QuickLook
import QuickLookThumbnailing
import SwiftUI

enum HistoryPreviewRoute: Equatable {
    case detail
    case quickLook(URL)

    static func forItem(_ item: HistoryItem) -> HistoryPreviewRoute {
        if (item.kind == .file || item.kind == .video), item.files.count == 1,
           let file = item.files.first, file.isAvailable {
            return .quickLook(file.url)
        }
        return .detail
    }
}

struct HistoryView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject var model: AppModel
    var runtime: AppRuntime? = nil
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("themePreset") private var themePreset = PaperTheme.macosNative.rawValue
    @AppStorage("accentColor") private var accentColor = PaperAccent.theme.rawValue
    @AppStorage("drawerEdge") private var drawerEdge = "left"
    @AppStorage("edgeHoverSide") private var edgeHoverSide = "follow"
    @AppStorage("historyLayout") private var historyLayout = "list"
    @AppStorage("edgeAutoHide") private var edgeAutoHide = true
    @AppStorage("tagMatchMode") private var storedTagMatchMode = TagMatchMode.any.rawValue
    @State private var selectedItem: HistoryItem?
    @State private var screenshotDocument: ScreenshotDocument?
    @State private var isCapturingScreenshot = false
    @State private var quickLookURL: URL?
    @State private var tagFilterInput = ""
    @State private var showFilters = false
    @State private var showSearchInput = false
    @State private var selectionMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showMergeSheet = false
    @State private var hoveredCardID: UUID? = nil

    private enum DeckCategory: String, CaseIterable, Identifiable {
        case all = "全部"
        case text = "文本"
        case images = "图像"
        case files = "文件"
        case favorites = "收藏"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .all: return "clock"
            case .text: return "doc.text"
            case .images: return "photo.on.rectangle"
            case .files: return "folder"
            case .favorites: return "star.fill"
            }
        }
    }

    private var currentCategory: DeckCategory {
        if model.selectedFilter == .favorites {
            return .favorites
        }
        switch model.searchScope.kind {
        case .text, .richText: return .text
        case .image: return .images
        case .file: return .files
        default: return .all
        }
    }

    private func resetAllFilters() {
        model.selectedFilter = .all
        model.searchScope = .unrestricted
        model.searchScope.tagMatch = TagMatchMode.load(from: .standard)
        model.refresh()
    }

    private var filterSummaryText: String {
        var parts: [String] = []
        if !model.searchScope.sourceName.isEmpty {
            parts.append("应用:\(model.searchScope.sourceName)")
        }
        if !model.searchScope.tags.isEmpty {
            parts.append("标签:\(model.searchScope.tags.joined(separator: ","))")
        }
        if model.searchScope.isSnippet == true {
            parts.append("片段")
        }
        if model.searchScope.since != nil {
            parts.append("近7天")
        }
        if let kind = model.searchScope.kind {
            parts.append(kind.rawValue)
        }
        return parts.isEmpty ? "高级筛选生效中" : parts.joined(separator: " · ")
    }

    private func selectCategory(_ cat: DeckCategory) {
        switch cat {
        case .all:
            resetAllFilters()
            return
        case .text:
            model.selectedFilter = .all
            model.searchScope.kind = .text
        case .images:
            model.selectedFilter = .all
            model.searchScope.kind = .image
        case .files:
            model.selectedFilter = .all
            model.searchScope.kind = .file
        case .favorites:
            model.selectedFilter = .favorites
            model.searchScope.kind = nil
        }
        model.refresh()
    }

    private var effectiveColorScheme: ColorScheme {
        AppearanceManager.effectiveColorScheme(for: appearanceMode, environmentScheme: colorScheme)
    }

    private var palette: PaperPalette {
        let accent = PaperAccent(rawValue: accentColor)
        return (PaperTheme(rawValue: themePreset) ?? .macosNative)
            .palette(for: effectiveColorScheme, accentOverride: accent == .theme ? nil : accent)
    }

    @AppStorage("horizontalDrawerHeight") private var horizontalDrawerHeight: Double = 286.0

    private var isHorizontal: Bool {
        drawerEdge == "top" || drawerEdge == "bottom"
    }

    private var horizontalCardHeight: CGFloat {
        let clampedH = max(210, min(348, horizontalDrawerHeight))
        return max(140, min(278, CGFloat(clampedH) - 64.0))
    }

    private var horizontalCardWidth: CGFloat {
        round(horizontalCardHeight * (200.0 / 230.0))
    }

    private var topResizeHandle: some View {
        TopResizeHandleBar(
            palette: palette,
            edge: drawerEdge,
            height: $horizontalDrawerHeight
        )
    }

    private var isErrorAlertPresented: Binding<Bool> {
        Binding<Bool>(
            get: { model.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    model.errorMessage = nil
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if isHorizontal {
                horizontalHeader
                    .overlay(alignment: .top) {
                        if drawerEdge == "bottom" {
                            topResizeHandle
                        }
                    }
                    .onHover { isOver in if isOver { hoveredCardID = nil } }
            } else {
                verticalHeader
                    .onHover { isOver in if isOver { hoveredCardID = nil } }
            }
            ScrollViewReader { scrollProxy in
                if isHorizontal {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            Color.clear.frame(width: 0).id("history-top")
                            if model.items.isEmpty {
                                emptyState.frame(width: 320)
                            } else {
                                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                                    selectableCard(item, cornerRadius: 13) {
                                        VerticalTicketCard(item: item, model: model, palette: palette,
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
                                                           onCopy: { handleCardPrimaryAction(item) },
                                                           onAnnotate: { annotate(item) },
                                                           onTag: { openTagEditor(for: item) },
                                                           cardHeight: horizontalCardHeight)
                                            .frame(width: horizontalCardWidth, height: horizontalCardHeight)
                                    }
                                }
                            }
                            if model.hasMore {
                                Button("加载更多") { model.loadMore() }
                                    .buttonStyle(.bordered)
                                    .frame(width: 80, height: horizontalCardHeight)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 7)
                        .padding(.bottom, 5)
                    }
                    .background(Color.clear)
                    .onHover { isOver in
                        if !isOver {
                            hoveredCardID = nil
                        }
                    }
                    .onChange(of: model.searchText) { _, _ in scrollProxy.scrollTo("history-top", anchor: .leading) }
                    .onChange(of: model.searchMode) { _, _ in scrollProxy.scrollTo("history-top", anchor: .leading) }
                    .onChange(of: model.selectedFilter) { _, _ in scrollProxy.scrollTo("history-top", anchor: .leading) }
                    .onChange(of: model.searchScope) { _, _ in scrollProxy.scrollTo("history-top", anchor: .leading) }
                } else {
                    ScrollView {
                        Group {
                            Color.clear.frame(height: 0).id("history-top")
                            if model.items.isEmpty {
                                emptyState.padding(.top, 100)
                            } else {
                                LazyVStack(spacing: 8) {
                                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                                        selectableCard(item, cornerRadius: historyLayout == "list" ? 10 : 13) {
                                            if historyLayout == "list" {
                                                PaperHistoryCard(item: item, model: model, palette: palette,
                                                                 onPreview: { preview(item) },
                                                                 onCopy: { handleCardPrimaryAction(item) },
                                                                 onAnnotate: { annotate(item) },
                                                                 onTag: { openTagEditor(for: item) })
                                            } else {
                                                VerticalTicketCard(item: item, model: model, palette: palette,
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
                                                                   onCopy: { handleCardPrimaryAction(item) },
                                                                   onAnnotate: { annotate(item) },
                                                                   onTag: { openTagEditor(for: item) })
                                            }
                                        }
                                    }
                                }
                            }
                            if model.hasMore {
                                Button("加载更多历史") { model.loadMore() }
                                    .buttonStyle(.bordered)
                                    .padding(.vertical, 12)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                    }
                    .background(Color.clear)
                    .onChange(of: model.searchText) { _, _ in scrollProxy.scrollTo("history-top", anchor: .top) }
                    .onChange(of: model.searchMode) { _, _ in scrollProxy.scrollTo("history-top", anchor: .top) }
                    .onChange(of: model.selectedFilter) { _, _ in scrollProxy.scrollTo("history-top", anchor: .top) }
                    .onChange(of: model.searchScope) { _, _ in scrollProxy.scrollTo("history-top", anchor: .top) }
                }
            }
            if selectionMode { batchBar }
        }
        .frame(minWidth: isHorizontal ? 500 : 280,
               maxWidth: isHorizontal ? .infinity : 340,
               minHeight: isHorizontal ? CGFloat(horizontalDrawerHeight) : 400,
               maxHeight: isHorizontal ? CGFloat(horizontalDrawerHeight) : .infinity)
        .background(drawerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(drawerBorderColor, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(palette.isDark ? 0.28 : 0.12), radius: 8, x: 0, y: 2)
        .padding(.bottom, drawerEdge == "bottom" ? 5 : 0)
        .frame(minWidth: isHorizontal ? 500 : 280,
               maxWidth: isHorizontal ? .infinity : 340,
               minHeight: isHorizontal ? CGFloat(horizontalDrawerHeight) + (drawerEdge == "bottom" ? 5 : 0) : 400,
               maxHeight: isHorizontal ? CGFloat(horizontalDrawerHeight) + (drawerEdge == "bottom" ? 5 : 0) : .infinity)
        .ignoresSafeArea()
        .background { DrawerWindowBridge(edge: drawerEdge, layout: historyLayout) }
        .foregroundStyle(palette.primaryText)
        .tint(palette.accent)
        .onChange(of: appearanceMode) { _, newMode in
            AppearanceManager.apply(mode: newMode)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HorizontalDrawerHeightDidChange"))) { note in
            handleDrawerHeightNotification(note)
        }
        .onChange(of: model.searchText) { _, _ in model.refresh() }
        .onChange(of: model.searchMode) { _, _ in model.refresh() }
        .onChange(of: model.selectedFilter) { _, _ in model.refresh() }
        .onChange(of: model.searchScope) { _, _ in model.refresh() }
        .onChange(of: storedTagMatchMode) { _, value in
            model.searchScope.tagMatch = TagMatchMode(rawValue: value) ?? .any
        }
        .onAppear {
            handleOnAppear()
        }
        .onChange(of: model.items) { _, newItems in
            selectedIDs.formIntersection(Set(newItems.map(\.id)))
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in hoveredCardID = nil }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ResetDrawerHoverStates"))) { _ in hoveredCardID = nil }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DrawerEdgeDidChange"))) { notif in
            handleDrawerEdgeNotification(notif)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DrawerStateDidChange"))) { notif in
            handleDrawerStateNotification(notif)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerScreenshotAction"))) { notif in
            handleTriggerScreenshotNotification(notif)
        }
        .sheet(item: $selectedItem) { item in HistoryDetailView(item: item, model: model) }
        .sheet(isPresented: $showMergeSheet) {
            MergeSheet(model: model, selectedIDs: Array(selectedIDs), palette: palette) {
                showMergeSheet = false
                selectedIDs.removeAll()
                selectionMode = false
            }
        }
        .quickLookPreview($quickLookURL)
        .alert("PasteLoom", isPresented: isErrorAlertPresented) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var drawerBorderColor: Color {
        if palette.isFrostedGlass {
            return palette.isDark ? Color.white.opacity(0.18) : Color.white.opacity(0.42)
        }
        return palette.isDark ? Color.white.opacity(0.12) : palette.cardBorder.opacity(0.4)
    }

    private var drawerBackground: some View {
        ZStack {
            VisualEffectBlur(material: palette.material, blendingMode: .behindWindow, alpha: palette.blurAlpha)
            palette.sidebarBackground.opacity(palette.backgroundOpacity)
        }
    }

    private var horizontalHeader: some View {
        HStack(spacing: 8) {
            // Brand logo & item count badge (Concept C)
            HStack(spacing: 5) {
                AppLogoView(size: 18, cornerRadius: 4.2)
                Text("PasteLoom")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text("\(model.items.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(palette.cardBackground, in: Capsule())
                    .overlay(Capsule().stroke(palette.cardBorder.opacity(0.4), lineWidth: 0.5))
            }
            .padding(.trailing, 2)

            // Divider separating Brand Logo and Search/Filter section
            Rectangle()
                .fill(palette.cardBorder.opacity(0.4))
                .frame(width: 0.5, height: 14)
                .padding(.horizontal, 2)

            // Search Button & Expandable Search Field
            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showSearchInput.toggle()
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(model.searchText.isEmpty ? palette.secondaryText : palette.accent)
                        .frame(width: 24, height: 24)
                        .background(showSearchInput || !model.searchText.isEmpty ? palette.cardBackground : Color.clear, in: Circle())
                }
                .buttonStyle(.plain)
                .help("搜索历史 (⌘F)")

                if showSearchInput || !model.searchText.isEmpty {
                    HStack(spacing: 4) {
                        TextField("搜索...", text: $model.searchText)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .frame(width: 100)
                            .accessibilityLabel("搜索")
                            .accessibilityIdentifier("historySearch")
                        if !model.searchText.isEmpty {
                            Button { model.searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill").font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(palette.secondaryText)
                        }
                        HStack(spacing: 2) {
                            searchMode("全文", symbol: "text.magnifyingglass", mode: .fullText)
                            searchMode("语义", symbol: "sparkles", mode: .semantic)
                            searchMode("标签", symbol: "tag.fill", mode: .tags)
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 24)
                    .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.cardBorder, lineWidth: 1))
                }
            }

            // Deck Category Pills with HIG-compliant restrained hierarchy (no colored rainbow dots)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(DeckCategory.allCases) { cat in
                        let isSelected = currentCategory == cat
                        Button {
                            selectCategory(cat)
                        } label: {
                            HStack(spacing: 3.5) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 9.5))
                                Text(cat.rawValue)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                            .background(
                                isSelected
                                    ? palette.accent.opacity(0.14)
                                    : palette.cardBackground.opacity(0.4),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(isSelected ? palette.accent.opacity(0.4) : palette.cardBorder.opacity(0.4), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if model.searchScope.hasFilters {
                        Button { resetAllFilters() } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 9))
                                Text("恢复全部")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(palette.accent)
                            .padding(.horizontal, 7)
                            .frame(height: 24)
                            .background(palette.accent.opacity(0.12), in: Capsule())
                            .overlay(Capsule().stroke(palette.accent.opacity(0.35), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .help("清除所有高级筛选，显示完整历史记录")
                    }

                    let hasAdvanced = model.searchScope.hasFilters
                    Button { openAdvancedFilter() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text("高级筛选")
                                .font(.system(size: 11, weight: hasAdvanced ? .semibold : .medium))
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .foregroundStyle(hasAdvanced ? palette.accent : palette.secondaryText)
                        .background(
                            hasAdvanced
                                ? palette.accent.opacity(0.14)
                                : palette.cardBackground.opacity(0.4),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().stroke(hasAdvanced ? palette.accent.opacity(0.4) : palette.cardBorder.opacity(0.4), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("高级筛选：按应用、日期、标签或条件过滤")
                }
            }
            .frame(minWidth: 0)
            .padding(.horizontal, 3)

            Spacer(minLength: 4)

            // Right Tools: Group 1 (State & Pin) + Divider + Group 2 (Utilities)
            HStack(spacing: 6) {
                // Group 1: 核心状态与停靠常驻 (High-frequency Controls: Antenna, Pin)
                HStack(spacing: 5) {
                    // Capture antenna monitoring toggle
                    Button {
                        model.setCaptureEnabled(!model.isCapturing)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 10))
                            Circle()
                                .fill(model.isCapturing ? Color.green : Color.orange)
                                .frame(width: 4, height: 4)
                        }
                        .padding(.horizontal, 6)
                        .frame(height: 24)
                        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 5.5))
                        .overlay(RoundedRectangle(cornerRadius: 5.5).stroke(palette.cardBorder.opacity(0.35), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help(model.isCapturing ? "剪贴板监听中（点击暂停）" : "剪贴板监听已暂停（点击恢复）")

                    // Pin / Auto-hide toggle button
                    Button {
                        edgeAutoHide.toggle()
                        NotificationCenter.default.post(name: NSNotification.Name("ToggleDrawerPin"), object: edgeAutoHide)
                    } label: {
                        Image(systemName: edgeAutoHide ? "pin" : "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(edgeAutoHide ? palette.secondaryText : palette.accent)
                            .frame(width: 24, height: 24)
                            .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 5.5))
                            .overlay(RoundedRectangle(cornerRadius: 5.5).stroke(palette.cardBorder.opacity(0.35), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help(edgeAutoHide ? "靠边自动隐藏已启用（点击固定常驻）" : "窗口已固定常驻（点击开启靠边自动隐藏）")
                }

                // Subtle vertical divider separating functional groups (9pt logical spacing)
                Rectangle()
                    .fill(palette.cardBorder.opacity(0.4))
                    .frame(width: 0.5, height: 14)
                    .padding(.horizontal, 2)

                // Group 2: 工具与偏好 (Screenshot, Settings)
                HStack(spacing: 5) {
                    // Screenshot & Annotate
                    Button { captureScreenshot() } label: {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.secondaryText)
                            .frame(width: 24, height: 24)
                            .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 5.5))
                            .overlay(RoundedRectangle(cornerRadius: 5.5).stroke(palette.cardBorder.opacity(0.35), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help("截图并标注")

                    // Settings
                    Button { openSettings() } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
                            .frame(width: 24, height: 24)
                            .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 5.5))
                            .overlay(RoundedRectangle(cornerRadius: 5.5).stroke(palette.cardBorder.opacity(0.35), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help("偏好设置")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            palette.isFrostedGlass
                ? (palette.isDark
                    ? Color.white.opacity(0.06)
                    : Color.white.opacity(0.16))
                : (palette.isDark
                    ? Color(nsColor: .windowBackgroundColor).opacity(0.65)
                    : palette.sidebarBackground)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.cardBorder.opacity(palette.isDark ? 0.35 : 0.25))
                .frame(height: 0.5)
        }
    }

    private func handleOnAppear() {
        model.searchScope.tagMatch = TagMatchMode.load(from: .standard)
        if edgeHoverSide != "follow" && edgeHoverSide != drawerEdge {
            edgeHoverSide = drawerEdge
            UserDefaults.standard.set(drawerEdge, forKey: "edgeHoverSide")
        }
        applyFirstLaunchDefaults()
    }

    private func applyFirstLaunchDefaults() {
        if !UserDefaults.standard.bool(forKey: "hasAppliedFirstLaunchLayoutDefaults_v2") {
            let isTopOrBottom = (drawerEdge == "bottom" || drawerEdge == "top")
            let defaultLayout = isTopOrBottom ? "horizontal" : "list"
            historyLayout = defaultLayout
            UserDefaults.standard.set(defaultLayout, forKey: "historyLayout")
            UserDefaults.standard.set(true, forKey: "hasAppliedFirstLaunchLayoutDefaults_v2")
        } else {
            let isSideEdge = (drawerEdge == "left" || drawerEdge == "right")
            if isSideEdge && historyLayout == "horizontal" {
                historyLayout = "list"
                UserDefaults.standard.set("list", forKey: "historyLayout")
            }
        }
    }

    private func handleDrawerHeightNotification(_ note: Notification) {
        if let newH = note.object as? Double {
            self.horizontalDrawerHeight = newH
        }
    }

    private func handleDrawerEdgeNotification(_ notif: Notification) {
        if let edge = notif.object as? String {
            handleDrawerEdgeChange(edge)
        }
    }

    private func handleDrawerStateNotification(_ notif: Notification) {
        let expanded = (notif.object as? Bool) ?? true
        handleDrawerStateChange(expanded)
    }

    private func handleDrawerEdgeChange(_ edge: String) {
        drawerEdge = edge
        edgeHoverSide = edge
        UserDefaults.standard.set(edge, forKey: "edgeHoverSide")
        let isSideEdge = (edge == "left" || edge == "right")
        if isSideEdge && historyLayout == "horizontal" {
            historyLayout = "list"
            UserDefaults.standard.set("list", forKey: "historyLayout")
        }
    }

    private func handleDrawerStateChange(_ expanded: Bool) {
        if !expanded {
            ThumbnailImageCache.shared.clear()
            Task {
                await model.clearThumbnailMemoryCache()
            }
        }
    }

    private func handleTriggerScreenshotNotification(_ notification: Notification) {
        let actionRaw = notification.object as? String ?? ""
        if actionRaw == ShortcutAction.quickScreenshot.rawValue {
            InteractiveScreenshotCoordinator.shared.startCapture(mode: .quick) { _ in } onQuickCopied: {
                model.refresh()
            }
        } else if actionRaw == ShortcutAction.screenshotAnnotate.rawValue {
            captureScreenshot()
        }
    }

    private var verticalHeader: some View {
        VStack(spacing: 8) {
            // Row 1: Brand title & top quick actions (symmetrically centered)
            HStack(alignment: .center, spacing: 6) {
                AppLogoView(size: 20, cornerRadius: 5)
                Text("PasteLoom")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)

                Spacer(minLength: 4)

                // Layout switch (list vs grid)
                Button {
                    historyLayout = (historyLayout == "list" ? "grid" : "list")
                    UserDefaults.standard.set(historyLayout, forKey: "historyLayout")
                } label: {
                    Image(systemName: historyLayout == "list" ? "rectangle.grid.1x2" : "sidebar.left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.secondaryText)
                        .frame(width: 24, height: 24)
                        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 5.5))
                        .overlay(RoundedRectangle(cornerRadius: 5.5).stroke(palette.cardBorder.opacity(0.4), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .help(historyLayout == "list" ? "切换为卡片网格列表" : "切换为紧凑单行列表")

                // Pin / Auto-hide toggle
                Button {
                    edgeAutoHide.toggle()
                    NotificationCenter.default.post(name: NSNotification.Name("ToggleDrawerPin"), object: edgeAutoHide)
                } label: {
                    Image(systemName: edgeAutoHide ? "pin" : "pin.fill")
                        .foregroundStyle(edgeAutoHide ? palette.secondaryText : palette.accent)
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 5.5))
                        .overlay(RoundedRectangle(cornerRadius: 5.5).stroke(palette.cardBorder.opacity(0.4), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .help(edgeAutoHide ? "靠边自动隐藏已启用（点击固定常驻）" : "窗口已固定常驻（点击开启自动隐藏）")
            }
            .padding(.top, 2)

            // Row 2: Integrated Search bar
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(palette.accent)
                    .font(.system(size: 12))
                    .padding(.leading, 8)
                ZStack(alignment: .leading) {
                    if model.searchText.isEmpty {
                        Text("搜索剪贴板...")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.secondaryText)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $model.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .accessibilityLabel("搜索")
                        .accessibilityIdentifier("historySearch")
                }
                .padding(.leading, 2)
                .frame(minWidth: 40)
                if !model.searchText.isEmpty {
                    Button { model.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.secondaryText)
                }
                HStack(spacing: 2) {
                    searchMode("全文", symbol: "text.magnifyingglass", mode: .fullText)
                    searchMode("语义", symbol: "sparkles", mode: .semantic)
                    searchMode("标签", symbol: "tag.fill", mode: .tags)
                }
                .padding(.trailing, 3)
            }
            .frame(height: 30)
            .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.cardBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)

            // Row 3: Circular filter & tool buttons - 5 buttons with equal distribution & visual symmetry
            HStack(spacing: 0) {
                circularFilterButton(
                    icon: "clock",
                    isSelected: model.selectedFilter == .all && !model.searchScope.hasFilters,
                    help: "全部历史 (点击恢复全部)"
                ) {
                    resetAllFilters()
                }

                Spacer()

                circularFilterButton(
                    icon: "star.fill",
                    isSelected: model.selectedFilter == .favorites,
                    help: "收藏夹"
                ) {
                    if model.selectedFilter == .favorites {
                        selectCategory(.all)
                    } else {
                        selectCategory(.favorites)
                    }
                }

                Spacer()

                circularFilterButton(
                    icon: selectionMode ? "checkmark.circle.fill" : "checkmark.circle",
                    isSelected: selectionMode,
                    help: selectionMode ? "退出多选" : "批量多选"
                ) {
                    selectionMode.toggle()
                    if !selectionMode { selectedIDs.removeAll() }
                }

                Spacer()

                circularFilterButton(
                    icon: "trash",
                    isSelected: model.selectedFilter == .trash,
                    help: "回收站"
                ) {
                    model.selectedFilter = (model.selectedFilter == .trash ? .all : .trash)
                }

                Spacer()

                Menu {
                    Button("偏好设置...") { openSettings() }
                    Button("刷新历史记录") { model.refresh() }
                    Button("高级筛选...") { openAdvancedFilter() }
                    Button("截图并标注...") { captureScreenshot() }
                    Divider()
                    Button(model.isCapturing ? "暂停剪贴板监控" : "恢复剪贴板监控") {
                        model.setCaptureEnabled(!model.isCapturing)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.secondaryText)
                        .frame(width: 26, height: 26)
                        .background(palette.cardBackground, in: Circle())
                        .overlay(Circle().stroke(palette.cardBorder, lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("更多选项与设置")
            }

            // Row 4: Category filter capsules with scroll support and clean margins
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(DeckCategory.allCases) { cat in
                        let isSelected = currentCategory == cat
                        Button {
                            selectCategory(cat)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 8.5))
                                Text(cat.rawValue)
                                    .font(.system(size: 9.5, weight: isSelected ? .semibold : .medium))
                            }
                            .fixedSize()
                            .padding(.horizontal, 7)
                            .frame(height: 22)
                            .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                            .background(
                                isSelected
                                    ? palette.accent.opacity(0.14)
                                    : palette.cardBackground.opacity(0.6),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(isSelected ? palette.accent.opacity(0.4) : palette.cardBorder.opacity(0.4), lineWidth: 0.6)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    let hasAdvanced = model.searchScope.hasFilters
                    Button { openAdvancedFilter() } label: {
                        HStack(spacing: 2.5) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 8.5, weight: .semibold))
                            Text("高级筛选")
                                .font(.system(size: 9.5, weight: hasAdvanced ? .semibold : .medium))
                                .fixedSize()
                        }
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .foregroundStyle(hasAdvanced ? palette.accent : palette.secondaryText)
                        .background(
                            hasAdvanced
                                ? palette.accent.opacity(0.14)
                                : palette.cardBackground.opacity(0.6),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().stroke(hasAdvanced ? palette.accent.opacity(0.4) : palette.cardBorder.opacity(0.4), lineWidth: 0.6)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("高级筛选：按应用、日期、标签或条件过滤")
                }
                .padding(.vertical, 1)
            }

            // Row 5: Active Advanced Filter Banner
            if model.searchScope.hasFilters {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.accent)

                    Text(filterSummaryText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Button {
                        resetAllFilters()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                            Text("恢复全部")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(palette.accent.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("重置高级筛选，显示全部历史记录")
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.accent.opacity(0.4), lineWidth: 0.8))
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(
            palette.isFrostedGlass
                ? (palette.isDark
                    ? Color.white.opacity(0.06)
                    : Color.white.opacity(0.16))
                : (palette.isDark
                    ? Color(nsColor: .windowBackgroundColor).opacity(0.65)
                    : palette.sidebarBackground)
        )
        .overlay(
            Rectangle()
                .fill(palette.isFrostedGlass
                    ? (palette.isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                    : palette.cardBorder)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    private func circularFilterButton(icon: String, isSelected: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : palette.secondaryText)
                .frame(width: 26, height: 26)
                .background(isSelected ? palette.accent : palette.cardBackground, in: Circle())
                .overlay(Circle().stroke(isSelected ? palette.accent : palette.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func filterTab(_ title: String, symbol: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10)) }
                Text(title).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 8)
            .frame(height: 25)
            .foregroundStyle(selected ? palette.cardBackground : palette.primaryText)
            .background(selected ? palette.accent : palette.cardBackground, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }


    private func searchMode(_ name: String, symbol: String, mode: HistorySearchMode?) -> some View {
        let selected = mode == model.searchMode
        return Button {
            if let mode { model.searchMode = mode }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: selected ? .bold : .medium))
                .frame(width: 20, height: 20)
                .foregroundStyle(selected ? palette.cardBackground : mode == nil ? palette.tertiaryText : palette.secondaryText)
                .background(selected ? palette.accent : Color.clear, in: RoundedRectangle(cornerRadius: 4.5))
        }
        .buttonStyle(.plain)
        .disabled(mode == nil)
        .help(name == "标签" ? "按标签搜索" : name == "语义" ? "语义相似度搜索" : "全文关键词搜索")
    }

    private func toolbarIcon(_ symbol: String, help: String, selected: Bool,
                             enabled: Bool = true, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(selected ? palette.cardBackground : enabled ? palette.primaryText : palette.tertiaryText)
                .frame(width: 36, height: 32)
                .background(selected ? palette.accent : palette.cardBackground,
                            in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: model.searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.largeTitle).foregroundStyle(palette.accent)
            Text(model.searchText.isEmpty ? "剪贴板历史从这里开始" : "没有匹配结果")
                .font(.headline)
            Text(model.searchText.isEmpty ? "在其他应用复制文本、链接、图片或文件。" : "试试其他关键词。")
                .font(.caption).foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func selectableCard<Content: View>(_ item: HistoryItem,
                                               cornerRadius: CGFloat = 10,
                                               @ViewBuilder content: () -> Content) -> some View {
        content()
            .allowsHitTesting(!selectionMode)
            .overlay {
                if selectionMode {
                    Button {
                        if !selectedIDs.insert(item.id).inserted { selectedIDs.remove(item.id) }
                    } label: {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(selectedIDs.contains(item.id) ? palette.accent.opacity(0.12) : .clear)
                            .overlay(RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(selectedIDs.contains(item.id) ? palette.accent : palette.cardBorder,
                                        lineWidth: selectedIDs.contains(item.id) ? 2 : 1))
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(palette.accent)
                                    .padding(9)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(selectedIDs.contains(item.id) ? "取消选择" : "选择")
                }
            }
    }

    private var batchBar: some View {
        HStack(spacing: 7) {
            Text("已选 \(selectedIDs.count)")
                .font(.caption.weight(.semibold))
                .frame(minWidth: 44)
            Spacer(minLength: 0)
            if model.selectedFilter == .trash {
                batchButton("恢复", symbol: "arrow.uturn.backward", action: .restore)
            } else {
                if selectedIDs.count >= 2 {
                    Button {
                        showMergeSheet = true
                    } label: {
                        Label("合并", systemImage: "rectangle.stack.badge.plus")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .buttonStyle(.borderedProminent)
                }
                batchButton("收藏", symbol: "star", action: .favorite)
                batchButton("置顶", symbol: "pin", action: .pin)
                batchButton("片段", symbol: "bookmark", action: .snippet)
                batchButton("删除", symbol: "trash", action: .trash)
            }
            Button("完成") {
                selectionMode = false
                selectedIDs.removeAll()
            }
            .font(.caption)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(palette.cardBackground)
        .overlay(alignment: .top) { palette.divider.frame(height: 1) }
    }

    private func batchButton(_ title: String, symbol: String, action: AppModel.BatchAction) -> some View {
        Button {
            model.performBatch(action, ids: selectedIDs)
            selectedIDs.removeAll()
            selectionMode = false
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .disabled(selectedIDs.isEmpty)
    }

    private func handleCardPrimaryAction(_ item: HistoryItem) {
        Task { @MainActor in
            let rt = runtime ?? AppDelegate.runtime
            if let rt {
                let outcome = await rt.pasteOrCopy(item: item, forceCopyOnly: false)
                NotificationCenter.default.post(
                    name: NSNotification.Name("CardPasteOutcomeReceived"),
                    object: item.id,
                    userInfo: ["outcome": outcome]
                )
            } else {
                model.copy(item)
                NotificationCenter.default.post(
                    name: NSNotification.Name("CardPasteOutcomeReceived"),
                    object: item.id,
                    userInfo: ["outcome": QuickPasteOutcome.copied]
                )
            }
        }
    }

    private func preview(_ item: HistoryItem) {
        HistoryPreviewWindowController.shared.show(item: item, model: model, palette: palette)
    }

    private func captureScreenshot() {
        InteractiveScreenshotCoordinator.shared.startCapture(mode: .annotate) { _ in
            model.refresh()
        } onQuickCopied: {
            model.refresh()
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

    private func openAdvancedFilter() {
        AdvancedFilterWindowController.shared.show(model: model, palette: palette)
    }

    private func openTagEditor(for item: HistoryItem) {
        TagEditorWindowController.shared.show(item: item, model: model, palette: palette)
    }
}

private func formatRelativeTime(_ date: Date) -> String {
    let calendar = Calendar.current
    let now = Date()
    let timeFormatter = DateFormatter()
    timeFormatter.dateFormat = "HH:mm"
    let timeStr = timeFormatter.string(from: date)

    if calendar.isDateInToday(date) {
        return "今天 \(timeStr)"
    } else if calendar.isDateInYesterday(date) {
        return "昨天 \(timeStr)"
    } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
        let mdFormatter = DateFormatter()
        mdFormatter.dateFormat = "M月d日"
        return "\(mdFormatter.string(from: date)) \(timeStr)"
    } else {
        let ymdFormatter = DateFormatter()
        ymdFormatter.dateFormat = "yyyy/M/d"
        return ymdFormatter.string(from: date)
    }
}

private struct GridHistoryCard: View {
    let item: HistoryItem
    @ObservedObject var model: AppModel
    let palette: PaperPalette
    let onPreview: () -> Void
    let onCopy: () -> Void
    let onAnnotate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) {
                Image(systemName: gridIcon)
                    .foregroundStyle(palette.accent)
                Text(item.sourceName ?? "Unknown").lineLimit(1)
                Spacer(minLength: 0)
                if item.isSnippet {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                        .foregroundStyle(palette.accent)
                }
            }
            .font(.caption.weight(.semibold))
            .frame(height: 18)
            Group {
                switch item.kind {
                case .image:
                    ImageThumbnailView(item: item, model: model, pixelSize: 260)
                        .adaptiveCardMediaFrame(cornerRadius: 6, shadowRadius: 3, shadowY: 1.5)
                case .video:
                    ZStack(alignment: .center) {
                        ImageThumbnailView(item: item, model: model, pixelSize: 260)
                            .adaptiveCardMediaFrame(cornerRadius: 6, shadowRadius: 3, shadowY: 1.5)
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(radius: 2)
                    }
                case .file:
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "folder.fill").font(.title).foregroundStyle(palette.accent)
                        Text(item.files.count == 1 ? item.files[0].name : "\(item.files.count) 个文件")
                            .lineLimit(3)
                    }
                case .url:
                    Text(item.text).lineLimit(6)
                case .text:
                    let displayText = SensitiveContentService.shared.isMaskingEnabled ? SensitiveContentService.shared.mask(item.text) : item.text
                    Text(displayText).lineLimit(8)
                case .richText:
                    let displayText = SensitiveContentService.shared.isMaskingEnabled ? SensitiveContentService.shared.mask(item.text) : item.text
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayText).lineLimit(6)
                        Text("富文本").font(.system(size: 9).weight(.semibold)).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(palette.accent.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, minHeight: 122, maxHeight: 122, alignment: .topLeading)
            HStack {
                Button(action: onPreview) { Image(systemName: "eye") }.help("预览")
                Button(action: onCopy) { Image(systemName: "doc.on.doc") }.help("复制")
                if item.kind == .image {
                    Button(action: onAnnotate) { Image(systemName: "pencil.tip.crop.circle") }.help("标注图片")
                    Button { model.performOCR(for: item) } label: { Image(systemName: "text.viewfinder") }.help("提取文字 (OCR)")
                }
                Spacer()
                Button { model.toggleSnippet(item) } label: {
                    Image(systemName: item.isSnippet ? "bookmark.fill" : "bookmark")
                }.help(item.isSnippet ? "取消片段" : "常用片段")
                Button { model.toggleFavorite(item) } label: {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                }.help(item.isFavorite ? "取消收藏" : "收藏")
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.secondaryText)
        }
        .padding(12)
        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.cardBorder))
    }

    private var gridIcon: String {
        switch item.kind {
        case .text: "text.alignleft"
        case .richText: "text.quote"
        case .url: "link"
        case .image: "photo"
        case .video: "video.fill"
        case .file: "folder"
        }
    }
}

struct TicketBorderShape: Shape {
    var cornerRadius: CGFloat = 13
    var notchRadius: CGFloat = 7
    var notch1Y: CGFloat = 52
    var toolbarHeight: CGFloat = 29

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cr = min(cornerRadius, min(w, h) / 2)
        let nr = notchRadius
        let n1 = max(cr + nr + 2, min(h - cr - nr - 2, notch1Y))
        let n2 = max(cr + nr + 2, min(h - cr - nr - 2, h - toolbarHeight - nr))

        // Top-left corner
        path.move(to: CGPoint(x: cr, y: 0))
        // Top edge
        path.addLine(to: CGPoint(x: w - cr, y: 0))
        // Top-right corner
        path.addArc(center: CGPoint(x: w - cr, y: cr), radius: cr,
                    startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)

        // Right edge down to notch 1
        path.addLine(to: CGPoint(x: w, y: n1 - nr))
        // Right notch 1 (inward arc)
        path.addArc(center: CGPoint(x: w, y: n1), radius: nr,
                    startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)

        // Right edge down to notch 2
        path.addLine(to: CGPoint(x: w, y: n2 - nr))
        // Right notch 2 (inward arc)
        path.addArc(center: CGPoint(x: w, y: n2), radius: nr,
                    startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)

        // Right edge down to bottom-right corner
        path.addLine(to: CGPoint(x: w, y: h - cr))
        path.addArc(center: CGPoint(x: w - cr, y: h - cr), radius: cr,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)

        // Bottom edge
        path.addLine(to: CGPoint(x: cr, y: h))
        // Bottom-left corner
        path.addArc(center: CGPoint(x: cr, y: h - cr), radius: cr,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)

        // Left edge up to notch 2
        path.addLine(to: CGPoint(x: 0, y: n2 + nr))
        // Left notch 2 (inward arc)
        path.addArc(center: CGPoint(x: 0, y: n2), radius: nr,
                    startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)

        // Left edge up to notch 1
        path.addLine(to: CGPoint(x: 0, y: n1 + nr))
        // Left notch 1 (inward arc)
        path.addArc(center: CGPoint(x: 0, y: n1), radius: nr,
                    startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)

        // Left edge up to top-left corner
        path.addLine(to: CGPoint(x: 0, y: cr))
        path.addArc(center: CGPoint(x: cr, y: cr), radius: cr,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)

        path.closeSubpath()
        return path
    }
}

struct PerforationDivider: View {
    let palette: PaperPalette
    var notchDiameter: CGFloat = 14
    var strokeColor: Color? = nil

    var body: some View {
        ZStack {
            DashedLine()
                .stroke(strokeColor ?? palette.cardBorder.opacity(0.35), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
                .frame(height: 0.5)
                .padding(.horizontal, notchDiameter / 2 + 1)
        }
        .frame(height: notchDiameter)
    }
}

struct DashedVerticalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: 0))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

struct VerticalPerforationDivider: View {
    let palette: PaperPalette
    var notchDiameter: CGFloat = 10
    var strokeColor: Color? = nil

    var body: some View {
        ZStack {
            DashedVerticalLine()
                .stroke(strokeColor ?? palette.cardBorder.opacity(0.35), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                .frame(width: 0.5)
        }
        .frame(width: notchDiameter)
    }
}

@MainActor
final class HoverPreviewCoordinator {
    static let shared = HoverPreviewCoordinator()

    weak var activePopoverWindow: NSWindow?
    private(set) var isHoverPreviewActive: Bool = false
    var isPinnedOpen: Bool = false
    var isInteractingWithContent: Bool = false

    func setPopoverWindow(_ window: NSWindow?) {
        self.activePopoverWindow = window
        if window != nil {
            self.isHoverPreviewActive = true
        }
    }

    func setPreviewActive(_ active: Bool) {
        if isPinnedOpen { return }
        self.isHoverPreviewActive = active
        if !active {
            self.isInteractingWithContent = false
            self.activePopoverWindow = nil
        }
    }

    func forceClose() {
        self.isPinnedOpen = false
        self.isInteractingWithContent = false
        self.isHoverPreviewActive = false
        self.activePopoverWindow = nil
    }

    func isMouseInPopoverOrBridge(drawerWindow: NSWindow?) -> Bool {
        if isPinnedOpen { return true }
        guard let popover = activePopoverWindow, popover.isVisible else {
            // Also check other visible popover windows belonging to the app
            let mouse = NSEvent.mouseLocation
            for win in NSApp.windows where win.isVisible && win != drawerWindow {
                let className = NSStringFromClass(type(of: win))
                if className.contains("Popover") || win.parent == drawerWindow {
                    if win.frame.insetBy(dx: -28, dy: -28).contains(mouse) {
                        return true
                    }
                }
            }
            return false
        }
        let mouse = NSEvent.mouseLocation

        // While mouse button is pressed (user is selecting text or dragging), never report false
        if NSEvent.pressedMouseButtons != 0 {
            return true
        }

        // 1. If we have the active popover window, test its bounds + safety margin (28pt safety padding)
        let popoverFrame = popover.frame.insetBy(dx: -28, dy: -28)
        if popoverFrame.contains(mouse) {
            return true
        }
        if let drawerWindow {
            // Gap / bridge between drawer window and popover
            let union = drawerWindow.frame.union(popover.frame).insetBy(dx: -28, dy: -28)
            if union.contains(mouse) {
                return true
            }
        }

        return false
    }
}

struct PopoverWindowTracker: NSViewRepresentable {
    let onWindowFound: (NSWindow) -> Void
    let onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> PopoverTrackingNSView {
        let view = PopoverTrackingNSView()
        view.onWindowFound = onWindowFound
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ nsView: PopoverTrackingNSView, context: Context) {
        nsView.onWindowFound = onWindowFound
        nsView.onHoverChanged = onHoverChanged
    }
}

final class PopoverTrackingNSView: NSView {
    var onWindowFound: ((NSWindow) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindowFound?(window)
            setupTrackingArea()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        setupTrackingArea()
    }

    private func setupTrackingArea() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChanged?(true)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChanged?(false)
    }
}

struct PaperHistoryCard: View {
    let item: HistoryItem
    @ObservedObject var model: AppModel
    let palette: PaperPalette
    let onPreview: () -> Void
    let onCopy: () -> Void
    let onAnnotate: () -> Void
    let onTag: () -> Void
    var preferredArrowEdge: Edge? = nil
    var showPerforation: Bool = false
    @AppStorage("drawerEdge") private var drawerEdge = "left"
    @AppStorage("doubleClickToPaste") private var doubleClickToPaste = true
    @State private var hovered = false
    @State private var isCardHovered = false
    @State private var isPopoverHovered = false
    @State private var showsHoverPreview = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var dismissTask: Task<Void, Never>?
    @State private var sourceIcon: NSImage?
    @State private var imageMetadata: ImageAssetInfo?
    @State private var isDrawerExpanded = true
    @State private var lastClickTime: Date = .distantPast
    @State private var isPerformingAction = false
    @State private var copiedFeedback = false
    @State private var feedbackText = "已复制"
    @State private var copyResetTask: Task<Void, Never>?

    private var imageTiltAngle: Double {
        let hash = abs(item.id.hashValue)
        let angles: [Double] = [-1.8, 1.5, -1.2, 2.0, -2.2, 1.4, -1.6, 1.8]
        return angles[hash % angles.count]
    }

    var body: some View {
        ZStack {
            // Stable hit-test anchor layer to prevent hover edge oscillation on rightward slide:
            Color.clear
                .padding(.leading, -7)
                .contentShape(Rectangle())

            // Main Card (with rightward slide on hover)
            HStack(spacing: 0) {
                // Left main section: Icon + Titles
                HStack(spacing: 10) {
                    // Left Icon or Image thumbnail
                    Group {
                        if item.kind == .image {
                            ImageThumbnailView(item: item, model: model, pixelSize: 96)
                                .adaptiveCardMediaFrame(cornerRadius: 4, shadowRadius: 2.5, shadowY: 1)
                                .rotationEffect(.degrees(imageTiltAngle))
                                .frame(width: 36, height: 36)
                        } else if let sourceIcon {
                            Image(nsImage: sourceIcon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 34, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            Image(systemName: symbol)
                                .font(.system(size: 16))
                                .foregroundStyle(palette.accent)
                                .frame(width: 34, height: 34)
                                .background(palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    // Middle Text: Title + Subtitle
                    VStack(alignment: .leading, spacing: 3) {
                        Text(primaryTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                            .lineLimit(1)

                        Text(secondarySubtitle)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, 4)

                if showPerforation {
                    Spacer(minLength: 2)
                    // Vertical Perforation Divider with circular notches top & bottom
                    VerticalPerforationDivider(palette: palette, notchDiameter: 10)
                        .frame(height: 60)
                } else {
                    Spacer(minLength: 8)
                }

                // Right Ticket Stub: Timestamp + Kind Badge + Status Icons
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 3) {
                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9.5))
                                .foregroundStyle(palette.accent)
                        }
                        if item.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9.5))
                                .foregroundStyle(palette.accent.opacity(0.85))
                        }
                        if item.isSnippet {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 9.5))
                                .foregroundStyle(palette.accent)
                        }
                        Text(formatTimeOnly(item.capturedAt))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                    }

                    Text(typeName)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                .padding(.trailing, 10)
            }
            .frame(height: 60)
            .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(hovered ? palette.accent : palette.cardBorder, lineWidth: hovered ? 1.5 : 1))
            .shadow(color: hovered ? palette.accent.opacity(0.32) : palette.shadow.opacity(0.24),
                    radius: hovered ? 7 : 2.5,
                    x: hovered ? 2.5 : 0,
                    y: 1.5)
            .offset(x: hovered ? 5 : 0)
            .animation(.spring(response: 0.26, dampingFraction: 0.78), value: hovered)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            handleCardClick()
        }
        .onHover { isOver in
            guard isDrawerExpanded else {
                hovered = false
                isCardHovered = false
                showsHoverPreview = false
                HoverPreviewCoordinator.shared.setPreviewActive(false)
                NotificationCenter.default.post(name: NSNotification.Name("HoverPreviewStateDidChange"), object: false)
                hoverTask?.cancel()
                dismissTask?.cancel()
                return
            }
            isCardHovered = isOver
            hovered = isOver
            if isOver {
                NotificationCenter.default.post(name: NSNotification.Name("PaperCardHovered"), object: item.id)
                dismissTask?.cancel()
                if !showsHoverPreview && !item.isDeleted {
                    hoverTask?.cancel()
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled, isCardHovered, isDrawerExpanded else { return }
                        showsHoverPreview = true
                        HoverPreviewCoordinator.shared.setPreviewActive(true)
                        NotificationCenter.default.post(name: NSNotification.Name("HoverPreviewStateDidChange"), object: true)
                    }
                }
            } else {
                hoverTask?.cancel()
                scheduleDismiss()
            }
        }
        .onDisappear {
            hoverTask?.cancel()
            dismissTask?.cancel()
            showsHoverPreview = false
            isCardHovered = false
            isPopoverHovered = false
            HoverPreviewCoordinator.shared.setPreviewActive(false)
            NotificationCenter.default.post(name: NSNotification.Name("HoverPreviewStateDidChange"), object: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PaperCardHovered"))) { notif in
            if let id = notif.object as? UUID, id != item.id {
                hoverTask?.cancel()
                dismissTask?.cancel()
                showsHoverPreview = false
                isCardHovered = false
                isPopoverHovered = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ForceCloseHoverPreview"))) { notif in
            if let id = notif.object as? UUID, id == item.id || notif.object == nil {
                hoverTask?.cancel()
                dismissTask?.cancel()
                showsHoverPreview = false
                isCardHovered = false
                isPopoverHovered = false
                hovered = false
                HoverPreviewCoordinator.shared.forceClose()
                NotificationCenter.default.post(name: NSNotification.Name("HoverPreviewStateDidChange"), object: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DrawerStateDidChange"))) { notif in
            let expanded = (notif.object as? Bool) ?? true
            isDrawerExpanded = expanded
            if !expanded {
                hoverTask?.cancel()
                dismissTask?.cancel()
                showsHoverPreview = false
                isCardHovered = false
                isPopoverHovered = false
                hovered = false
                HoverPreviewCoordinator.shared.setPreviewActive(false)
                NotificationCenter.default.post(name: NSNotification.Name("HoverPreviewStateDidChange"), object: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CardPasteOutcomeReceived"))) { notif in
            guard let cardId = notif.object as? UUID, cardId == item.id else { return }
            isPerformingAction = false
            if let outcome = notif.userInfo?["outcome"] as? QuickPasteOutcome {
                switch outcome {
                case .pasted:
                    showFeedback("已粘贴")
                case .copied:
                    showFeedback("已复制")
                case .copiedPermissionRequired:
                    showFeedback("需辅助功能权限")
                case .copiedNoTarget, .copiedActivationFailed, .copiedPasteEventFailed:
                    showFeedback("已复制")
                case .failed(let msg):
                    showFeedback("失败: \(msg)")
                }
            }
        }
        .popover(isPresented: $showsHoverPreview, attachmentAnchor: .rect(.bounds), arrowEdge: preferredArrowEdge ?? (drawerEdge == "bottom" ? .top : (drawerEdge == "top" ? .bottom : (drawerEdge == "left" ? .trailing : .leading)))) {
            HistoryHoverPreviewView(
                item: item,
                model: model,
                palette: palette,
                onPreview: {
                    showsHoverPreview = false
                    HoverPreviewCoordinator.shared.setPreviewActive(false)
                    NotificationCenter.default.post(name: NSNotification.Name("HoverPreviewStateDidChange"), object: false)
                    onPreview()
                },
                onCopy: {
                    onCopy()
                },
                onAnnotate: {
                    showsHoverPreview = false
                    HoverPreviewCoordinator.shared.setPreviewActive(false)
                    NotificationCenter.default.post(name: NSNotification.Name("HoverPreviewStateDidChange"), object: false)
                    onAnnotate()
                },
                onTag: {
                    showsHoverPreview = false
                    HoverPreviewCoordinator.shared.setPreviewActive(false)
                    NotificationCenter.default.post(name: NSNotification.Name("HoverPreviewStateDidChange"), object: false)
                    onTag()
                },
                onTrash: {
                    showsHoverPreview = false
                    HoverPreviewCoordinator.shared.setPreviewActive(false)
                    NotificationCenter.default.post(name: NSNotification.Name("HoverPreviewStateDidChange"), object: false)
                    model.moveToTrash(item)
                },
                onHoverChanged: { isOver in
                    isPopoverHovered = isOver
                    if isOver {
                        dismissTask?.cancel()
                    } else {
                        scheduleDismiss()
                    }
                }
            )
            .frame(width: 335)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(4)
        }
        .contextMenu {
            Button("直接粘贴") {
                Task { @MainActor in
                    _ = await AppDelegate.runtime?.pasteOrCopy(item: item, forceCopyOnly: false)
                }
            }
            Button("拷贝内容") {
                Task { @MainActor in
                    _ = await AppDelegate.runtime?.pasteOrCopy(item: item, forceCopyOnly: true)
                }
            }
            Button(item.isPinned ? "取消置顶" : "置顶") { model.togglePinned(item) }
            Button(item.isFavorite ? "取消收藏" : "收藏") { model.toggleFavorite(item) }
            Button("编辑标签...") { onTag() }
            if item.kind == .image {
                Button("打印图片...") {
                    Task { @MainActor in
                        guard let data = await model.originalImageData(for: item),
                              let image = NSImage(data: data) else { return }
                        ImagePrintService.shared.print(image: image, jobTitle: item.sourceName.map { "PasteLoom - \($0)" } ?? "PasteLoom 图片打印")
                    }
                }
                Button("标注图片...") { onAnnotate() }
                Button("提取图片文字 (OCR)") { model.performOCR(for: item) }
            } else {
                Button("提取纯文本") { model.performOCR(for: item) }
            }
            Button("查看详情...") { onPreview() }
            Divider()
            if item.isDeleted {
                Button("从回收站恢复") { model.restore(item) }
            } else {
                Button("移至回收站", role: .destructive) { model.moveToTrash(item) }
            }
        }
        .task(id: item.sourceBundleIdentifier) {
            guard let bundleID = item.sourceBundleIdentifier,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                sourceIcon = nil
                return
            }
            sourceIcon = NSWorkspace.shared.icon(forFile: url.path)
        }
        .task(id: item.imageRelativePath) {
            imageMetadata = await model.imageMetadata(for: item)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CardPasteOutcomeReceived"))) { notif in
            guard let cardId = notif.object as? UUID, cardId == item.id else { return }
            isPerformingAction = false
            if let outcome = notif.userInfo?["outcome"] as? QuickPasteOutcome {
                switch outcome {
                case .pasted:
                    showFeedback("已粘贴")
                case .copied:
                    showFeedback("已复制")
                case .copiedPermissionRequired:
                    showFeedback("需辅助功能权限")
                case .copiedNoTarget, .copiedActivationFailed, .copiedPasteEventFailed:
                    showFeedback("已复制")
                case .failed(let msg):
                    showFeedback("失败: \(msg)")
                }
            }
        }
    }

    private func scheduleDismiss() {
        if HoverPreviewCoordinator.shared.isPinnedOpen || HoverPreviewCoordinator.shared.isInteractingWithContent { return }
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            if HoverPreviewCoordinator.shared.isPinnedOpen || HoverPreviewCoordinator.shared.isInteractingWithContent { return }
            if NSEvent.pressedMouseButtons != 0 { return }
            if isCardHovered || isPopoverHovered { return }

            let mouse = NSEvent.mouseLocation
            if let popoverWin = HoverPreviewCoordinator.shared.activePopoverWindow, popoverWin.isVisible {
                let popoverFrame = popoverWin.frame.insetBy(dx: -36, dy: -36)
                if popoverFrame.contains(mouse) {
                    isPopoverHovered = true
                    return
                }
            }

            showsHoverPreview = false
            HoverPreviewCoordinator.shared.setPreviewActive(false)
            NotificationCenter.default.post(name: NSNotification.Name("HoverPreviewStateDidChange"), object: false)
        }
    }

    private var primaryTitle: String {
        switch item.kind {
        case .text, .richText:
            let raw = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let firstLine = raw.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? raw
            let displayText = SensitiveContentService.shared.isMaskingEnabled ? SensitiveContentService.shared.mask(firstLine) : firstLine
            return displayText.isEmpty ? "空白文本" : displayText
        case .url:
            let raw = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? "网页链接" : raw
        case .image:
            if let meta = imageMetadata {
                return "[图片 \(ByteCountFormatter.string(fromByteCount: meta.byteCount, countStyle: .file))]"
            }
            return "[图片]"
        case .video:
            return item.files.first?.name ?? "视频"
        case .file:
            if item.files.count > 1 {
                return "\(item.files.first?.name ?? "文件") 等 \(item.files.count) 项"
            }
            return item.files.first?.name ?? "本地文件"
        }
    }

    private var secondarySubtitle: String {
        var parts: [String] = []
        if let source = item.sourceName, !source.isEmpty {
            parts.append(source)
        }
        switch item.kind {
        case .text, .richText:
            parts.append("\(item.text.count) 字")
        case .url:
            if let host = URLComponents(string: item.text)?.host, !host.isEmpty {
                parts.append(host)
            } else {
                parts.append("网页链接")
            }
        case .image:
            if let meta = imageMetadata {
                parts.append("\(meta.pixelWidth)×\(meta.pixelHeight)")
            } else {
                parts.append("图像")
            }
        case .video:
            parts.append("媒体视频")
        case .file:
            if item.files.count > 1 {
                parts.append("\(item.files.count) 个文件")
            } else {
                parts.append(item.files.first?.fileExtension.uppercased() ?? "文件")
            }
        }
        return parts.joined(separator: " · ")
    }

    private func formatTimeOnly(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let df = DateFormatter()
            df.dateFormat = "HH:mm"
            return "今天 " + df.string(from: date)
        } else if cal.isDateInYesterday(date) {
            let df = DateFormatter()
            df.dateFormat = "HH:mm"
            return "昨天 " + df.string(from: date)
        } else {
            let df = DateFormatter()
            df.dateFormat = "MM-dd"
            return df.string(from: date)
        }
    }

    private var symbol: String {
        switch item.kind {
        case .text: "text.alignleft"
        case .richText: "text.quote"
        case .url: "link"
        case .image: "photo"
        case .video: "video.fill"
        case .file: "folder"
        }
    }

    private var typeName: String {
        switch item.kind {
        case .text: "文本"
        case .richText: "富文本"
        case .url: "链接"
        case .image: "图片"
        case .video: "视频"
        case .file: "文件"
        }
    }

    private func handleCardClick() {
        guard !isPerformingAction else { return }
        let now = Date()
        let isDoubleClick = (NSApp.currentEvent?.clickCount ?? 1) >= 2 || now.timeIntervalSince(lastClickTime) < 0.35
        lastClickTime = now
        executeCardPasteOrCopy(isDoubleClick: isDoubleClick)
    }

    private func executeCardPasteOrCopy(isDoubleClick: Bool) {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        let hasTarget = AppDelegate.runtime?.focus.captureTarget() != nil
        let autoPaste = AppDelegate.runtime?.model.autoPasteEnabled ?? true
        let willPaste = hasTarget && autoPaste
        showFeedback(willPaste ? "粘贴中..." : "已复制")
        onCopy()
    }

    private func showFeedback(_ text: String) {
        feedbackText = text
        withAnimation(.easeInOut(duration: 0.15)) {
            copiedFeedback = true
        }
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeInOut(duration: 0.15)) {
                copiedFeedback = false
            }
        }
    }
}


struct VerticalTicketCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: HistoryItem
    @ObservedObject var model: AppModel
    let palette: PaperPalette
    var cardIndex: Int = 0
    var isHovered: Bool? = nil
    var onHoverChanged: ((Bool) -> Void)? = nil
    let onPreview: () -> Void
    let onCopy: () -> Void
    let onAnnotate: () -> Void
    let onTag: () -> Void
    var cardHeight: CGFloat = 230
    @AppStorage("doubleClickToPaste") private var doubleClickToPaste = true
    @State private var localHovered = false
    @State private var sourceIcon: NSImage?
    @State private var imageMetadata: ImageAssetInfo?
    @State private var copiedFeedback = false
    @State private var feedbackText = "已复制"
    @State private var isExtracting = false
    @State private var isPerformingAction = false
    @State private var copyResetTask: Task<Void, Never>?
    @State private var lastClickTime: Date = .distantPast
    @State private var hoverDismissTask: Task<Void, Never>?

    private var effectiveHovered: Bool {
        isHovered ?? localHovered
    }

    private func handleCardHover(_ isOver: Bool) {
        hoverDismissTask?.cancel()
        if isOver {
            localHovered = true
            onHoverChanged?(true)
        } else {
            hoverDismissTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard !Task.isCancelled else { return }
                localHovered = false
                onHoverChanged?(false)
            }
        }
    }

    private var contentMaxHeight: CGFloat {
        max(45, cardHeight - 100)
    }

    private var imageMaxHeight: CGFloat {
        max(40, cardHeight - 105)
    }

    private var imageTiltAngle: Double {
        let hash = abs(item.id.hashValue)
        let angles: [Double] = [-1.5, 1.2, -1.0, 1.6, -1.8, 1.1, -1.3, 1.4]
        return angles[hash % angles.count]
    }

    private var metadataLine: String {
        switch item.kind {
        case .image:
            if let meta = imageMetadata {
                let sizeStr = ByteCountFormatter.string(fromByteCount: meta.byteCount, countStyle: .file)
                return "图片 · \(meta.pixelWidth) × \(meta.pixelHeight) · \(sizeStr)"
            }
            return "图片"
        case .video:
            return "视频 · \(item.files.first?.name ?? "")"
        case .url:
            return "链接 · \(URLComponents(string: item.text)?.host ?? "网址")"
        case .text, .richText:
            let count = item.text.count
            return "文本 · \(count) 字"
        case .file:
            return "文件 · \(item.files.count) 个"
        }
    }

    private func formatTimeOnly(_ date: Date) -> String {
        let cal = Calendar.current
        let df = DateFormatter()
        if cal.isDateInToday(date) {
            df.dateFormat = "今天 HH:mm"
        } else if cal.isDateInYesterday(date) {
            df.dateFormat = "昨天 HH:mm"
        } else {
            df.dateFormat = "M月d日 HH:mm"
        }
        return df.string(from: date)
    }

    private var symbol: String {
        switch item.kind {
        case .text: "text.alignleft"
        case .richText: "text.quote"
        case .url: "link"
        case .image: "photo"
        case .video: "video.fill"
        case .file: "folder"
        }
    }

    var body: some View {
        ZStack {
            // Stable hit-test anchor layer covering card motion envelope [-8, +8] pt:
            Color.clear
                .padding(.vertical, -8)
                .contentShape(Rectangle())

            // Main Ticket View (with upward slide lift on hover)
            ZStack {
                // Background fill: elevate card surface in dark mode
                TicketBorderShape()
                    .fill(palette.cardBackground)
                    .contentShape(TicketBorderShape())
                    .onTapGesture {
                        handleCardClick()
                    }

                // Card stroke border: crisp 1.0pt border with dark mode elevation
                TicketBorderShape()
                    .stroke(
                        effectiveHovered
                            ? palette.accent
                            : (palette.isDark ? palette.cardBorder.opacity(0.85) : palette.cardBorder.opacity(0.55)),
                        lineWidth: effectiveHovered ? 1.2 : 1.0
                    )

                // Main Ticket Stack
                VStack(alignment: .leading, spacing: 0) {
                    // Row 1: Header (Source App Icon + Source App Name + Pin + Time + Subtitle)
                    HStack(alignment: .top, spacing: 6) {
                        if let sourceIcon {
                            Image(nsImage: sourceIcon)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 3.5))
                        } else {
                            Image(systemName: symbol)
                                .font(.system(size: 11))
                                .foregroundStyle(palette.accent)
                                .frame(width: 16, height: 16)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(item.sourceName ?? "未知来源")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.primaryText)
                                    .lineLimit(1)

                                if item.isPinned {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(palette.accent)
                                }
                                if item.isFavorite {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(palette.accent.opacity(0.85))
                                }

                                Spacer(minLength: 4)

                                Text(formatTimeOnly(item.capturedAt))
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(palette.secondaryText)
                                    .lineLimit(1)
                            }

                            Text(metadataLine)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(palette.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 11)
                    .padding(.top, 9)
                    .padding(.bottom, 7)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleCardClick()
                    }

                    // Perforation Divider 1: with circular notches
                    PerforationDivider(
                        palette: palette,
                        notchDiameter: cardHeight < 200 ? 11 : 14,
                        strokeColor: effectiveHovered ? palette.accent : (palette.isDark ? Color.white.opacity(0.10) : palette.cardBorder.opacity(0.35))
                    )

                    // Row 2: Middle Content (Unified 3-tier Typography: Title 12pt, Body 11pt line-height 1.3, Meta 10pt)
                    ZStack(alignment: .center) {
                        switch item.kind {
                        case .image:
                            ImageThumbnailView(item: item, model: model, pixelSize: 520)
                                .adaptiveCardMediaFrame(cornerRadius: 6, shadowRadius: 5, shadowY: 2.5)
                                .rotationEffect(.degrees(imageTiltAngle))
                                .frame(maxWidth: .infinity, maxHeight: imageMaxHeight)
                        case .video:
                            ZStack {
                                ImageThumbnailView(item: item, model: model, pixelSize: 520)
                                    .adaptiveCardMediaFrame(cornerRadius: 6, shadowRadius: 5, shadowY: 2.5)
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(.white.opacity(0.95))
                                    .shadow(radius: 2)
                            }
                            .rotationEffect(.degrees(imageTiltAngle))
                            .frame(maxWidth: .infinity, maxHeight: imageMaxHeight)
                        case .text, .richText:
                            let rawText = SensitiveContentService.shared.isMaskingEnabled ? SensitiveContentService.shared.mask(item.text) : item.text
                            let displayText = OCRTextFormatter.formatIfFragmented(rawText)
                            Text(displayText)
                                .font(.system(size: 11, weight: .regular))
                                .lineSpacing(3.3)
                                .lineLimit(cardHeight > 260 ? 8 : (cardHeight < 190 ? 2 : (cardHeight < 220 ? 3 : 5)))
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(palette.primaryText)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        case .url:
                            VStack(alignment: .leading, spacing: 3) {
                                Text(URLComponents(string: item.text)?.host ?? "网页链接")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.primaryText)
                                    .lineLimit(1)
                                Text(item.text)
                                    .font(.system(size: 11, weight: .regular))
                                    .lineSpacing(3.3)
                                    .foregroundStyle(palette.secondaryText)
                                    .lineLimit(cardHeight > 260 ? 4 : (cardHeight < 200 ? 2 : 3))
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(.horizontal, 10)
                        case .file:
                            VStack(alignment: .center, spacing: 3) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(palette.accent)
                                Text(item.files.first?.name ?? "\(item.files.count) 个文件")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.primaryText)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                if let ext = item.files.first?.url.pathExtension, !ext.isEmpty {
                                    Text(ext.uppercased())
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundStyle(palette.secondaryText)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 10)
                        }

                        if copiedFeedback {
                            HStack(spacing: 4) {
                                if isExtracting {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .scaleEffect(0.65)
                                } else {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                Text(feedbackText)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(palette.cardBackground, in: Capsule())
                            .overlay(Capsule().stroke(palette.accent.opacity(0.6), lineWidth: 0.5))
                            .foregroundStyle(palette.accent)
                            .shadow(radius: 2)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: max(40, contentMaxHeight - 45), maxHeight: contentMaxHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleCardClick()
                    }

                    // Perforation Divider 2: between Content and Bottom Toolbar
                    PerforationDivider(
                        palette: palette,
                        notchDiameter: cardHeight < 200 ? 11 : 14,
                        strokeColor: effectiveHovered
                            ? palette.accent
                            : (palette.isDark ? palette.cardBorder.opacity(0.70) : palette.cardBorder.opacity(0.35))
                    )

                    // Row 3: Bottom Stub Area - 6-Button Action Toolbar (Eye, Pin, Star, Tag, OCR/Extract, Trash)
                    // 平时自动隐藏保持票据留白，鼠标移至卡片上方时平滑淡入并恢复交互
                    CardBottomToolbar(
                        item: item,
                        model: model,
                        palette: palette,
                        cardHeight: cardHeight,
                        isVisible: effectiveHovered,
                        onPreview: onPreview,
                        onTag: onTag,
                        handleExtractText: handleExtractText
                    )
                    .frame(height: cardHeight < 190 ? 20 : 22)
                    .padding(.horizontal, 4)
                    .padding(.bottom, cardHeight < 200 ? 5.5 : 7)
                    .opacity(effectiveHovered ? 1 : 0)
                    .allowsHitTesting(effectiveHovered)
                    .animation(.easeInOut(duration: 0.18), value: effectiveHovered)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .shadow(
                color: effectiveHovered
                    ? palette.accent.opacity(0.35)
                    : (palette.isDark ? Color.black.opacity(0.40) : palette.shadow.opacity(0.18)),
                radius: effectiveHovered ? 6 : (palette.isDark ? 4 : 2.5),
                y: effectiveHovered ? 3 : (palette.isDark ? 2 : 1.5)
            )
            .offset(y: effectiveHovered ? -5 : 0)
            .animation(.spring(response: 0.26, dampingFraction: 0.78), value: effectiveHovered)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { isOver in
            handleCardHover(isOver)
        }
        .onDisappear {
            hoverDismissTask?.cancel()
            hoverDismissTask = nil
            localHovered = false
        }
        .contextMenu {
            Button("直接粘贴") {
                Task { @MainActor in
                    _ = await AppDelegate.runtime?.pasteOrCopy(item: item, forceCopyOnly: false)
                }
            }
            Button("拷贝内容") {
                Task { @MainActor in
                    _ = await AppDelegate.runtime?.pasteOrCopy(item: item, forceCopyOnly: true)
                }
            }
            Button(item.isPinned ? "取消置顶" : "置顶") { model.togglePinned(item) }
            Button(item.isFavorite ? "取消收藏" : "收藏") { model.toggleFavorite(item) }
            Button("编辑标签...") { onTag() }
            if item.kind == .image {
                Button("打印图片...") {
                    Task { @MainActor in
                        guard let data = await model.originalImageData(for: item),
                              let image = NSImage(data: data) else { return }
                        ImagePrintService.shared.print(image: image, jobTitle: item.sourceName.map { "PasteLoom - \($0)" } ?? "PasteLoom 图片打印")
                    }
                }
                Button("标注图片...") { onAnnotate() }
                Button("提取图片文字 (OCR)") { handleExtractText() }
            } else {
                Button("提取纯文本") { handleExtractText() }
            }
            Button("查看详情...") { onPreview() }
            Divider()
            if item.isDeleted {
                Button("从回收站恢复") { model.restore(item) }
            } else {
                Button("移至回收站", role: .destructive) { model.moveToTrash(item) }
            }
        }
        .task(id: item.sourceBundleIdentifier) {
            guard let bundleID = item.sourceBundleIdentifier,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            sourceIcon = NSWorkspace.shared.icon(forFile: url.path)
        }
        .task(id: item.imageRelativePath) {
            imageMetadata = await model.imageMetadata(for: item)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CardPasteOutcomeReceived"))) { notif in
            guard let cardId = notif.object as? UUID, cardId == item.id else { return }
            isPerformingAction = false
            if let outcome = notif.userInfo?["outcome"] as? QuickPasteOutcome {
                switch outcome {
                case .pasted:
                    showFeedback("已粘贴")
                case .copied:
                    showFeedback("已复制")
                case .copiedPermissionRequired:
                    showFeedback("需辅助功能权限")
                case .copiedNoTarget, .copiedActivationFailed, .copiedPasteEventFailed:
                    showFeedback("已复制")
                case .failed(let msg):
                    showFeedback("失败: \(msg)")
                }
            }
        }
    }

    private func handleCardClick() {
        guard !isPerformingAction else { return }
        let now = Date()
        let isDoubleClick = (NSApp.currentEvent?.clickCount ?? 1) >= 2 || now.timeIntervalSince(lastClickTime) < 0.35
        lastClickTime = now
        executeCardPasteOrCopy(isDoubleClick: isDoubleClick)
    }

    private func executeCardPasteOrCopy(isDoubleClick: Bool) {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        let hasTarget = AppDelegate.runtime?.focus.captureTarget() != nil
        let autoPaste = AppDelegate.runtime?.model.autoPasteEnabled ?? true
        let willPaste = hasTarget && autoPaste
        showFeedback(willPaste ? "粘贴中..." : "已复制", isProgress: willPaste)
        onCopy()
    }

    private func showFeedback(_ text: String, isProgress: Bool = false) {
        feedbackText = text
        isExtracting = isProgress
        withAnimation(.easeInOut(duration: 0.15)) {
            copiedFeedback = true
        }
        copyResetTask?.cancel()
        if !isProgress {
            copyResetTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation(.easeInOut(duration: 0.15)) {
                    copiedFeedback = false
                }
            }
        }
    }

    private func handleExtractText() {
        if item.kind == .image {
            if let ocr = item.ocrText, !ocr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let formatted = OCRTextFormatter.format(ocr)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(formatted, forType: .string)
                Task {
                    try? await model.repository.incrementCopyCount(for: item.id)
                }
                showFeedback("已提取并复制")
            } else {
                showFeedback("识别中...", isProgress: true)
                Task { @MainActor in
                    let recognized = await model.performOCRAsync(for: item)
                    if let recognized, !recognized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        showFeedback("已提取并复制")
                    } else {
                        showFeedback("未识别到文字")
                    }
                }
            }
        } else {
            let textToCopy: String
            switch item.kind {
            case .text, .richText, .url:
                textToCopy = item.text
            case .file:
                textToCopy = item.files.map(\.url.path).joined(separator: "\n")
            default:
                textToCopy = item.text
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(textToCopy, forType: .string)
            Task {
                try? await model.repository.incrementCopyCount(for: item.id)
            }
            showFeedback("已提取并复制")
        }
    }
}

private struct CardBottomToolbar: View {
    let item: HistoryItem
    @ObservedObject var model: AppModel
    let palette: PaperPalette
    let cardHeight: CGFloat
    let isVisible: Bool
    let onPreview: () -> Void
    let onTag: () -> Void
    let handleExtractText: () -> Void

    private var iconSize: CGFloat {
        if cardHeight < 190 { return 10.0 }
        if cardHeight < 220 { return 11.0 }
        return 11.5
    }

    private var dividerHeight: CGFloat {
        if cardHeight < 190 { return 9.0 }
        if cardHeight < 220 { return 10.5 }
        return 11.0
    }

    var body: some View {
        HStack(spacing: 0) {
            CardToolbarButton(
                symbol: "eye",
                help: "快速预览",
                iconSize: iconSize,
                palette: palette,
                action: onPreview
            )
            btnDivider
            CardToolbarButton(
                symbol: item.isPinned ? "pin.fill" : "pin",
                help: item.isPinned ? "取消置顶" : "置顶",
                iconSize: iconSize,
                palette: palette,
                activeColor: item.isPinned ? palette.accent : nil,
                action: { model.togglePinned(item) }
            )
            btnDivider
            CardToolbarButton(
                symbol: item.isFavorite ? "star.fill" : "star",
                help: item.isFavorite ? "取消收藏" : "收藏",
                iconSize: iconSize,
                palette: palette,
                activeColor: item.isFavorite ? .yellow : nil,
                action: { model.toggleFavorite(item) }
            )
            btnDivider
            CardToolbarButton(
                symbol: "tag",
                help: "编辑标签",
                iconSize: iconSize,
                palette: palette,
                action: onTag
            )
            btnDivider
            CardToolbarButton(
                symbol: "text.viewfinder",
                help: item.kind == .image ? "提取文字 (OCR)" : "提取纯文本",
                iconSize: iconSize,
                palette: palette,
                action: handleExtractText
            )
            btnDivider
            CardToolbarButton(
                symbol: "trash",
                help: "移至回收站",
                iconSize: iconSize,
                palette: palette,
                isDestructive: true,
                action: { model.moveToTrash(item) }
            )
        }
        .contentShape(Rectangle())
    }

    private var btnDivider: some View {
        Rectangle()
            .fill(palette.cardBorder.opacity(0.40))
            .frame(width: 0.5, height: dividerHeight)
    }
}

private struct CardToolbarButton: View {
    let symbol: String
    let help: String
    let iconSize: CGFloat
    let palette: PaperPalette
    var isDestructive: Bool = false
    var activeColor: Color? = nil
    let action: () -> Void

    @State private var isHovered = false

    private var iconColor: Color {
        if isDestructive {
            return isHovered ? Color.red : Color.red.opacity(0.85)
        }
        if let activeColor {
            return activeColor
        }
        if isHovered {
            return palette.accent
        }
        return palette.primaryText.opacity(0.72)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 3.5)
                        .fill(isHovered ? (isDestructive ? Color.red.opacity(0.12) : palette.accent.opacity(0.12)) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { over in
            if isHovered != over {
                isHovered = over
            }
        }
    }
}

private struct HorizontalHistoryCard: View {
    let item: HistoryItem
    @ObservedObject var model: AppModel
    let palette: PaperPalette
    let onPreview: () -> Void
    let onCopy: () -> Void
    let onAnnotate: () -> Void
    let onTag: () -> Void
    @AppStorage("doubleClickToPaste") private var doubleClickToPaste = true
    @State private var hovered = false
    @State private var sourceIcon: NSImage?
    @State private var imageMetadata: ImageAssetInfo?
    @State private var copiedFeedback = false
    @State private var feedbackText = "已复制"
    @State private var copyResetTask: Task<Void, Never>?
    @State private var lastClickTime: Date = .distantPast
    @State private var isPerformingAction = false

    private var imageTiltAngle: Double {
        let hash = abs(item.id.hashValue)
        let angles: [Double] = [-1.8, 1.5, -1.2, 2.0, -2.2, 1.4, -1.6, 1.8]
        return angles[hash % angles.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row 1: Header (Source App Icon + Source App Name + Time + Subtitle)
            HStack(alignment: .top, spacing: 5) {
                if let sourceIcon {
                    Image(nsImage: sourceIcon).resizable().scaledToFit()
                        .frame(width: 15, height: 15)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.accent)
                        .frame(width: 15, height: 15)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(item.sourceName ?? "Unknown")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                            .lineLimit(1)

                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9.5))
                                .foregroundStyle(palette.accent)
                        }
                        if item.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(palette.accent.opacity(0.85))
                        }

                        Spacer(minLength: 2)

                        Text(formatTimeOnly(item.capturedAt))
                            .font(.system(size: 9))
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                    }

                    Text(metadataLine)
                        .font(.system(size: 8.5))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                handleCardClick()
            }

            // Perforation Divider with circular notches
            PerforationDivider(palette: palette, notchDiameter: 8)

            // Row 2: Middle Content (Height ~64pt)
            ZStack(alignment: .center) {
                switch item.kind {
                case .image:
                    ImageThumbnailView(item: item, model: model, pixelSize: 220)
                        .adaptiveCardMediaFrame(cornerRadius: 4.5, shadowRadius: 3.5, shadowY: 1.8)
                        .rotationEffect(.degrees(imageTiltAngle))
                        .frame(maxWidth: .infinity, maxHeight: 62)
                case .video:
                    ZStack {
                        ImageThumbnailView(item: item, model: model, pixelSize: 220)
                            .adaptiveCardMediaFrame(cornerRadius: 4.5, shadowRadius: 3.5, shadowY: 1.8)
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.92))
                            .shadow(color: .black.opacity(0.35), radius: 2)
                    }
                    .rotationEffect(.degrees(imageTiltAngle))
                    .frame(maxWidth: .infinity, maxHeight: 62)
                case .text, .richText:
                    let displayText = SensitiveContentService.shared.isMaskingEnabled ? SensitiveContentService.shared.mask(item.text) : item.text
                    Text(displayText)
                        .font(.system(size: 9.5))
                        .lineSpacing(1.5)
                        .lineLimit(4)
                        .foregroundStyle(palette.primaryText)
                        .frame(maxWidth: .infinity, maxHeight: 62, alignment: .topLeading)
                        .padding(.horizontal, 4)
                case .url:
                    VStack(alignment: .leading, spacing: 2) {
                        Text(URLComponents(string: item.text)?.host ?? "网页链接")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(palette.primaryText)
                            .lineLimit(1)
                        Text(item.text)
                            .font(.system(size: 9))
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 62, alignment: .topLeading)
                    .padding(.horizontal, 4)
                case .file:
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(palette.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.files.first?.name ?? "\(item.files.count) 个文件")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(palette.primaryText)
                                .lineLimit(2)
                            Text(item.files.first?.url.pathExtension.uppercased() ?? "")
                                .font(.system(size: 8.5))
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 62, alignment: .leading)
                    .padding(.horizontal, 4)
                }

                // Copy success overlay
                if copiedFeedback {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                        Text(feedbackText)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(palette.cardBackground, in: Capsule())
                    .overlay(Capsule().stroke(palette.accent.opacity(0.6), lineWidth: 0.8))
                    .foregroundStyle(palette.accent)
                    .shadow(radius: 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: 64)
            .contentShape(Rectangle())
            .onTapGesture {
                handleCardClick()
            }

            hairlineDivider

            // Row 3: 5-Button Action Toolbar (Eye, Pin, Star, Tag, Trash)
            HStack(spacing: 0) {
                toolAction("eye", "快速预览") { onPreview() }
                actionDivider
                toolAction(item.isPinned ? "pin.fill" : "pin", item.isPinned ? "取消置顶" : "置顶") {
                    model.togglePinned(item)
                }
                actionDivider
                toolAction(item.isFavorite ? "star.fill" : "star", item.isFavorite ? "取消收藏" : "收藏", iconColor: item.isFavorite ? .yellow : nil) {
                    model.toggleFavorite(item)
                }
                actionDivider
                toolAction("tag", "编辑标签") { onTag() }
                actionDivider
                toolAction("text.viewfinder", item.kind == .image ? "提取文字 (OCR)" : "提取纯文本") {
                    model.performOCR(for: item)
                }
                actionDivider
                toolAction("trash", "移至回收站", isDestructive: true) {
                    model.moveToTrash(item)
                }
            }
            .frame(height: 24)
            .padding(.horizontal, 2)
            .opacity(hovered ? 1 : 0)
            .allowsHitTesting(hovered)
            .animation(.easeInOut(duration: 0.18), value: hovered)
        }
        .frame(width: 158, height: 148)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(hovered ? palette.accent : palette.cardBorder.opacity(0.4), lineWidth: hovered ? 1.0 : 0.5)
        )
        .shadow(color: palette.shadow.opacity(hovered ? 0.6 : 0.25), radius: hovered ? 5 : 2, y: 1.5)
        .onHover { hovered = $0 }
        .contextMenu {
            Button("直接粘贴") {
                Task { @MainActor in
                    _ = await AppDelegate.runtime?.pasteOrCopy(item: item, forceCopyOnly: false)
                }
            }
            Button("拷贝内容") {
                Task { @MainActor in
                    _ = await AppDelegate.runtime?.pasteOrCopy(item: item, forceCopyOnly: true)
                }
            }
            Button(item.isPinned ? "取消置顶" : "置顶") { model.togglePinned(item) }
            Button(item.isFavorite ? "取消收藏" : "收藏") { model.toggleFavorite(item) }
            Button("编辑标签...") { onTag() }
            if item.kind == .image {
                Button("标注图片...") { onAnnotate() }
                Button("提取图片文字 (OCR)") { model.performOCR(for: item) }
            } else {
                Button("提取纯文本") { model.performOCR(for: item) }
            }
            Button("查看详情...") { onPreview() }
            Divider()
            if item.isDeleted {
                Button("从回收站恢复") { model.restore(item) }
            } else {
                Button("移至回收站", role: .destructive) { model.moveToTrash(item) }
            }
        }
        .task(id: item.sourceBundleIdentifier) {
            guard let bundleID = item.sourceBundleIdentifier,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            sourceIcon = NSWorkspace.shared.icon(forFile: url.path)
        }
        .task(id: item.imageRelativePath) {
            imageMetadata = await model.imageMetadata(for: item)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CardPasteOutcomeReceived"))) { notif in
            guard let cardId = notif.object as? UUID, cardId == item.id else { return }
            isPerformingAction = false
            if let outcome = notif.userInfo?["outcome"] as? QuickPasteOutcome {
                switch outcome {
                case .pasted:
                    showFeedback("已粘贴")
                case .copied:
                    showFeedback("已复制")
                case .copiedPermissionRequired:
                    showFeedback("需辅助功能权限")
                case .copiedNoTarget, .copiedActivationFailed, .copiedPasteEventFailed:
                    showFeedback("已复制")
                case .failed(let msg):
                    showFeedback("失败: \(msg)")
                }
            }
        }
    }

    private var cardBackground: some View {
        palette.cardBackground
    }

    private var hairlineDivider: some View {
        Rectangle()
            .fill(palette.cardBorder.opacity(0.45))
            .frame(height: 1)
    }

    private var actionDivider: some View {
        Rectangle()
            .fill(palette.cardBorder.opacity(0.45))
            .frame(width: 1, height: 12)
    }

    private func toolAction(_ symbol: String, _ help: String, isDestructive: Bool = false, iconColor: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isDestructive ? Color.red.opacity(0.85) :
                                 iconColor ?? (symbol.contains(".fill") ? palette.accent : palette.primaryText.opacity(0.72)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func handleCardClick() {
        guard !isPerformingAction else { return }
        let now = Date()
        let isDoubleClick = (NSApp.currentEvent?.clickCount ?? 1) >= 2 || now.timeIntervalSince(lastClickTime) < 0.35
        lastClickTime = now
        executeCardPasteOrCopy(isDoubleClick: isDoubleClick)
    }

    private func executeCardPasteOrCopy(isDoubleClick: Bool) {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        let hasTarget = AppDelegate.runtime?.focus.captureTarget() != nil
        let autoPaste = AppDelegate.runtime?.model.autoPasteEnabled ?? true
        let willPaste = hasTarget && autoPaste
        showFeedback(willPaste ? "粘贴中..." : "已复制")
        Task { @MainActor in
            let rt = AppDelegate.runtime
            let outcome: QuickPasteOutcome
            if let rt {
                outcome = await rt.pasteOrCopy(item: item, forceCopyOnly: false)
            } else {
                model.copy(item)
                outcome = .copied
            }
            isPerformingAction = false
            NotificationCenter.default.post(
                name: NSNotification.Name("CardPasteOutcomeReceived"),
                object: item.id,
                userInfo: ["outcome": outcome]
            )
        }
    }

    private func showFeedback(_ text: String) {
        feedbackText = text
        withAnimation(.easeInOut(duration: 0.15)) {
            copiedFeedback = true
        }
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeInOut(duration: 0.15)) {
                copiedFeedback = false
            }
        }
    }

    private var metadataLine: String {
        switch item.kind {
        case .image:
            if let meta = imageMetadata {
                return "图片 · \(meta.pixelWidth) × \(meta.pixelHeight)"
            }
            return "图片"
        case .video:
            return "视频 · \(item.files.first?.name ?? "")"
        case .url:
            return "链接 · \(URLComponents(string: item.text)?.host ?? "网址")"
        case .text, .richText:
            return "文本 · \(item.text.count) 字"
        case .file:
            if item.files.count > 1 {
                return "文件 · \(item.files.count) 项"
            }
            return "文件 · \(item.files.first?.fileExtension.uppercased() ?? "")"
        }
    }

    private func formatTimeOnly(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: date)
    }

    private var symbol: String {
        switch item.kind {
        case .text: "text.alignleft"
        case .richText: "text.quote"
        case .url: "link"
        case .image: "photo"
        case .video: "video.fill"
        case .file: "folder"
        }
    }
}

struct OCRExtractedEntity: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let type: OCREntityType
}

enum OCREntityType: String, Hashable, CaseIterable {
    case phone = "电话号码"
    case email = "邮箱地址"
    case url = "网页链接"
    case address = "地址街道"
    case code = "邮编/代码"
    case price = "金额价格"
    case frequent = "历史高频"

    var icon: String {
        switch self {
        case .phone: "phone.fill"
        case .email: "envelope.fill"
        case .url: "link"
        case .address: "mappin.and.ellipse"
        case .code: "number"
        case .price: "dollarsign.circle.fill"
        case .frequent: "sparkles"
        }
    }

    var badgeColor: Color {
        switch self {
        case .phone: .blue
        case .email: .indigo
        case .url: .cyan
        case .address: .green
        case .code: .orange
        case .price: .teal
        case .frequent: .yellow
        }
    }
}

enum OCREntityDetector {
    static func extractEntities(from text: String, historyItems: [HistoryItem] = []) -> [OCRExtractedEntity] {
        var results: [OCRExtractedEntity] = []
        var seenTexts: Set<String> = []

        func addEntity(_ str: String, type: OCREntityType) {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard trimmed.count >= 2, !seenTexts.contains(trimmed) else { return }
            seenTexts.insert(trimmed)
            results.append(OCRExtractedEntity(text: trimmed, type: type))
        }

        // 1. Phone numbers
        let phonePattern = #"(?:\+?86[-.\s]?)?1[3-9]\d{9}|(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}"#
        if let regex = try? NSRegularExpression(pattern: phonePattern) {
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for m in matches {
                addEntity(ns.substring(with: m.range), type: .phone)
            }
        }

        // 2. Email addresses
        let emailPattern = #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        if let regex = try? NSRegularExpression(pattern: emailPattern) {
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for m in matches {
                addEntity(ns.substring(with: m.range), type: .email)
            }
        }

        // 3. URLs
        let urlPattern = #"(?:https?://|www\.)[^\s]+"#
        if let regex = try? NSRegularExpression(pattern: urlPattern) {
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for m in matches {
                addEntity(ns.substring(with: m.range), type: .url)
            }
        }

        // 4. Address keywords / US/CN Street addresses
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if lower.contains("avenue") || lower.contains("street") || lower.contains("road") ||
               lower.contains("blvd") || lower.contains("lane") || lower.contains("drive") ||
               trimmed.contains("路") || trimmed.contains("街") || trimmed.contains("巷") ||
               trimmed.contains("大厦") || trimmed.contains("单元") || trimmed.contains("室") {
                addEntity(trimmed, type: .address)
            }
        }

        // 5. Postal / Zip code or 5-6 digit numeric codes
        let codePattern = #"\b\d{5}(?:-\d{4})?\b|\b\d{6}\b"#
        if let regex = try? NSRegularExpression(pattern: codePattern) {
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for m in matches {
                addEntity(ns.substring(with: m.range), type: .code)
            }
        }

        // 6. Prices / Currency
        let pricePattern = #"(?:[¥$€]\s*\d+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?\s*(?:元|USD|RMB))"#
        if let regex = try? NSRegularExpression(pattern: pricePattern) {
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for m in matches {
                addEntity(ns.substring(with: m.range), type: .price)
            }
        }

        // 7. Frequent history terms (from user's previous copies in history)
        for h in historyItems.prefix(25) {
            let hText = h.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if hText.count >= 3 && hText.count <= 25 && text.contains(hText) {
                addEntity(hText, type: .frequent)
            }
        }

        return results
    }
}

struct OCRSelectableItem: Identifiable, Hashable {
    let id: String
    let text: String
    let typeName: String
    let icon: String
    let badgeColor: Color
}

struct OCRResultInspectorView: View {
    let text: String
    @ObservedObject var model: AppModel
    let palette: PaperPalette
    let onCopy: (String) -> Void

    @State private var selectedTab: Int = 0 // 0: 全文划选, 1: 词条多选
    @State private var selectedItems: Set<String> = []
    @State private var isSmartLayout: Bool = true

    @State private var cachedEntities: [OCRExtractedEntity] = []
    @State private var cachedSelectableItems: [OCRSelectableItem] = []

    private var activeDisplayText: String {
        isSmartLayout ? OCRTextFormatter.format(text) : text
    }

    private var entities: [OCRExtractedEntity] {
        cachedEntities
    }

    private var selectableItems: [OCRSelectableItem] {
        cachedSelectableItems
    }

    private func computeItems() {
        let content = activeDisplayText
        let ents = OCREntityDetector.extractEntities(from: content, historyItems: model.items)
        cachedEntities = ents

        var results: [OCRSelectableItem] = []
        var seen = Set<String>()

        // 1. Detected key entities
        for ent in ents {
            if !seen.contains(ent.text) {
                seen.insert(ent.text)
                results.append(
                    OCRSelectableItem(
                        id: "ent_\(ent.text)",
                        text: ent.text,
                        typeName: ent.type.rawValue,
                        icon: ent.type.icon,
                        badgeColor: ent.type.badgeColor
                    )
                )
            }
        }

        // 2. Lines of text
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !seen.contains(trimmed) {
                seen.insert(trimmed)
                results.append(
                    OCRSelectableItem(
                        id: "line_\(trimmed)",
                        text: trimmed,
                        typeName: "文本行",
                        icon: "text.alignleft",
                        badgeColor: palette.secondaryText
                    )
                )
            }
        }
        cachedSelectableItems = results
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header bar: Title + Mode Switcher + Smart Layout Switch + Copy All button
            HStack(spacing: 5) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.accent)

                Text("识别内容")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                    .fixedSize()

                Spacer(minLength: 4)

                // Mode Switcher (Capsule segmented toggle)
                HStack(spacing: 0) {
                    modeTabButton("全文划选", index: 0)
                    modeTabButton(selectedItems.isEmpty ? "词条多选" : "词条 (\(selectedItems.count))", index: 1)
                }
                .fixedSize(horizontal: true, vertical: false)
                .background(palette.primaryText.opacity(0.06), in: Capsule())
                .overlay(Capsule().stroke(palette.cardBorder.opacity(0.6), lineWidth: 0.8))

                // Smart / Raw Layout switch button
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isSmartLayout.toggle()
                        computeItems()
                    }
                } label: {
                    HStack(spacing: 2.5) {
                        Image(systemName: isSmartLayout ? "text.alignleft" : "list.bullet")
                            .font(.system(size: 8.5))
                        Text(isSmartLayout ? "智能排版" : "原始逐行")
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(isSmartLayout ? palette.accent.opacity(0.12) : palette.primaryText.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(isSmartLayout ? palette.accent : palette.secondaryText)
                }
                .buttonStyle(.plain)
                .help(isSmartLayout ? "当前已根据文字内容智能集中排版，点击切换原始逐行" : "当前为原始逐行识别，点击切换智能排版")

                // Copy All button
                Button {
                    onCopy(activeDisplayText)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                        Text("全选复制")
                            .font(.system(size: 9.5, weight: .medium))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
                .help("全部复制优化排版后的完整文字")
            }

            // Body according to selected tab
            if selectedTab == 0 {
                // Tab 0: Continuous Text Selection across all lines
                VStack(alignment: .leading, spacing: 5) {
                    ScrollView {
                        Text(activeDisplayText)
                            .font(.system(size: 11.5))
                            .lineSpacing(4)
                            .foregroundStyle(palette.primaryText.opacity(0.95))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .textSelection(.enabled)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 5)
                    }
                    .frame(maxHeight: 106)
                    .background(palette.primaryText.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.cardBorder.opacity(0.5), lineWidth: 0.8))

                    // Quick Entity Chips (horizontal scroll)
                    if !entities.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4.5) {
                                ForEach(entities) { entity in
                                    Button {
                                        onCopy(entity.text)
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: entity.type.icon)
                                                .font(.system(size: 8.5))
                                                .foregroundStyle(entity.type.badgeColor)
                                            Text(entity.text)
                                                .font(.system(size: 9.5, weight: .medium))
                                                .foregroundStyle(palette.primaryText)
                                                .lineLimit(1)
                                        }
                                        .padding(.horizontal, 5.5)
                                        .padding(.vertical, 2.5)
                                        .background(entity.type.badgeColor.opacity(0.12), in: Capsule())
                                        .overlay(Capsule().stroke(entity.type.badgeColor.opacity(0.35), lineWidth: 0.8))
                                    }
                                    .buttonStyle(.plain)
                                    .help("点击单独复制: \(entity.type.rawValue)")
                                }
                            }
                            .padding(.vertical, 1)
                        }
                    }

                    // Tip footer
                    HStack(spacing: 3) {
                        Image(systemName: "cursorarrow.and.square.on.square.dashed")
                            .font(.system(size: 8.5))
                        Text("支持鼠标跨行自由拖拽划选，按 ⌘C 快速复制局部内容")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(palette.secondaryText.opacity(0.85))
                }
            } else {
                // Tab 1: Segment & Entity Multi-Picker
                VStack(alignment: .leading, spacing: 5) {
                    // Multi-select control bar
                    HStack(spacing: 6) {
                        Text(selectedItems.isEmpty ? "点击勾选多个词条组合复制" : "已勾选 \(selectedItems.count) 项")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(selectedItems.isEmpty ? palette.secondaryText : palette.accent)

                        Spacer()

                        Button("全选") {
                            selectedItems = Set(selectableItems.map(\.text))
                        }
                        .font(.system(size: 9.5))
                        .buttonStyle(.plain)
                        .foregroundStyle(palette.secondaryText)

                        Text("·")
                            .foregroundStyle(palette.secondaryText)

                        Button("清空") {
                            selectedItems.removeAll()
                        }
                        .font(.system(size: 9.5))
                        .buttonStyle(.plain)
                        .foregroundStyle(palette.secondaryText)
                    }

                    // Multi-select rows list
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(selectableItems) { item in
                                let isSelected = selectedItems.contains(item.text)
                                HStack(spacing: 6) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 11))
                                        .foregroundStyle(isSelected ? palette.accent : palette.secondaryText.opacity(0.6))

                                    HStack(spacing: 2.5) {
                                        Image(systemName: item.icon)
                                            .font(.system(size: 8))
                                        Text(item.typeName)
                                            .font(.system(size: 8.5, weight: .semibold))
                                    }
                                    .foregroundStyle(item.badgeColor)
                                    .padding(.horizontal, 4.5)
                                    .padding(.vertical, 1.5)
                                    .background(item.badgeColor.opacity(0.12), in: Capsule())

                                    Text(item.text)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(palette.primaryText)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Button {
                                        onCopy(item.text)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 9))
                                            .foregroundStyle(palette.secondaryText)
                                    }
                                    .buttonStyle(.plain)
                                    .help("单独复制此项")
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 3.5)
                                .background(
                                    isSelected ? palette.accent.opacity(0.10) : palette.primaryText.opacity(0.02),
                                    in: RoundedRectangle(cornerRadius: 5)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(isSelected ? palette.accent.opacity(0.35) : Color.clear, lineWidth: 0.8)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if isSelected {
                                        selectedItems.remove(item.text)
                                    } else {
                                        selectedItems.insert(item.text)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 96)
                    .background(palette.primaryText.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.cardBorder.opacity(0.5), lineWidth: 0.8))

                    // Bottom Multi-copy confirmation button
                    if !selectedItems.isEmpty {
                        Button {
                            let ordered = selectableItems.filter { selectedItems.contains($0.text) }.map(\.text)
                            let joined = ordered.joined(separator: "\n")
                            onCopy(joined)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc.fill")
                                    .font(.system(size: 9.5))
                                Text("复制所选 (\(selectedItems.count) 项)")
                                    .font(.system(size: 10.5, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(palette.accent, in: RoundedRectangle(cornerRadius: 5))
                            .foregroundStyle(Color.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(7)
        .background(palette.primaryText.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.cardBorder.opacity(0.6), lineWidth: 0.8))
        .onAppear {
            HoverPreviewCoordinator.shared.isInteractingWithContent = true
            computeItems()
        }
        .onChange(of: text) { _, _ in
            computeItems()
        }
        .onDisappear {
            HoverPreviewCoordinator.shared.isInteractingWithContent = false
        }
        .onHover { isOver in
            if isOver {
                HoverPreviewCoordinator.shared.isInteractingWithContent = true
            }
        }
    }

    private func modeTabButton(_ title: String, index: Int) -> some View {
        Button {
            selectedTab = index
        } label: {
            Text(title)
                .font(.system(size: 9.5, weight: selectedTab == index ? .bold : .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(selectedTab == index ? palette.primaryText : palette.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(
                    selectedTab == index ? palette.cardBackground : Color.clear,
                    in: Capsule()
                )
                .shadow(color: selectedTab == index ? Color.black.opacity(0.1) : Color.clear, radius: 1, y: 0.5)
        }
        .buttonStyle(.plain)
    }
}

struct HistoryHoverPreviewView: View {
    let item: HistoryItem
    @ObservedObject var model: AppModel
    let palette: PaperPalette
    var onPreview: (() -> Void)? = nil
    var onCopy: (() -> Void)? = nil
    var onAnnotate: (() -> Void)? = nil
    var onTag: (() -> Void)? = nil
    var onTrash: (() -> Void)? = nil
    var onHoverChanged: ((Bool) -> Void)? = nil

    @State private var sourceIcon: NSImage?
    @State private var feedbackText = "已复制"
    @State private var showFeedback = false
    @State private var isExtracting = false
    @State private var currentOCRText: String? = nil
    @State private var isTextEntitiesExpanded = false
    @State private var isWindowPinned = false
    @State private var feedbackResetTask: Task<Void, Never>?

    private var kindBadgeTitle: String {
        switch item.kind {
        case .text: "文本"
        case .richText: "富文本"
        case .url: "链接"
        case .image: "图片"
        case .video: "视频"
        case .file: "文件"
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                // Header: Source app icon + source app name + kind badge + Pin + Close
                HStack(spacing: 7) {
                    if let icon = sourceIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Image(systemName: "app.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(palette.secondaryText)
                    }

                    Text(item.sourceName ?? "未知来源")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)

                    Spacer()

                    Text(kindBadgeTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(palette.accent.opacity(0.12), in: Capsule())

                    // Window Pin Toggle
                    Button {
                        isWindowPinned.toggle()
                        HoverPreviewCoordinator.shared.isPinnedOpen = isWindowPinned
                    } label: {
                        Image(systemName: isWindowPinned ? "pin.fill" : "pin")
                            .font(.system(size: 10))
                            .foregroundStyle(isWindowPinned ? palette.accent : palette.secondaryText)
                            .padding(3.5)
                            .background(isWindowPinned ? palette.accent.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help(isWindowPinned ? "窗口已锁定常驻（不会自动隐藏），点击解除" : "锁定窗口，防止选取文字时自动隐藏")

                    // Close Window Button
                    Button {
                        HoverPreviewCoordinator.shared.forceClose()
                        NotificationCenter.default.post(name: NSNotification.Name("ForceCloseHoverPreview"), object: item.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(palette.secondaryText)
                            .padding(3.5)
                    }
                    .buttonStyle(.plain)
                    .help("关闭预览")
                }

                Rectangle()
                    .fill(palette.cardBorder.opacity(0.6))
                    .frame(height: 1)

                // Middle Content
                contentView
                    .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(palette.cardBorder.opacity(0.6))
                    .frame(height: 1)

                // Bottom Action Toolbar (7 buttons): Eye, Copy, Pin, Star, Tag, OCR/Extract, Trash
                HStack(spacing: 0) {
                    previewToolAction("eye", "快速预览") {
                        onPreview?()
                    }
                    actionDivider
                    previewToolAction("doc.on.doc", "拷贝内容") {
                        handleCopy()
                    }
                    actionDivider
                    previewToolAction(item.isPinned ? "pin.fill" : "pin", item.isPinned ? "取消置顶" : "置顶") {
                        model.togglePinned(item)
                    }
                    actionDivider
                    previewToolAction(item.isFavorite ? "star.fill" : "star", item.isFavorite ? "取消收藏" : "收藏", iconColor: item.isFavorite ? .yellow : nil) {
                        model.toggleFavorite(item)
                    }
                    actionDivider
                    previewToolAction("tag", "编辑标签") {
                        onTag?()
                    }
                    actionDivider
                    previewToolAction("text.viewfinder", item.kind == .image ? "提取文字 (OCR)" : "提取纯文本") {
                        handleExtractText()
                    }
                    if item.kind == .image {
                        actionDivider
                        previewToolAction("printer", "打印图片") {
                            Task { @MainActor in
                                if let data = await model.thumbnail(for: item, maxPixelSize: 4096),
                                   let image = NSImage(data: data) {
                                    ImagePrintService.shared.print(image: image, jobTitle: item.sourceName.map { "PasteLoom - \($0)" } ?? "PasteLoom 图片打印")
                                }
                            }
                        }
                    }
                    actionDivider
                    previewToolAction("trash", "移至回收站", isDestructive: true) {
                        onTrash?()
                    }
                }
                .frame(height: 28)
                .padding(.horizontal, 2)
            }

            // Overlay Toast / Feedback Pill
            if showFeedback {
                HStack(spacing: 4) {
                    if isExtracting {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.65)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    Text(feedbackText)
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(palette.cardBackground, in: Capsule())
                .overlay(Capsule().stroke(palette.accent.opacity(0.6), lineWidth: 0.8))
                .foregroundStyle(palette.accent)
                .shadow(radius: 2)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(10)
        .foregroundStyle(palette.primaryText)
        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(
            PopoverWindowTracker(
                onWindowFound: { win in
                    HoverPreviewCoordinator.shared.setPopoverWindow(win)
                },
                onHoverChanged: { isOver in
                    onHoverChanged?(isOver)
                }
            )
        )
        .onHover { isOver in
            onHoverChanged?(isOver)
        }
        .onAppear {
            currentOCRText = item.ocrText
        }
        .onChange(of: item.ocrText) { newText in
            currentOCRText = newText
        }
        .onDisappear {
            feedbackResetTask?.cancel()
            if isWindowPinned {
                HoverPreviewCoordinator.shared.isPinnedOpen = false
            }
            HoverPreviewCoordinator.shared.isInteractingWithContent = false
            HoverPreviewCoordinator.shared.setPopoverWindow(nil)
        }
        .task(id: item.sourceBundleIdentifier) {
            guard let bundleID = item.sourceBundleIdentifier,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                sourceIcon = nil
                return
            }
            sourceIcon = NSWorkspace.shared.icon(forFile: url.path)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch item.kind {
        case .text, .richText:
            if isTextEntitiesExpanded {
                OCRResultInspectorView(
                    text: item.text,
                    model: model,
                    palette: palette,
                    onCopy: { copiedStr in
                        handleCopyText(copiedStr)
                    }
                )
            } else {
                ScrollView {
                    Text(item.text)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.primaryText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                .frame(maxHeight: 220)
            }

        case .url:
            VStack(spacing: 8) {
                Image(systemName: "safari.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(palette.accent)

                Text(URLComponents(string: item.text)?.host ?? "网页链接")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                    .multilineTextAlignment(.center)

                Text(item.text)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 6)

        case .image:
            VStack(spacing: 7) {
                ImageThumbnailView(item: item, model: model, pixelSize: 800)
                    .scaledToFit()
                    .adaptiveCardMediaFrame(cornerRadius: 8, shadowRadius: 5, shadowY: 2.5)
                    .frame(maxHeight: ((currentOCRText != nil) || isExtracting) ? 190 : 230)
                    .frame(maxWidth: .infinity, alignment: .center)

                if isExtracting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.85)
                        Text("正在识别文字中...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(palette.primaryText.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.cardBorder.opacity(0.6), lineWidth: 0.8))
                } else if let ocr = (currentOCRText ?? item.ocrText), !ocr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    OCRResultInspectorView(
                        text: ocr,
                        model: model,
                        palette: palette,
                        onCopy: { copiedStr in
                            handleCopyText(copiedStr)
                        }
                    )
                }
            }

        case .video:
            VStack(spacing: 8) {
                ZStack {
                    ImageThumbnailView(item: item, model: model, pixelSize: 620)
                        .scaledToFit()
                        .adaptiveCardMediaFrame(cornerRadius: 8, shadowRadius: 4, shadowY: 2)
                        .frame(maxHeight: 180)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 4)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Text(item.files.first?.name ?? "视频文件")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            }

        case .file:
            VStack(spacing: 8) {
                ForEach(item.files.prefix(5), id: \.url) { file in
                    HStack(spacing: 8) {
                        FileThumbnailView(file: file).frame(width: 28, height: 28)
                        Text(file.name)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                        if !file.isAvailable {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(palette.warning)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                }
                if item.files.count > 5 {
                    Text("另有 \(item.files.count - 5) 个文件")
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
    }

    private var actionDivider: some View {
        Rectangle()
            .fill(palette.cardBorder.opacity(0.4))
            .frame(width: 1, height: 13)
    }

    private func previewToolAction(
        _ symbol: String,
        _ help: String,
        isDestructive: Bool = false,
        iconColor: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5))
                .foregroundStyle(
                    isDestructive ? Color.red.opacity(0.9) :
                    iconColor ?? (symbol.contains(".fill") ? palette.accent : palette.secondaryText)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func triggerFeedback(_ text: String, isProgress: Bool = false) {
        feedbackText = text
        isExtracting = isProgress
        withAnimation(.easeInOut(duration: 0.15)) {
            showFeedback = true
        }
        feedbackResetTask?.cancel()
        if !isProgress {
            feedbackResetTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation(.easeInOut(duration: 0.15)) {
                    showFeedback = false
                }
            }
        }
    }

    private func handleCopyText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        Task {
            try? await model.repository.incrementCopyCount(for: item.id)
        }
        triggerFeedback("已复制")
    }

    private func handleCopy() {
        onCopy?()
        triggerFeedback("已复制")
    }

    private func handleExtractText() {
        if item.kind == .image {
            if let ocr = currentOCRText ?? item.ocrText, !ocr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let formatted = OCRTextFormatter.format(ocr)
                currentOCRText = formatted
                handleCopyText(formatted)
                triggerFeedback("已复制全部识别文字")
            } else {
                triggerFeedback("文字识别中...", isProgress: true)
                isExtracting = true
                Task { @MainActor in
                    let recognized = await model.recognizeOCRText(for: item)
                    isExtracting = false
                    if let recognized, !recognized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        currentOCRText = recognized
                        triggerFeedback("识别成功！已高亮重要信息")
                    } else {
                        triggerFeedback("未识别到文字")
                    }
                }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                isTextEntitiesExpanded.toggle()
            }
            let textToCopy: String
            switch item.kind {
            case .text, .richText, .url:
                textToCopy = item.text
            case .file:
                textToCopy = item.files.map(\.url.path).joined(separator: "\n")
            default:
                textToCopy = item.text
            }
            handleCopyText(textToCopy)
        }
    }
}

struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
    }
}

private struct TopResizeHandleBar: View {
    let palette: PaperPalette
    let edge: String
    @Binding var height: Double
    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        ZStack(alignment: .top) {
            // Full-width hit test area capturing resize drag and setting resizeUpDown cursor
            TopEdgeResizeBridge(
                edge: edge,
                height: $height,
                isHovered: $isHovered,
                isDragging: $isDragging
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Centered visual grab bar at the very top edge - subtle indicator
            Capsule()
                .fill(
                    isDragging ? palette.accent :
                    (isHovered ? palette.accent.opacity(0.9) : palette.primaryText.opacity(0.28))
                )
                .frame(
                    width: isDragging ? 48 : (isHovered ? 42 : 36),
                    height: isDragging ? 3.0 : (isHovered ? 2.5 : 2.0)
                )
                .padding(.top, 1.5)
                .shadow(
                    color: (isDragging || isHovered) ? palette.accent.opacity(0.35) : Color.black.opacity(0.08),
                    radius: (isDragging || isHovered) ? 2 : 1,
                    y: 0.5
                )
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 6)
        .contentShape(Rectangle())
    }
}

private struct TopEdgeResizeBridge: NSViewRepresentable {
    let edge: String
    @Binding var height: Double
    @Binding var isHovered: Bool
    @Binding var isDragging: Bool

    func makeNSView(context: Context) -> TopEdgeResizeNSView {
        let view = TopEdgeResizeNSView()
        view.edge = edge
        view.onHoverChanged = { hovered in
            DispatchQueue.main.async {
                isHovered = hovered
            }
        }
        view.onDraggingChanged = { dragging in
            DispatchQueue.main.async {
                isDragging = dragging
            }
        }
        view.onHeightChanged = { newH in
            height = newH
        }
        return view
    }

    func updateNSView(_ nsView: TopEdgeResizeNSView, context: Context) {
        nsView.edge = edge
    }
}

private final class TopEdgeResizeNSView: NSView {
    var edge: String = "bottom"
    var onHeightChanged: ((Double) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onDraggingChanged: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var dragStartScreenY: CGFloat = 0
    private var dragStartHeight: Double = 0
    private var isDragging = false

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 6)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return bounds.contains(point) ? self : nil
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        discardCursorRects()
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeUpDown.set()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChanged?(true)
        NSCursor.resizeUpDown.set()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChanged?(false)
        if !isDragging {
            NSCursor.arrow.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        onDraggingChanged?(true)
        dragStartScreenY = NSEvent.mouseLocation.y
        let stored = UserDefaults.standard.double(forKey: "horizontalDrawerHeight")
        dragStartHeight = (stored >= 210 && stored <= 348) ? stored : 286.0
        NSCursor.resizeUpDown.set()

        NotificationCenter.default.post(name: NSNotification.Name("TopEdgeResizeDidBegin"), object: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        NSCursor.resizeUpDown.set()
        let currentScreenY = NSEvent.mouseLocation.y
        let delta = (edge == "bottom") ? (currentScreenY - dragStartScreenY) : (dragStartScreenY - currentScreenY)
        let target = max(210.0, min(348.0, dragStartHeight + Double(delta)))

        UserDefaults.standard.set(target, forKey: "horizontalDrawerHeight")

        if let win = window, let screen = win.screen ?? NSScreen.main {
            var f = win.frame
            if edge == "bottom" {
                f.origin.y = screen.frame.minY
                f.size.height = CGFloat(target) + 5.0
            } else {
                f.origin.y = screen.visibleFrame.maxY - CGFloat(target) - 5.0
                f.size.height = CGFloat(target)
            }
            win.setFrame(f, display: true)
        }
        onHeightChanged?(target)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        onDraggingChanged?(false)

        let stored = UserDefaults.standard.double(forKey: "horizontalDrawerHeight")
        UserDefaults.standard.set(stored, forKey: "horizontalDrawerHeight")
        UserDefaults.standard.synchronize()

        NotificationCenter.default.post(name: NSNotification.Name("TopEdgeResizeDidEnd"), object: nil)
        NotificationCenter.default.post(
            name: NSNotification.Name("HorizontalDrawerHeightDidChange"),
            object: stored,
            userInfo: ["animated": false]
        )
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        window?.invalidateCursorRects(for: self)
        NSCursor.arrow.set()
    }
}

private struct DrawerWindowBridge: NSViewRepresentable {
    let edge: String
    let layout: String
    func makeNSView(context: Context) -> DrawerWindowView { DrawerWindowView() }
    func updateNSView(_ nsView: DrawerWindowView, context: Context) { nsView.configure(edge: edge, layout: layout) }
}

private final class DrawerWindowView: NSView, NSWindowDelegate {
    private var isResizingTopEdge = false
    private var configuredEdge: String?
    private var configuredLayout: String?
    private var desiredEdge = "left"
    private var isCollapsed = false
    private var isProgrammaticMove = false
    private var isUserDragging = false
    private var hideTimer: Timer?
    private var expandTimer: Timer?
    private var autoHideCheckTimer: Timer?
    private var snapDebounceTimer: Timer?
    private var trackingArea: NSTrackingArea?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var mouseUpMonitor: Any?
    private var currentNormalFrame: NSRect = .zero
    private var currentCollapsedFrame: NSRect = .zero
    private var observerTokens: [Any] = []

    deinit {
        cleanup()
    }

    private func targetWindowLevel() -> NSWindow.Level {
        if isCollapsed { return .normal }
        if desiredEdge == "bottom" {
            // Keep higher than dock menus and third-party dock preview utilities like DockDoor (level 102)
            return NSWindow.Level(Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
        }
        if desiredEdge == "top" {
            return .floating
        }
        let alwaysOnTop = UserDefaults.standard.object(forKey: "windowAlwaysOnTop") == nil ? true : UserDefaults.standard.bool(forKey: "windowAlwaysOnTop")
        return alwaysOnTop ? .floating : .normal
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        if result != nil {
            return result
        }
        // When bottom-docked and expanded, absorb all unhandled mouse events within window bounds
        // so WindowServer does NOT pass hover events down to the macOS Dock or trigger DockDoor
        if desiredEdge == "bottom" && !isCollapsed && bounds.contains(point) {
            return self
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        // Absorbs click in window background / bottom margin space so it doesn't trigger Dock
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let win = window {
            let storedEdge = UserDefaults.standard.string(forKey: "drawerEdge") ?? desiredEdge
            desiredEdge = storedEdge
            win.level = targetWindowLevel()
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            win.isExcludedFromWindowsMenu = true
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = false
            win.acceptsMouseMovedEvents = true
            win.delegate = self
            setupTrackingArea()
            setupMouseMonitors()
            setupNotifications()
            hideStandardWindowButtons()
            applyFrame(for: storedEdge)

            let isAutoHide = UserDefaults.standard.object(forKey: "edgeAutoHide") == nil ? true : UserDefaults.standard.bool(forKey: "edgeAutoHide")
            if isAutoHide {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.collapseDrawer()
                }
            } else {
                startAutoHideCheckTimer()
            }
        } else {
            cleanup()
        }
    }

    private func cleanup() {
        stopAutoHideCheckTimer()
        NotificationCenter.default.post(name: NSNotification.Name("ResetDrawerHoverStates"), object: nil)
        if window?.delegate === self {
            window?.delegate = nil
        }
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens.removeAll()
        hideTimer?.invalidate()
        hideTimer = nil
        expandTimer?.invalidate()
        expandTimer = nil
        snapDebounceTimer?.invalidate()
        snapDebounceTimer = nil
        if let trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let mouseUpMonitor {
            NSEvent.removeMonitor(mouseUpMonitor)
            self.mouseUpMonitor = nil
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        setupTrackingArea()
    }

    private func setupTrackingArea() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]
        let newArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(newArea)
        self.trackingArea = newArea
    }

    private var lastMouseMoveTime: TimeInterval = 0

    private func setupMouseMonitors() {
        if mouseMonitor != nil {
            NSEvent.removeMonitor(mouseMonitor!)
            mouseMonitor = nil
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.handleGlobalMouseMove()
            }
        }

        if localMouseMonitor != nil {
            NSEvent.removeMonitor(localMouseMonitor!)
            localMouseMonitor = nil
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleGlobalMouseMove()
            return event
        }

        if mouseUpMonitor != nil {
            NSEvent.removeMonitor(mouseUpMonitor!)
            mouseUpMonitor = nil
        }
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.isResizingTopEdge {
                    self.isResizingTopEdge = false
                    UserDefaults.standard.synchronize()
                    self.clampWindowToDockedEdge()
                }
                guard self.isUserDragging else { return }
                self.isUserDragging = false
                self.evaluateMagneticSnap()
            }
        }
    }

    private func isMouseInActiveZone(_ mouse: NSPoint) -> Bool {
        if isResizingTopEdge { return true }
        if HoverPreviewCoordinator.shared.isPinnedOpen { return true }
        guard let window else { return false }
        let winFrame = window.frame
        guard let screen = window.screen ?? NSScreen.main else { return winFrame.contains(mouse) }

        if winFrame.contains(mouse) { return true }

        if TagEditorWindowController.shared.isOpen {
            return true
        }

        if HoverPreviewCoordinator.shared.isMouseInPopoverOrBridge(drawerWindow: window) {
            return true
        }

        // Edge margin tolerance for docked window (strictly around the window, not whole screen!)
        let tolerance: CGFloat = 16
        switch desiredEdge {
        case "bottom":
            let minX = winFrame.minX - tolerance
            let maxX = winFrame.maxX + tolerance
            let minY = screen.frame.minY - 10
            let maxY = winFrame.maxY + tolerance
            return mouse.x >= minX && mouse.x <= maxX && mouse.y >= minY && mouse.y <= maxY
        case "top":
            let minX = winFrame.minX - tolerance
            let maxX = winFrame.maxX + tolerance
            let minY = winFrame.minY - tolerance
            let maxY = screen.frame.maxY + 10
            return mouse.x >= minX && mouse.x <= maxX && mouse.y >= minY && mouse.y <= maxY
        case "left":
            let minX = screen.frame.minX - 10
            let maxX = winFrame.maxX + tolerance
            let minY = winFrame.minY - tolerance
            let maxY = winFrame.maxY + tolerance
            return mouse.x >= minX && mouse.x <= maxX && mouse.y >= minY && mouse.y <= maxY
        case "right":
            let minX = winFrame.minX - tolerance
            let maxX = screen.frame.maxX + 10
            let minY = winFrame.minY - tolerance
            let maxY = winFrame.maxY + tolerance
            return mouse.x >= minX && mouse.x <= maxX && mouse.y >= minY && mouse.y <= maxY
        default:
            return winFrame.contains(mouse)
        }
    }

    private func startAutoHideCheckTimer() {
        stopAutoHideCheckTimer()
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.evaluateAutoHide()
            }
        }
        timer.tolerance = 0.03
        RunLoop.main.add(timer, forMode: .common)
        self.autoHideCheckTimer = timer
    }

    private func stopAutoHideCheckTimer() {
        autoHideCheckTimer?.invalidate()
        autoHideCheckTimer = nil
    }

    private func handleGlobalMouseMove() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastMouseMoveTime < 0.05 { return }
        lastMouseMoveTime = now
        evaluateAutoHide()
    }

    private func evaluateAutoHide() {
        guard !isCollapsed, let window, !isProgrammaticMove, !isResizingTopEdge else { return }
        if HoverPreviewCoordinator.shared.isHoverPreviewActive || HoverPreviewCoordinator.shared.isPinnedOpen || TagEditorWindowController.shared.isOpen { return }
        if window.attachedSheet != nil { return }
        let isAutoHide = UserDefaults.standard.object(forKey: "edgeAutoHide") == nil ? true : UserDefaults.standard.bool(forKey: "edgeAutoHide")
        guard isAutoHide else { return }

        let mouse = NSEvent.mouseLocation
        let inZone = isMouseInActiveZone(mouse)

        if inZone {
            hideTimer?.invalidate()
            hideTimer = nil
        } else {
            NotificationCenter.default.post(name: NSNotification.Name("ResetDrawerHoverStates"), object: nil)
            if hideTimer == nil {
                let delay = UserDefaults.standard.double(forKey: "edgeHoverDelay")
                let effectiveDelay = delay > 0.05 ? delay : 0.35
                hideTimer = Timer.scheduledTimer(withTimeInterval: effectiveDelay, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, let win = self.window else { return }
                        if HoverPreviewCoordinator.shared.isHoverPreviewActive || HoverPreviewCoordinator.shared.isPinnedOpen || TagEditorWindowController.shared.isOpen { return }
                        if win.attachedSheet != nil { return }
                        let currentMouse = NSEvent.mouseLocation
                        if !self.isMouseInActiveZone(currentMouse) {
                            self.collapseDrawer()
                        }
                    }
                }
            }
        }
    }

    private func setupNotifications() {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens.removeAll()

        let resizeBeginToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TopEdgeResizeDidBegin"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isResizingTopEdge = true
        }
        observerTokens.append(resizeBeginToken)

        let resizeEndToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TopEdgeResizeDidEnd"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isResizingTopEdge = false
            self.clampWindowToDockedEdge()
        }
        observerTokens.append(resizeEndToken)

        let expandToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("EdgeHoverExpandDrawer"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard AppDelegate.runtime?.quickPaste.isQuickPasteActive != true && AppDelegate.runtime?.quickPaste.wasRecentlyActive != true else { return }
            self?.expandDrawer()
        }
        observerTokens.append(expandToken)

        let autoPasteToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CollapseDrawerForAutoPaste"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.collapseDrawer(force: true)
        }
        observerTokens.append(autoPasteToken)

        let snapToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SnapDrawerEdge"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let edge = notification.object as? String {
                let targetLayout = (edge == "bottom" || edge == "top") ? "horizontal" : "list"
                self?.configure(edge: edge, layout: targetLayout)
            }
        }
        observerTokens.append(snapToken)

        let pinToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ToggleDrawerPin"),
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self else { return }
            let isAutoHide = UserDefaults.standard.object(forKey: "edgeAutoHide") == nil ? true : UserDefaults.standard.bool(forKey: "edgeAutoHide")
            if !isAutoHide {
                self.expandDrawer()
            } else {
                self.startAutoHideCheckTimer()
                let mouse = NSEvent.mouseLocation
                if !self.isMouseInActiveZone(mouse) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        guard let self else { return }
                        if !self.isMouseInActiveZone(NSEvent.mouseLocation) {
                            self.collapseDrawer()
                        }
                    }
                }
            }
        }
        observerTokens.append(pinToken)

        let heightToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HorizontalDrawerHeightDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let win = self.window, !self.isResizingTopEdge else { return }
            self.clampWindowToDockedEdge()
            if !self.isCollapsed {
                let animated = (notification.userInfo?["animated"] as? Bool) ?? true
                if animated {
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.28
                        ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        win.animator().setFrame(self.currentNormalFrame, display: true)
                    }
                } else {
                    win.setFrame(self.currentNormalFrame, display: true)
                }
            }
        }
        observerTokens.append(heightToken)

        let topToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("WindowAlwaysOnTopDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let win = self.window else { return }
            win.level = self.targetWindowLevel()
        }
        observerTokens.append(topToken)

        if let win = window {
            win.isMovableByWindowBackground = false
            win.ignoresMouseEvents = self.isCollapsed
            let moveToken = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: win,
                queue: .main
            ) { [weak self] _ in
                self?.handleWindowDidMove()
            }
            observerTokens.append(moveToken)

            let resizeToken = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: win,
                queue: .main
            ) { [weak self] _ in
                guard let self, !self.isResizingTopEdge else { return }
                self.clampWindowToDockedEdge()
            }
            observerTokens.append(resizeToken)

            let becomeKeyToken = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: win,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.hideStandardWindowButtons()
                if self.isCollapsed || AppDelegate.runtime?.quickPaste.isQuickPasteActive == true || AppDelegate.runtime?.quickPaste.wasRecentlyActive == true {
                    return
                }
            }
            observerTokens.append(becomeKeyToken)

            let resignKeyToken = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: win,
                queue: .main
            ) { [weak self] _ in
                NotificationCenter.default.post(name: NSNotification.Name("ResetDrawerHoverStates"), object: nil)
                if HoverPreviewCoordinator.shared.isHoverPreviewActive || TagEditorWindowController.shared.isOpen { return }
                let isAutoHide = UserDefaults.standard.object(forKey: "edgeAutoHide") == nil ? true : UserDefaults.standard.bool(forKey: "edgeAutoHide")
                if isAutoHide {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        guard let self, let win = self.window else { return }
                        if HoverPreviewCoordinator.shared.isHoverPreviewActive || TagEditorWindowController.shared.isOpen { return }
                        if !win.isKeyWindow && !self.isMouseInActiveZone(NSEvent.mouseLocation) {
                            self.collapseDrawer()
                        }
                    }
                }
            }
            observerTokens.append(resignKeyToken)

            let hoverPreviewToken = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("HoverPreviewStateDidChange"),
                object: nil,
                queue: .main
            ) { [weak self] notif in
                let isActive = (notif.object as? Bool) ?? false
                if isActive {
                    self?.hideTimer?.invalidate()
                    self?.hideTimer = nil
                } else {
                    guard let self, let win = self.window else { return }
                    let mouse = NSEvent.mouseLocation
                    if !self.isMouseInActiveZone(mouse) {
                        self.handleGlobalMouseMove()
                    }
                }
            }
            observerTokens.append(hoverPreviewToken)

            let modalClosedToken = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ModalSheetClosed"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, let win = self.window else { return }
                let mouse = NSEvent.mouseLocation
                if !self.isMouseInActiveZone(mouse) {
                    self.handleGlobalMouseMove()
                }
            }
            observerTokens.append(modalClosedToken)
        }
    }

    private func handleWindowDidMove() {
        guard !isProgrammaticMove, !isCollapsed, !isResizingTopEdge else { return }
        if NSEvent.pressedMouseButtons != 0 {
            isUserDragging = true
            return
        }
        clampWindowToDockedEdge()
        snapDebounceTimer?.invalidate()
        snapDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isProgrammaticMove, !self.isResizingTopEdge else { return }
                self.evaluateMagneticSnap()
            }
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let screen = sender.screen ?? NSScreen.main else { return frameSize }
        let available = screen.visibleFrame
        let edgeMargin: CGFloat = 5.0
        let isHorizontal = (desiredEdge == "top" || desiredEdge == "bottom")
        if isHorizontal {
            let clampedH: CGFloat = min(348, max(210, frameSize.height - (desiredEdge == "bottom" ? edgeMargin : 0)))
            let targetW = (desiredEdge == "bottom" ? screen.frame.width : available.width) - edgeMargin * 2
            let targetH = clampedH + (desiredEdge == "bottom" ? edgeMargin : 0)
            UserDefaults.standard.set(Double(clampedH), forKey: "horizontalDrawerHeight")
            NotificationCenter.default.post(
                name: NSNotification.Name("HorizontalDrawerHeightDidChange"),
                object: Double(clampedH),
                userInfo: ["animated": false]
            )
            return NSSize(width: targetW, height: targetH)
        } else {
            let clampedW = min(340, max(280, frameSize.width))
            let targetH = available.height - edgeMargin * 2
            return NSSize(width: clampedW, height: targetH)
        }
    }

    func windowDidResize(_ notification: Notification) {
        clampWindowToDockedEdge()
    }

    func windowDidMove(_ notification: Notification) {
        clampWindowToDockedEdge()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        discardCursorRects()
        if desiredEdge == "bottom" {
            let topRect = NSRect(x: 0, y: bounds.height - 16, width: bounds.width, height: 16)
            addCursorRect(topRect, cursor: .resizeUpDown)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
    }

    private func clampWindowToDockedEdge() {
        guard let window, !isProgrammaticMove, !isResizingTopEdge else { return }
        let screen = window.screen ?? NSScreen.main
        guard let screen else { return }
        let available = screen.visibleFrame
        let edgeMargin: CGFloat = 5.0
        let isHorizontal = (desiredEdge == "top" || desiredEdge == "bottom")

        var frame = window.frame
        if isHorizontal {
            let storedH = UserDefaults.standard.double(forKey: "horizontalDrawerHeight")
            let clampedH: CGFloat = min(348, max(210, storedH > 0 ? CGFloat(storedH) : 286))
            if desiredEdge == "bottom" {
                frame.origin.x = screen.frame.minX + edgeMargin
                frame.origin.y = screen.frame.minY
                frame.size.width = screen.frame.width - edgeMargin * 2
                frame.size.height = clampedH + edgeMargin
            } else { // top
                frame.size.height = clampedH
                frame.origin.x = available.minX + edgeMargin
                frame.origin.y = available.maxY - clampedH - edgeMargin
                frame.size.width = available.width - edgeMargin * 2
            }
        } else {
            let clampedWidth = min(340, max(280, frame.size.width))
            frame.size.width = clampedWidth
            frame.size.height = available.height - edgeMargin * 2
            frame.origin.y = available.minY + edgeMargin
            if desiredEdge == "right" {
                frame.origin.x = available.maxX - clampedWidth - edgeMargin
            } else { // left
                frame.origin.x = available.minX + edgeMargin
            }
            UserDefaults.standard.set(clampedWidth, forKey: "verticalDrawerWidth")
        }

        self.currentNormalFrame = frame
        switch desiredEdge {
        case "right":
            self.currentCollapsedFrame = NSRect(x: available.maxX + edgeMargin, y: frame.origin.y, width: frame.size.width, height: frame.size.height)
        case "left":
            self.currentCollapsedFrame = NSRect(x: available.minX - frame.size.width - edgeMargin, y: frame.origin.y, width: frame.size.width, height: frame.size.height)
        case "top":
            self.currentCollapsedFrame = NSRect(x: frame.origin.x, y: available.maxY + edgeMargin, width: frame.size.width, height: frame.size.height)
        default: // bottom
            self.currentCollapsedFrame = NSRect(x: frame.origin.x, y: screen.frame.minY - frame.size.height - edgeMargin, width: frame.size.width, height: frame.size.height)
        }

        if !isCollapsed {
            let diffX = abs(window.frame.origin.x - frame.origin.x)
            let diffY = abs(window.frame.origin.y - frame.origin.y)
            let diffW = abs(window.frame.size.width - frame.size.width)
            let diffH = abs(window.frame.size.height - frame.size.height)
            if diffX > 0.5 || diffY > 0.5 || diffW > 0.5 || diffH > 0.5 {
                isProgrammaticMove = true
                window.setFrame(frame, display: true)
                isProgrammaticMove = false
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        if isResizingTopEdge {
            isResizingTopEdge = false
            UserDefaults.standard.synchronize()
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            clampWindowToDockedEdge()
            NSCursor.arrow.set()
        }
        if isUserDragging {
            isUserDragging = false
            evaluateMagneticSnap()
        }
    }

    private func evaluateMagneticSnap() {
        guard let window, !isCollapsed, !isProgrammaticMove else { return }
        let screen = window.screen ?? NSScreen.main
        guard let screen else { return }
        let available = screen.visibleFrame
        let winFrame = window.frame

        let midX = winFrame.midX
        let midY = winFrame.midY

        let distLeft = midX - available.minX
        let distRight = available.maxX - midX
        let distTop = available.maxY - midY
        let distBottom = midY - available.minY

        let candidates: [(edge: String, dist: CGFloat)] = [
            ("left", distLeft),
            ("right", distRight),
            ("top", distTop),
            ("bottom", distBottom)
        ]
        guard let closest = candidates.min(by: { $0.dist < $1.dist }) else { return }

        let snapped = closest.edge
        let currentStored = UserDefaults.standard.string(forKey: "historyLayout") ?? "list"
        let targetLayout = (snapped == "bottom" || snapped == "top") ? "horizontal" : (currentStored == "horizontal" ? "list" : currentStored)
        let edgeChanged = snapped != configuredEdge

        configuredEdge = snapped
        desiredEdge = snapped
        configuredLayout = targetLayout

        UserDefaults.standard.set(snapped, forKey: "drawerEdge")
        UserDefaults.standard.set(snapped, forKey: "edgeHoverSide")
        UserDefaults.standard.set(targetLayout, forKey: "historyLayout")
        UserDefaults.standard.synchronize()

        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        if edgeChanged {
            NotificationCenter.default.post(name: NSNotification.Name("DrawerEdgeDidChange"), object: snapped)
        }
        applyFrame(for: snapped)
    }

    private func hideStandardWindowButtons() {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let btn = window.standardWindowButton(button) {
                btn.isHidden = true
                btn.alphaValue = 0
                btn.isEnabled = false
            }
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        hideTimer?.invalidate()
        hideTimer = nil
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NotificationCenter.default.post(name: NSNotification.Name("ResetDrawerHoverStates"), object: nil)
        if HoverPreviewCoordinator.shared.isHoverPreviewActive || TagEditorWindowController.shared.isOpen { return }
        let isAutoHide = UserDefaults.standard.object(forKey: "edgeAutoHide") == nil ? true : UserDefaults.standard.bool(forKey: "edgeAutoHide")
        guard isAutoHide else { return }
        hideTimer?.invalidate()
        let delay = UserDefaults.standard.double(forKey: "edgeHoverDelay")
        let effectiveDelay = delay > 0.05 ? delay : 0.4
        hideTimer = Timer.scheduledTimer(withTimeInterval: effectiveDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let win = self.window else { return }
                if HoverPreviewCoordinator.shared.isHoverPreviewActive || TagEditorWindowController.shared.isOpen { return }
                let currentMouse = NSEvent.mouseLocation
                if !self.isMouseInActiveZone(currentMouse) {
                    self.collapseDrawer()
                }
            }
        }
    }

    func expandDrawer() {
        guard let window else { return }
        if AppDelegate.runtime?.quickPaste.isQuickPasteActive == true || AppDelegate.runtime?.quickPaste.wasRecentlyActive == true {
            return
        }
        _ = AppDelegate.runtime?.focus.captureTarget()
        isCollapsed = false
        window.ignoresMouseEvents = false
        expandTimer?.invalidate()
        expandTimer = nil
        hideTimer?.invalidate()
        hideTimer = nil
        window.level = targetWindowLevel()
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
            window.animator().setFrame(currentNormalFrame, display: true)
        }
        NotificationCenter.default.post(name: NSNotification.Name("DrawerStateDidChange"), object: true)
        startAutoHideCheckTimer()
    }

    func collapseDrawer(force: Bool = false) {
        guard let window, !isCollapsed, !isResizingTopEdge else { return }
        NotificationCenter.default.post(name: NSNotification.Name("ResetDrawerHoverStates"), object: nil)
        if !force && (HoverPreviewCoordinator.shared.isHoverPreviewActive || HoverPreviewCoordinator.shared.isPinnedOpen || TagEditorWindowController.shared.isOpen) { return }
        let isAutoHide = UserDefaults.standard.object(forKey: "edgeAutoHide") == nil ? true : UserDefaults.standard.bool(forKey: "edgeAutoHide")
        guard force || isAutoHide else { return }
        if !force && window.attachedSheet != nil { return }
        HoverPreviewCoordinator.shared.forceClose()
        isCollapsed = true
        window.ignoresMouseEvents = true
        expandTimer?.invalidate()
        expandTimer = nil
        hideTimer?.invalidate()
        hideTimer = nil
        stopAutoHideCheckTimer()
        NotificationCenter.default.post(name: NSNotification.Name("DrawerStateDidChange"), object: false)

        if force {
            window.resignKey()
            window.level = .normal
            window.orderOut(nil)
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0.0
            window.animator().setFrame(currentCollapsedFrame, display: true)
        }, completionHandler: { [weak window, weak self] in
            guard let self, self.isCollapsed else { return }
            window?.level = .normal
            window?.ignoresMouseEvents = true
            window?.alphaValue = 0.0
            AppDelegate.runtime?.model.trimMemory()
        })
    }

    func configure(edge: String, layout: String? = nil) {
        let currentLayout = layout ?? ((edge == "bottom" || edge == "top") ? "horizontal" : "list")
        let changed = configuredEdge != edge || configuredLayout != currentLayout
        desiredEdge = edge
        configuredLayout = currentLayout
        if (changed || configuredEdge == nil), window != nil {
            applyFrame(for: edge)
        }
    }

    private func applyFrame(for edge: String) {
        guard let window else { return }
        configuredEdge = edge
        desiredEdge = edge
        isProgrammaticMove = true
        snapDebounceTimer?.invalidate()
        snapDebounceTimer = nil

        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.hideStandardWindowButtons()
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? window.screen ?? NSScreen.main
            guard let screen else {
                self.isProgrammaticMove = false
                return
            }
            let available = screen.visibleFrame
            let isHorizontal = (edge == "top" || edge == "bottom")
            let currentStored = UserDefaults.standard.string(forKey: "historyLayout") ?? "list"
            let targetLayout = isHorizontal ? "horizontal" : (currentStored == "horizontal" ? "list" : currentStored)
            self.configuredLayout = targetLayout

            let edgeMargin: CGFloat = 5.0
            let storedWidth = UserDefaults.standard.double(forKey: "verticalDrawerWidth")
            let verticalDrawerWidth: CGFloat = (storedWidth >= 280 && storedWidth <= 340) ? storedWidth : 280

            let storedH = UserDefaults.standard.double(forKey: "horizontalDrawerHeight")
            let horizontalHeight: CGFloat = min(348, max(210, storedH > 0 ? CGFloat(storedH) : 286))
            let width: CGFloat = isHorizontal ? ((edge == "bottom" ? screen.frame.width : available.width) - edgeMargin * 2) : verticalDrawerWidth
            let height: CGFloat = isHorizontal ? (horizontalHeight + (edge == "bottom" ? edgeMargin : 0)) : (available.height - edgeMargin * 2)

            window.contentMinSize = isHorizontal
                ? NSSize(width: min(500, width), height: 210)
                : NSSize(width: 280, height: min(400, height))
            window.contentMaxSize = isHorizontal
                ? NSSize(width: (edge == "bottom" ? screen.frame.width : available.width) - edgeMargin * 2, height: 348 + (edge == "bottom" ? edgeMargin : 0))
                : NSSize(width: 340, height: available.height - edgeMargin * 2)
            window.setContentSize(NSSize(width: width, height: height))

            let normalX: CGFloat
            let normalY: CGFloat
            let collapsedX: CGFloat
            let collapsedY: CGFloat

            switch edge {
            case "right":
                normalX = available.maxX - width - edgeMargin
                normalY = available.minY + edgeMargin
                collapsedX = available.maxX + edgeMargin
                collapsedY = normalY
            case "top":
                normalX = available.minX + edgeMargin
                normalY = available.maxY - height - edgeMargin
                collapsedX = normalX
                collapsedY = available.maxY + edgeMargin
            case "bottom":
                normalX = screen.frame.minX + edgeMargin
                normalY = screen.frame.minY
                collapsedX = normalX
                collapsedY = screen.frame.minY - height - edgeMargin
            default: // left
                normalX = available.minX + edgeMargin
                normalY = available.minY + edgeMargin
                collapsedX = available.minX - width - edgeMargin
                collapsedY = normalY
            }

            self.currentNormalFrame = NSRect(x: normalX, y: normalY, width: width, height: height)
            self.currentCollapsedFrame = NSRect(x: collapsedX, y: collapsedY, width: width, height: height)

            let targetFrame = self.isCollapsed ? self.currentCollapsedFrame : self.currentNormalFrame

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(targetFrame, display: true)
                window.animator().alphaValue = self.isCollapsed ? 0.0 : 1.0
            }

            self.hideStandardWindowButtons()
            window.ignoresMouseEvents = self.isCollapsed
            window.level = self.targetWindowLevel()
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            window.isExcludedFromWindowsMenu = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.contentView?.wantsLayer = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.isProgrammaticMove = false
            }
        }
    }
}

// MARK: - Image Printing Service

final class ImagePrintCanvasView: NSView {
    let image: NSImage

    init(image: NSImage, frame: NSRect) {
        self.image = image
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: 1)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard image.size.width > 0, image.size.height > 0 else { return }

        let targetRect = bounds
        let imgSize = image.size
        let scale = min(targetRect.width / imgSize.width, targetRect.height / imgSize.height)
        let drawWidth = max(1, imgSize.width * scale)
        let drawHeight = max(1, imgSize.height * scale)
        let drawX = targetRect.origin.x + (targetRect.width - drawWidth) / 2
        let drawY = targetRect.origin.y + (targetRect.height - drawHeight) / 2
        let drawRect = NSRect(x: drawX, y: drawY, width: drawWidth, height: drawHeight)

        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
}

@MainActor
final class ImagePrintService {
    static let shared = ImagePrintService()

    func makePrintOperation(
        for image: NSImage,
        jobTitle: String = "PasteLoom 图片打印",
        basePrintInfo: NSPrintInfo? = nil,
        showsPrintPanel: Bool = true,
        showsProgressPanel: Bool = true
    ) -> NSPrintOperation {
        let printInfo = ((basePrintInfo ?? NSPrintInfo.shared).copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true
        printInfo.jobDisposition = .spool

        // Match orientation to image aspect ratio
        let isLandscape = image.size.width > image.size.height
        printInfo.orientation = isLandscape ? .landscape : .portrait

        let canvasSize: NSSize
        let imageableBounds = printInfo.imageablePageBounds
        if imageableBounds.width > 0 && imageableBounds.height > 0 {
            canvasSize = imageableBounds.size
        } else if printInfo.paperSize.width > 0 && printInfo.paperSize.height > 0 {
            canvasSize = printInfo.paperSize
        } else {
            canvasSize = image.size
        }

        let printView = ImagePrintCanvasView(image: image, frame: NSRect(origin: .zero, size: canvasSize))
        let operation = NSPrintOperation(view: printView, printInfo: printInfo)
        operation.jobTitle = jobTitle
        operation.showsPrintPanel = showsPrintPanel
        operation.showsProgressPanel = showsProgressPanel
        return operation
    }

    @discardableResult
    func print(
        image: NSImage,
        window: NSWindow? = nil,
        jobTitle: String = "PasteLoom 图片打印",
        asSheet: Bool = false
    ) -> Bool {
        let operation = makePrintOperation(for: image, jobTitle: jobTitle)
        if asSheet, let window, window.isVisible {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
            return true
        } else {
            return operation.run()
        }
    }
}

private struct HistoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let item: HistoryItem
    @ObservedObject var model: AppModel
    var palette: PaperPalette? = nil
    var onClose: (() -> Void)? = nil
    @State private var quickLookURL: URL?
    @State private var copied = false
    @State private var isPrinting = false

    private func closeView() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func annotateImage() {
        Task {
            guard let data = await model.originalImageData(for: item) else { return }
            let document = ScreenshotDocument(pngData: data)
            ScreenshotEditorWindowController.shared.show(document: document)
        }
    }

    private func printImage() {
        guard !isPrinting else { return }
        isPrinting = true
        Task { @MainActor in
            defer { isPrinting = false }
            guard let data = await model.originalImageData(for: item),
                  let image = NSImage(data: data) else {
                NSSound.beep()
                return
            }
            let title = item.sourceName.map { "PasteLoom - \($0)" } ?? "PasteLoom 图片打印"
            ImagePrintService.shared.print(image: image, jobTitle: title)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Row
            HStack(spacing: 10) {
                Label(title, systemImage: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette?.primaryText ?? Color.primary)
                    .lineLimit(1)

                if let source = item.sourceName {
                    Text("·")
                        .foregroundStyle(palette?.secondaryText ?? Color.secondary)
                    Text(source)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette?.secondaryText ?? Color.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if item.kind == .url, let url = URL(string: item.text) {
                    Button("打开链接") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                if item.kind == .image {
                    Button {
                        printImage()
                    } label: {
                        HStack(spacing: 4) {
                            if isPrinting {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "printer")
                            }
                            Text("打印")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isPrinting)
                    .help("打印图片 (⌘P)")
                    .keyboardShortcut("p", modifiers: .command)

                    Button("标注图片") { annotateImage() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                    if item.ocrText == nil || item.ocrText?.isEmpty == true {
                        Button("提取文字 (OCR)") { model.performOCR(for: item) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                Button {
                    model.copy(item)
                    withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "已复制" : "复制")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    closeView()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(palette?.secondaryText ?? Color.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭 (Esc)")
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .background(palette?.sidebarBackground ?? Color(nsColor: .windowBackgroundColor))

            Divider()

            // Main Content Body
            if item.kind == .image {
                imagePreviewContent
            } else {
                ScrollView {
                VStack(spacing: 14) {
                    switch item.kind {
                    case .text, .richText:
                        VStack(alignment: .leading, spacing: 10) {
                            Text(item.text)
                                .font(.system(size: 14))
                                .lineSpacing(5)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(palette?.cardBackground ?? Color(nsColor: .controlBackgroundColor),
                                            in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette?.cardBorder.opacity(0.6) ?? Color.gray.opacity(0.2), lineWidth: 0.8))

                            HStack {
                                Text("\(item.text.count) 个字符 · \(item.text.split(whereSeparator: \.isWhitespace).count) 词")
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette?.secondaryText ?? Color.secondary)
                                Spacer()
                                Text(formatRelativeTime(item.capturedAt))
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette?.secondaryText ?? Color.secondary)
                            }
                            .padding(.horizontal, 4)
                        }
                    case .url:
                        VStack(alignment: .center, spacing: 12) {
                            Image(systemName: "link.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(palette?.accent ?? Color.blue)

                            Text(URLComponents(string: item.text)?.host ?? "网页链接")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(palette?.primaryText ?? Color.primary)

                            Text(item.text)
                                .font(.system(size: 13))
                                .foregroundStyle(palette?.secondaryText ?? Color.secondary)
                                .textSelection(.enabled)
                                .multilineTextAlignment(.center)
                                .padding(12)
                                .background(palette?.cardBackground ?? Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                            if let url = URL(string: item.text) {
                                Button("在浏览器中打开") {
                                    NSWorkspace.shared.open(url)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    case .image:
                        EmptyView()
                    case .video:
                        VStack(spacing: 12) {
                            ZStack {
                                ImageThumbnailView(item: item, model: model, pixelSize: 1800)
                                    .frame(maxWidth: .infinity, maxHeight: 360)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                if let first = item.files.first, first.isAvailable {
                                    Button {
                                        quickLookURL = first.url
                                    } label: {
                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 64))
                                            .foregroundStyle(.white.opacity(0.92))
                                            .shadow(radius: 4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            if let first = item.files.first {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(first.name).font(.system(size: 13, weight: .semibold))
                                        Text(first.url.path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if first.isAvailable {
                                        Button("系统播放器打开") { NSWorkspace.shared.open(first.url) }
                                            .buttonStyle(.bordered)
                                        Button("快速预览") { quickLookURL = first.url }
                                            .buttonStyle(.borderedProminent)
                                    }
                                }
                            }
                        }
                    case .file:
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(item.files, id: \.url) { file in
                                HStack(spacing: 10) {
                                    FileThumbnailView(file: file).frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(file.name).font(.system(size: 13, weight: .semibold))
                                        Text(file.url.deletingLastPathComponent().path)
                                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                        Text(file.isAvailable ? "可用" : "原文件不可用")
                                            .font(.system(size: 10))
                                            .foregroundStyle(file.isAvailable ? .green : .orange)
                                    }
                                    Spacer()
                                    if file.isAvailable {
                                        Button("快速查看") { quickLookURL = file.url }
                                            .buttonStyle(.bordered)
                                        Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                                            .buttonStyle(.bordered)
                                    }
                                }
                                .padding(10)
                                .background(palette?.cardBackground ?? Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        }
        .frame(minWidth: 380, minHeight: 300)
        .background(palette?.cardBackground ?? Color(nsColor: .windowBackgroundColor))
        .quickLookPreview($quickLookURL)
    }

    @ViewBuilder
    private var imagePreviewContent: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                ImageThumbnailView(item: item, model: model, pixelSize: 2048)
                    .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                    .adaptiveCardMediaFrame(cornerRadius: 8, shadowRadius: 6, shadowY: 2.5)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                    .contextMenu {
                        Button {
                            printImage()
                        } label: {
                            Label("打印图片 (⌘P)", systemImage: "printer")
                        }
                        Divider()
                        Button {
                            annotateImage()
                        } label: {
                            Label("标注图片", systemImage: "pencil.tip.crop.circle")
                        }
                        Button {
                            model.copy(item)
                        } label: {
                            Label("复制图片", systemImage: "doc.on.doc")
                        }
                        if let ocr = item.ocrText, !ocr.isEmpty {
                            Button {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(OCRTextFormatter.format(ocr), forType: .string)
                            } label: {
                                Label("复制识别文字", systemImage: "text.viewfinder")
                            }
                        }
                    }
            }

            if let ocr = item.ocrText, !ocr.isEmpty {
                let formattedOCR = OCRTextFormatter.format(ocr)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("识别文字 (OCR)", systemImage: "text.viewfinder")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette?.primaryText ?? Color.primary)
                        Spacer()
                        Button("复制识别文字") {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(formattedOCR, forType: .string)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    ScrollView {
                        Text(formattedOCR)
                            .font(.system(size: 12))
                            .lineSpacing(3.5)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 100)
                    .background(palette?.cardBackground ?? Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var symbol: String {
        switch item.kind {
        case .text: "doc.text"
        case .richText: "text.quote"
        case .url: "link"
        case .image: "photo"
        case .video: "video.fill"
        case .file: "folder"
        }
    }

    private var title: String {
        switch item.kind {
        case .text: "文本预览"
        case .richText: "富文本预览"
        case .url: "网址预览"
        case .image: "图片预览"
        case .video: "视频预览"
        case .file: "文件预览"
        }
    }
}

@MainActor
final class HistoryPreviewWindowController: NSObject, NSWindowDelegate {
    static let shared = HistoryPreviewWindowController()
    private(set) var window: HistoryPreviewWindow?
    private var activeTask: Task<Void, Never>?
    private(set) var currentItem: HistoryItem?
    private weak var currentModel: AppModel?

    var canPrintCurrentImage: Bool {
        currentItem?.kind == .image && currentModel != nil
    }

    func printCurrentImage() {
        guard let item = currentItem, item.kind == .image, let model = currentModel else { return }
        Task { @MainActor in
            guard let data = await model.originalImageData(for: item),
                  let image = NSImage(data: data) else {
                NSSound.beep()
                return
            }
            let title = item.sourceName.map { "PasteLoom - \($0)" } ?? "PasteLoom 图片打印"
            ImagePrintService.shared.print(image: image, jobTitle: title)
        }
    }

    func show(item: HistoryItem, model: AppModel, palette: PaperPalette) {
        activeTask?.cancel()
        close()

        self.currentItem = item
        self.currentModel = model

        activeTask = Task { @MainActor in
            var imageSize: CGSize? = nil
            if item.kind == .image {
                if let meta = await model.imageMetadata(for: item), meta.pixelWidth > 0, meta.pixelHeight > 0 {
                    imageSize = CGSize(width: meta.pixelWidth, height: meta.pixelHeight)
                }
            }
            guard !Task.isCancelled else { return }
            self.presentWindow(item: item, model: model, palette: palette, imageSize: imageSize)
        }
    }

    private func presentWindow(item: HistoryItem, model: AppModel, palette: PaperPalette, imageSize: CGSize?) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let visible = screen.visibleFrame
        let targetWidth: CGFloat
        let targetHeight: CGFloat
        switch item.kind {
        case .image:
            if let imageSize, imageSize.width > 0, imageSize.height > 0 {
                let aspect = imageSize.width / imageSize.height
                let extraH: CGFloat = (item.ocrText?.isEmpty == false) ? 160 : 70
                let maxW = min(visible.width * 0.82, 1080)
                let maxH = min(visible.height * 0.82 - extraH, 780)

                var fitW: CGFloat = max(400, min(imageSize.width, maxW))
                var fitH: CGFloat = fitW / aspect

                if fitH > maxH {
                    fitH = maxH
                    fitW = fitH * aspect
                }
                if fitW > maxW {
                    fitW = maxW
                    fitH = fitW / aspect
                }
                if fitH < 260 {
                    fitH = 260
                    fitW = fitH * aspect
                }

                targetWidth = min(visible.width * 0.85, max(420, fitW + 36))
                targetHeight = min(visible.height * 0.85, max(340, fitH + extraH))
            } else {
                targetWidth = min(800, max(560, visible.width * 0.6))
                targetHeight = min(620, max(460, visible.height * 0.6))
            }
        case .text, .richText:
            targetWidth = min(720, max(560, visible.width * 0.55))
            targetHeight = min(560, max(440, visible.height * 0.58))
        case .url:
            targetWidth = min(680, max(520, visible.width * 0.5))
            targetHeight = min(460, max(360, visible.height * 0.45))
        case .video, .file:
            targetWidth = min(760, max(600, visible.width * 0.58))
            targetHeight = min(580, max(460, visible.height * 0.58))
        }

        let originX = visible.midX - targetWidth / 2
        let originY = visible.midY - targetHeight / 2
        let frameRect = NSRect(x: originX, y: originY, width: targetWidth, height: targetHeight)

        let newWindow = HistoryPreviewWindow(
            contentRect: frameRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "PasteLoom · 预览"
        newWindow.titleVisibility = .hidden
        newWindow.titlebarAppearsTransparent = true
        newWindow.isMovableByWindowBackground = true
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating
        newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        newWindow.isExcludedFromWindowsMenu = true
        newWindow.backgroundColor = .clear
        newWindow.isOpaque = false
        newWindow.hasShadow = true
        newWindow.delegate = self
        newWindow.minSize = NSSize(width: 380, height: 300)

        let previewView = HistoryDetailView(item: item, model: model, palette: palette, onClose: { [weak self] in
            self?.close()
        })
        newWindow.contentView = NSHostingView(rootView: previewView)

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        activeTask?.cancel()
        activeTask = nil
        currentItem = nil
        currentModel = nil
        guard let win = window else { return }
        window = nil
        win.delegate = nil
        win.orderOut(nil)
        win.contentView = nil
        win.close()
        ThumbnailImageCache.shared.clear()
    }

    func windowWillClose(_ notification: Notification) {
        activeTask?.cancel()
        activeTask = nil
        let win = window
        window = nil
        currentItem = nil
        currentModel = nil
        win?.contentView = nil
        win?.delegate = nil
        ThumbnailImageCache.shared.clear()
    }
}

final class HistoryPreviewWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 { // ESC
            HistoryPreviewWindowController.shared.close()
            return true
        }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "p" {
            if HistoryPreviewWindowController.shared.canPrintCurrentImage {
                HistoryPreviewWindowController.shared.printCurrentImage()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct ImageThumbnailView: View {
    let item: HistoryItem
    let model: AppModel
    let pixelSize: Int
    @State private var image: NSImage?

    private var cacheKey: String {
        "\(item.id)-\(pixelSize)"
    }

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").resizable().scaledToFit().foregroundStyle(.secondary).padding(28) }
        }
        .onAppear {
            if image == nil, let cached = ThumbnailImageCache.shared.image(forKey: cacheKey) {
                image = cached
            }
        }
        .task(id: cacheKey) {
            if let cached = ThumbnailImageCache.shared.image(forKey: cacheKey) {
                image = cached
                return
            }
            if let data = await model.thumbnail(for: item, maxPixelSize: pixelSize) {
                if let decoded = NSImage(data: data) {
                    let cost = Int(decoded.size.width * decoded.size.height * 4)
                    ThumbnailImageCache.shared.setImage(decoded, forKey: cacheKey, cost: cost)
                    image = decoded
                }
            }
        }
        .onDisappear {
            image = nil
        }
    }
}

struct FileThumbnailView: View {
    let file: FileReference
    @State private var image: NSImage?

    private var cacheKey: String {
        "file-thumb-\(file.url.path)"
    }

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "doc").resizable().scaledToFit().foregroundStyle(.secondary) }
        }
        .onAppear {
            if image == nil, let cached = ThumbnailImageCache.shared.image(forKey: cacheKey) {
                image = cached
            }
        }
        .task(id: file.url) {
            if let cached = ThumbnailImageCache.shared.image(forKey: cacheKey) {
                image = cached
                return
            }
            guard file.isAvailable else {
                image = NSImage(systemSymbolName: "doc.badge.questionmark", accessibilityDescription: "文件不存在")
                return
            }
            let request = QLThumbnailGenerator.Request(fileAt: file.url,
                                                       size: CGSize(width: 96, height: 96),
                                                       scale: 2,
                                                       representationTypes: .thumbnail)
            let result: NSImage? = await withCheckedContinuation { continuation in
                QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
                    continuation.resume(returning: thumbnail?.nsImage)
                }
            }
            let finalImage = result ?? NSWorkspace.shared.icon(forFile: file.url.path)
            ThumbnailImageCache.shared.setImage(finalImage, forKey: cacheKey, cost: 96 * 96 * 4)
            image = finalImage
        }
        .onDisappear {
            image = nil
        }
    }
}

@MainActor
final class AdvancedFilterWindowController: NSObject, NSWindowDelegate {
    static let shared = AdvancedFilterWindowController()
    private var window: AdvancedFilterWindow?

    func show(model: AppModel, palette: PaperPalette) {
        close()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let visible = screen.visibleFrame
        let targetWidth: CGFloat = 340
        let targetHeight: CGFloat = 430
        let originX = visible.midX - targetWidth / 2
        let originY = visible.midY - targetHeight / 2
        let frameRect = NSRect(x: originX, y: originY, width: targetWidth, height: targetHeight)

        let newWindow = AdvancedFilterWindow(
            contentRect: frameRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "PasteLoom · 高级筛选"
        newWindow.titleVisibility = .hidden
        newWindow.isMovableByWindowBackground = false
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating
        newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        newWindow.isExcludedFromWindowsMenu = true
        newWindow.backgroundColor = .clear
        newWindow.isOpaque = false
        newWindow.hasShadow = true
        newWindow.delegate = self
        newWindow.minSize = NSSize(width: targetWidth, height: targetHeight)
        newWindow.maxSize = NSSize(width: targetWidth, height: targetHeight)

        let filterView = AdvancedFilterModalView(model: model, palette: palette, onClose: { [weak self] in
            self?.close()
        })
        newWindow.contentView = NSHostingView(rootView: filterView)

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        guard let win = window else { return }
        window = nil
        win.delegate = nil
        win.orderOut(nil)
        win.contentView = nil
        win.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

final class AdvancedFilterWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 { // ESC
            AdvancedFilterWindowController.shared.close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private struct AdvancedFilterModalView: View {
    @ObservedObject var model: AppModel
    let palette: PaperPalette
    let onClose: () -> Void

    @State private var tagFilterInput: String = ""
    @AppStorage("historyTagMatchMode") private var storedTagMatchMode = TagMatchMode.any.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(palette.accent)
                Text("高级筛选")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(palette.secondaryText)
                }
                .buttonStyle(.plain)
                .help("关闭 (Esc)")
            }
            .padding(.bottom, 2)

            Divider()

            // Content Type Picker
            VStack(alignment: .leading, spacing: 5) {
                Text("内容类型")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
                Picker("", selection: Binding(
                    get: { model.searchScope.kind },
                    set: { model.searchScope.kind = $0 }
                )) {
                    Text("全部类型").tag(HistoryKind?.none)
                    Text("纯文本").tag(Optional(HistoryKind.text))
                    Text("富文本").tag(Optional(HistoryKind.richText))
                    Text("网页链接").tag(Optional(HistoryKind.url))
                    Text("图片").tag(Optional(HistoryKind.image))
                    Text("视频").tag(Optional(HistoryKind.video))
                    Text("文件").tag(Optional(HistoryKind.file))
                }
                .labelsHidden()
            }

            // Source App Field
            VStack(alignment: .leading, spacing: 5) {
                Text("来源应用名称")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
                TextField("例如: Xcode, Safari, 微信", text: Binding(
                    get: { model.searchScope.sourceName },
                    set: { model.searchScope.sourceName = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            // Tags Field
            VStack(alignment: .leading, spacing: 5) {
                Text("标签筛选")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
                TextField("输入标签，多个用逗号隔开", text: Binding(
                    get: { tagFilterInput },
                    set: { value in
                        tagFilterInput = value
                        let tags = value.split(separator: ",").map {
                            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        }.filter { !$0.isEmpty }
                        model.searchScope.tags = tags
                    }
                ))
                .textFieldStyle(.roundedBorder)

                Picker("匹配模式", selection: $storedTagMatchMode) {
                    Text("满足任一").tag(TagMatchMode.any.rawValue)
                    Text("满足全部").tag(TagMatchMode.all.rawValue)
                }
                .pickerStyle(.segmented)
                .onChange(of: storedTagMatchMode) { _, newValue in
                    if let mode = TagMatchMode(rawValue: newValue) {
                        model.searchScope.tagMatch = mode
                    }
                }
            }

            Divider()

            // Quick toggles
            VStack(alignment: .leading, spacing: 8) {
                Toggle("只看常用片段", isOn: Binding(
                    get: { model.searchScope.isSnippet == true },
                    set: { model.searchScope.isSnippet = $0 ? true : nil }
                ))
                .font(.system(size: 12))

                Toggle("只看最近 7 天", isOn: Binding(
                    get: { model.searchScope.since != nil },
                    set: { model.searchScope.since = $0 ? Date().addingTimeInterval(-7 * 24 * 3600) : nil }
                ))
                .font(.system(size: 12))
            }

            Spacer(minLength: 4)

            // Footer
            HStack {
                Button("重置筛选") {
                    tagFilterInput = ""
                    model.searchScope = .unrestricted
                    model.searchScope.tagMatch = TagMatchMode.load(from: .standard)
                }
                .disabled(!model.searchScope.hasFilters)

                Spacer()

                Button("完成") {
                    onClose()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 340, height: 430)
        .background(palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.cardBorder, lineWidth: 1)
        )
        .onAppear {
            tagFilterInput = model.searchScope.tags.joined(separator: ", ")
        }
    }
}

@MainActor
final class TagEditorWindowController: NSObject, NSWindowDelegate {
    static let shared = TagEditorWindowController()
    private var window: TagEditorWindow?
    private(set) var isOpen: Bool = false

    func show(item: HistoryItem, model: AppModel, palette: PaperPalette) {
        close()
        isOpen = true

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let visible = screen.visibleFrame
        let targetWidth: CGFloat = 380
        let targetHeight: CGFloat = 195
        let originX = visible.midX - targetWidth / 2
        let originY = visible.midY - targetHeight / 2
        let clampedX = max(visible.minX + 20, min(originX, visible.maxX - targetWidth - 20))
        let clampedY = max(visible.minY + 20, min(originY, visible.maxY - targetHeight - 20))
        let frameRect = NSRect(x: clampedX, y: clampedY, width: targetWidth, height: targetHeight)

        let newWindow = TagEditorWindow(
            contentRect: frameRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "PasteLoom · 编辑标签"
        newWindow.titleVisibility = .hidden
        newWindow.isMovableByWindowBackground = true
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating
        newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        newWindow.isExcludedFromWindowsMenu = true
        newWindow.backgroundColor = .clear
        newWindow.isOpaque = false
        newWindow.hasShadow = true
        newWindow.delegate = self
        newWindow.minSize = NSSize(width: targetWidth, height: targetHeight)
        newWindow.maxSize = NSSize(width: targetWidth, height: targetHeight)

        let tagView = TagEditorModalView(
            item: item,
            model: model,
            palette: palette,
            onClose: { [weak self] in
                self?.close()
            }
        )
        newWindow.contentView = NSHostingView(rootView: tagView)

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        guard let win = window else { return }
        window = nil
        isOpen = false
        win.delegate = nil
        win.orderOut(nil)
        win.contentView = nil
        win.close()
        NotificationCenter.default.post(name: NSNotification.Name("ModalSheetClosed"), object: nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        isOpen = false
        NotificationCenter.default.post(name: NSNotification.Name("ModalSheetClosed"), object: nil)
    }
}

final class TagEditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 { // ESC
            TagEditorWindowController.shared.close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private struct TagEditorModalView: View {
    let item: HistoryItem
    @ObservedObject var model: AppModel
    let palette: PaperPalette
    let onClose: () -> Void

    @State private var tagInput: String = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.accent)
                Text("编辑标签")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(palette.secondaryText)
                }
                .buttonStyle(.plain)
                .help("取消 (Esc)")
            }

            Text("用逗号分隔多个标签。搜索可以按标签命中。")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondaryText)

            TextField("例如: 工作, 灵感, 代码", text: $tagInput)
                .textFieldStyle(.roundedBorder)
                .focused($isFieldFocused)
                .onSubmit {
                    saveTags()
                }

            Spacer(minLength: 2)

            HStack {
                Spacer()
                Button("取消") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    saveTags()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380, height: 195)
        .background(palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.cardBorder, lineWidth: 1)
        )
        .onAppear {
            tagInput = item.tags.joined(separator: ", ")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFieldFocused = true
            }
        }
    }

    private func saveTags() {
        let tags = tagInput.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        model.setTags(tags, for: item)
        onClose()
    }
}

