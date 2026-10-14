import AppKit
import SwiftUI

struct QuickPasteView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("themePreset") private var themePreset = PaperTheme.macosNative.rawValue
    @AppStorage("accentColor") private var accentColor = PaperAccent.theme.rawValue
    @AppStorage("quickPasteLayout") private var quickPasteLayout = "list"
    @AppStorage("showQuickPasteKeyboardBanner") private var showKeyboardBanner = true
    @ObservedObject var model: QuickPasteViewModel
    let onConfirm: () -> Void
    let onCopyOnly: () -> Void
    let onOpenAccessibilitySettings: () -> Void
    var onDismiss: (() -> Void)? = nil

    @FocusState private var searchFocused: Bool

    private var effectiveColorScheme: ColorScheme {
        AppearanceManager.effectiveColorScheme(for: appearanceMode, environmentScheme: colorScheme)
    }

    private var palette: PaperPalette {
        let accent = PaperAccent(rawValue: accentColor)
        return (PaperTheme(rawValue: themePreset) ?? .macosNative)
            .palette(for: effectiveColorScheme, accentOverride: accent == .theme ? nil : accent)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Row: Icon + Title + Count Badge + Utility Buttons
            HStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.accent)

                Text("快速粘贴")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.primaryText)

                Text("\(model.results.count)")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(palette.accent.opacity(0.12), in: Capsule())

                Spacer()

                Button {
                    quickPasteLayout = (quickPasteLayout == "list" ? "grid" : "list")
                } label: {
                    Image(systemName: quickPasteLayout == "list" ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.cardBorder.opacity(0.6), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .help("切换视图排版")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showKeyboardBanner.toggle()
                    }
                } label: {
                    Image(systemName: "keyboard")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(showKeyboardBanner ? palette.accent : palette.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.cardBorder.opacity(0.6), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .help("显示/隐藏键盘提示")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // Keyboard Instructions Banner
            if showKeyboardBanner {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: "command")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(palette.accent)
                        Text("键盘操作")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(palette.primaryText)
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showKeyboardBanner = false
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(palette.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("↑↓ 移动 · 空格 选择 · ⌘C 复制 · ↵ 粘贴 · 按数字键 1–9 粘贴对应序号")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(palette.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.accent.opacity(0.18), lineWidth: 0.8))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondaryText)
                TextField("搜索...", text: Binding(
                    get: { model.query },
                    set: { model.updateQuery($0) }
                ))
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .font(.system(size: 13.5))
                .accessibilityIdentifier("quickPasteSearch")

                Text("⌘F")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(palette.secondaryText.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.cardBorder.opacity(0.8), lineWidth: 0.8))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            // Content Area / Cards List
            if model.results.isEmpty {
                ContentUnavailableView(model.query.isEmpty ? "暂无历史" : "没有匹配结果",
                                       systemImage: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        if quickPasteLayout == "grid" {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                                ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                                    QuickPasteTicketCard(
                                        item: item,
                                        index: index,
                                        model: model,
                                        palette: palette,
                                        isSelected: index == model.selectedIndex,
                                        isSelectedInMulti: model.isSelected(item)
                                    ) {
                                        if !model.selectedIDs.isEmpty {
                                            model.toggleSelection(for: item)
                                        } else {
                                            model.select(item)
                                            onConfirm()
                                        }
                                    }
                                    .id(item.id)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                        } else {
                            LazyVStack(spacing: 7) {
                                ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                                    QuickPasteTicketCard(
                                        item: item,
                                        index: index,
                                        model: model,
                                        palette: palette,
                                        isSelected: index == model.selectedIndex,
                                        isSelectedInMulti: model.isSelected(item)
                                    ) {
                                        if !model.selectedIDs.isEmpty {
                                            model.toggleSelection(for: item)
                                        } else {
                                            model.select(item)
                                            onConfirm()
                                        }
                                    }
                                    .id(item.id)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                        }
                    }
                    .onChange(of: model.keyboardNavigatedID) { _, targetID in
                        guard let targetID else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(targetID, anchor: .center)
                        }
                    }
                }
            }

            // Bottom Toolbar
            VStack(spacing: 4) {
                if let message = model.statusMessage {
                    Text(message).foregroundStyle(.orange).font(.caption).padding(.horizontal, 14)
                }

                HStack(alignment: .center) {
                    // Left: Keyboard shortcut hints
                    HStack(spacing: 5) {
                        Text("^↵ 菜单")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(palette.secondaryText)
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.secondaryText.opacity(0.5))
                        Text("↵ \(model.autoPasteEnabled ? "粘贴" : "复制")")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(palette.secondaryText)
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.secondaryText.opacity(0.5))
                        Text("⌘C 仅复制")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(palette.secondaryText)
                    }

                    Spacer()

                    // Right: Compact native buttons with horizontal alignment
                    HStack(spacing: 8) {
                        Button("取消") {
                            if let onDismiss {
                                onDismiss()
                            } else {
                                NSApp.keyWindow?.orderOut(nil)
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.primaryText)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.cardBorder.opacity(0.75), lineWidth: 0.8))
                        .shadow(color: Color.black.opacity(0.03), radius: 1, y: 0.5)

                        Button {
                            onConfirm()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.turn.down.left")
                                    .font(.system(size: 10, weight: .bold))
                                Text(confirmButtonTitle)
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 28)
                            .background(
                                model.itemsToPaste.isEmpty ? palette.accent.opacity(0.45) : palette.accent,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .shadow(color: palette.accent.opacity(0.2), radius: 2, y: 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.itemsToPaste.isEmpty)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
            .background(palette.sidebarBackground)
        }
        .frame(width: quickPasteLayout == "grid" ? 580 : 480, height: 580)
        .background(
            ZStack {
                VisualEffectBlur(material: palette.material, blendingMode: .behindWindow, alpha: palette.blurAlpha)
                palette.sidebarBackground.opacity(palette.backgroundOpacity)
            }
        )
        .foregroundStyle(palette.primaryText)
        .tint(palette.accent)
        .preferredColorScheme(appearanceMode == "light" ? .light : appearanceMode == "dark" ? .dark : (appearanceManager.isSystemDark ? .dark : .light))
        .onAppear { searchFocused = true }
        .id(model.presentationID)
    }

    private var confirmButtonTitle: String {
        let count = model.itemsToPaste.count
        if count > 1 {
            return model.autoPasteEnabled ? "粘贴 (\(count))" : "复制 (\(count))"
        }
        return model.autoPasteEnabled ? "粘贴" : "复制"
    }
}

private struct QuickPasteTicketCard: View {
    let item: HistoryItem
    let index: Int
    @ObservedObject var model: QuickPasteViewModel
    let palette: PaperPalette
    let isSelected: Bool
    let isSelectedInMulti: Bool
    let onSelect: () -> Void

    @AppStorage("quickPasteLayout") private var quickPasteLayout = "list"
    @State private var imageMetadata: ImageAssetInfo?
    @State private var hovered = false
    @State private var isCardHovered = false
    @State private var isPopoverHovered = false
    @State private var showsHoverPreview = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var dismissTask: Task<Void, Never>?
    @State private var lastClickTime: Date = .distantPast

    private var isHighlighted: Bool {
        hovered || isSelected
    }

    private var badgeNumberText: String {
        "\(index + 1)"
    }

    private var kindIcon: String {
        switch item.kind {
        case .text: "doc.text"
        case .richText: "text.quote"
        case .image: "photo"
        case .video: "video.fill"
        case .url: "link"
        case .file: "folder"
        }
    }

    private var kindTitle: String {
        switch item.kind {
        case .text: "文本"
        case .richText: "富文本"
        case .image: "图片"
        case .video: "视频"
        case .url: "链接"
        case .file: "文件"
        }
    }

    private var cardTitle: String {
        switch item.kind {
        case .image:
            if let meta = imageMetadata {
                let sizeStr = ByteCountFormatter.string(fromByteCount: meta.byteCount, countStyle: .file)
                return "[图片 \(sizeStr)]"
            }
            return "[图片]"
        case .video:
            return item.files.first?.name ?? "[视频]"
        case .text, .richText:
            return item.text.replacingOccurrences(of: "\n", with: " ")
        case .url:
            return URLComponents(string: item.text)?.host ?? item.text
        case .file:
            return item.files.first?.name ?? "\(item.files.count) 个文件"
        }
    }

    private var detailString: String {
        switch item.kind {
        case .image:
            if let meta = imageMetadata {
                return "\(meta.pixelWidth)×\(meta.pixelHeight)"
            }
            return ""
        case .video:
            return item.files.first?.name ?? ""
        case .text, .richText:
            return "\(item.text.count) 字"
        case .url:
            return URLComponents(string: item.text)?.host ?? "网页"
        case .file:
            return "\(item.files.count) 个文件"
        }
    }

    private func formatShortDate(_ date: Date) -> String {
        let cal = Calendar.current
        let df = DateFormatter()
        if cal.isDateInToday(date) {
            df.dateFormat = "今天 HH:mm"
        } else if cal.isDateInYesterday(date) {
            df.dateFormat = "昨天 HH:mm"
        } else {
            df.dateFormat = "MM/dd HH:mm"
        }
        return df.string(from: date)
    }

    var body: some View {
        ZStack {
            // Stable hit-test anchor layer to prevent hover edge oscillation on rightward slide:
            Color.clear
                .padding(.leading, -7)
                .contentShape(Rectangle())

            // Ticket Card Body
            ZStack {
                // Background fill
                RoundedRectangle(cornerRadius: 10)
                    .fill(palette.cardBackground)

                // Outer border
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isHighlighted ? palette.accent : palette.cardBorder.opacity(0.7),
                            lineWidth: isHighlighted ? 1.5 : 0.8)

                // Ticket Content Stack
                HStack(spacing: 0) {
                    // Left Section: Thumbnail + Main Info
                    HStack(spacing: 10) {
                        // Thumbnail Box (38x38)
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(palette.secondaryText.opacity(0.07))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.cardBorder.opacity(0.4), lineWidth: 0.6))

                            switch item.kind {
                            case .text, .richText:
                                Image(systemName: "doc.text")
                                    .font(.system(size: 16))
                                    .foregroundStyle(palette.secondaryText)
                            case .url:
                                Image(systemName: "link")
                                    .font(.system(size: 15))
                                    .foregroundStyle(palette.accent)
                            case .image:
                                QuickPasteImage(item: item, model: model)
                                    .adaptiveCardMediaFrame(cornerRadius: 5, shadowRadius: 2, shadowY: 1)
                                    .frame(width: 34, height: 34)
                            case .video:
                                ZStack {
                                    QuickPasteImage(item: item, model: model)
                                        .adaptiveCardMediaFrame(cornerRadius: 5, shadowRadius: 2, shadowY: 1)
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.92))
                                }
                                .frame(width: 34, height: 34)
                            case .file:
                                Image(nsImage: NSWorkspace.shared.icon(forFile: item.files.first?.url.path ?? ""))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 26, height: 26)
                            }
                        }
                        .frame(width: 38, height: 38)

                        // Title & Metadata
                        VStack(alignment: .leading, spacing: 3.5) {
                            // Line 1: Pushpin (if pinned) + Title
                            HStack(spacing: 4) {
                                if item.isPinned {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(palette.accent)
                                }

                                Text(cardTitle)
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundStyle(palette.primaryText)
                                    .lineLimit(1)
                            }

                            // Line 2: Stamp Badge + Source App + Detail
                            HStack(spacing: 5) {
                                // Stamp / Notched Tag
                                HStack(spacing: 3) {
                                    Image(systemName: kindIcon)
                                        .font(.system(size: 8.5))
                                    Text(kindTitle)
                                        .font(.system(size: 9.5, weight: .medium))
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(palette.secondaryText.opacity(0.08), in: RoundedRectangle(cornerRadius: 3.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3.5)
                                        .stroke(palette.cardBorder.opacity(0.6), style: StrokeStyle(lineWidth: 0.8, dash: [3, 2]))
                                )
                                .foregroundStyle(palette.secondaryText)

                                Text(item.sourceName ?? "剪贴板")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(palette.secondaryText)
                                    .lineLimit(1)

                                if !detailString.isEmpty {
                                    Text("·")
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(palette.secondaryText)

                                    Text(detailString)
                                        .font(.system(size: 10))
                                        .foregroundStyle(palette.secondaryText)
                                        .lineLimit(1)
                                }
                            }
                        }

                        Spacer(minLength: 4)
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 6)

                    // Vertical Perforation Divider
                    QuickPastePerforationDivider(
                        palette: palette,
                        notchDiameter: 8,
                        strokeColor: isHighlighted ? palette.accent : palette.cardBorder.opacity(0.7)
                    )
                    .frame(height: 66)

                    // Right Stub: Number Badge + Timestamp + Type
                    VStack(spacing: 3) {
                        Circle()
                            .fill(isHighlighted ? palette.accent.opacity(0.14) : palette.secondaryText.opacity(0.08))
                            .frame(width: 19, height: 19)
                            .overlay {
                                Text(badgeNumberText)
                                    .font(.system(size: 10, weight: isHighlighted ? .medium : .regular))
                                    .foregroundStyle(isHighlighted ? palette.accent : palette.secondaryText.opacity(0.85))
                            }

                        Text(formatShortDate(item.capturedAt))
                            .font(.system(size: 9.5))
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)

                        Text(kindTitle)
                            .font(.system(size: 9))
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(width: 68)
                    .padding(.horizontal, 2)
                }
            }
            .frame(height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: isHighlighted ? palette.accent.opacity(0.32) : palette.shadow.opacity(0.12),
                    radius: isHighlighted ? 7 : 2.5,
                    x: (quickPasteLayout == "list" && isHighlighted) ? 2.5 : 0,
                    y: 1.5)
            .overlay(alignment: .topTrailing) {
                if isSelectedInMulti {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.accent)
                        .padding(4)
                }
            }
            .offset(x: (quickPasteLayout == "list" && isHighlighted) ? 5 : 0,
                    y: (quickPasteLayout == "grid" && isHighlighted) ? -4 : 0)
            .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isHighlighted)
            .popover(isPresented: $showsHoverPreview, attachmentAnchor: .point(.trailing), arrowEdge: .trailing) {
                QuickPasteHoverPreviewView(
                    item: item,
                    model: model,
                    palette: palette,
                    onHoverChanged: { isOver in
                        isPopoverHovered = isOver
                        if isOver {
                            dismissTask?.cancel()
                        } else {
                            scheduleDismiss()
                        }
                    }
                )
                .frame(width: 330)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(4)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            let now = Date()
            guard now.timeIntervalSince(lastClickTime) > 0.35 else { return }
            lastClickTime = now
            showsHoverPreview = false
            onSelect()
        }
        .onHover { isOver in
            hovered = isOver
            isCardHovered = isOver
            if isOver {
                model.selectIndex(index)
                dismissTask?.cancel()
                hoverTask?.cancel()
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled, isCardHovered else { return }
                    showsHoverPreview = true
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
        }
        .task(id: item.imageRelativePath) {
            imageMetadata = await model.imageMetadata(for: item)
        }
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            if NSEvent.pressedMouseButtons != 0 {
                // Keep open while user is dragging / selecting text
                scheduleDismiss()
                return
            }
            if !isCardHovered && !isPopoverHovered {
                showsHoverPreview = false
            }
        }
    }
}

private struct QuickPastePerforationDivider: View {
    let palette: PaperPalette
    var notchDiameter: CGFloat = 8
    var strokeColor: Color? = nil

    var body: some View {
        ZStack {
            DashedVerticalLine()
                .stroke(palette.cardBorder.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: 1)
        }
        .frame(width: notchDiameter)
    }
}

private struct QuickPasteHoverPreviewView: View {
    let item: HistoryItem
    @ObservedObject var model: QuickPasteViewModel
    let palette: PaperPalette
    var onHoverChanged: ((Bool) -> Void)? = nil
    @State private var sourceIcon: NSImage?
    @State private var previewImage: NSImage?
    @State private var imageMetadata: ImageAssetInfo?

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

    private func formatFullDate(_ date: Date) -> String {
        let df = DateFormatter()
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            df.dateFormat = "今天 HH:mm:ss"
        } else if cal.isDateInYesterday(date) {
            df.dateFormat = "昨天 HH:mm:ss"
        } else {
            df.dateFormat = "yyyy-MM-dd HH:mm"
        }
        return df.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Source app icon + source app name + timestamp + kind badge
            HStack(spacing: 8) {
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

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(item.sourceName ?? "未知应用")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)

                    Text(formatFullDate(item.capturedAt))
                        .font(.system(size: 9.5))
                        .foregroundStyle(palette.secondaryText)
                }

                Spacer()

                Text(kindBadgeTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(palette.accent.opacity(0.12), in: Capsule())
            }

            Divider()

            // Main Content Area
            switch item.kind {
            case .text, .richText:
                let displayText = SensitiveContentService.shared.isMaskingEnabled ? SensitiveContentService.shared.mask(item.text) : item.text
                ScrollView {
                    Text(displayText)
                        .font(.system(size: 12))
                        .lineSpacing(3)
                        .foregroundStyle(palette.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.vertical, 2)
                }
                .frame(maxHeight: 220)

                HStack {
                    Text("\(item.text.count) 字 · \(item.text.components(separatedBy: .newlines).count) 行")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                }

            case .url:
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(palette.accent)

                        Text(URLComponents(string: item.text)?.host ?? "网页链接")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.primaryText)
                            .lineLimit(1)
                        Spacer()
                    }

                    Text(item.text)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .lineLimit(5)
                }
                .padding(.vertical, 4)

            case .image:
                VStack(spacing: 8) {
                    if let img = previewImage {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .adaptiveCardMediaFrame(cornerRadius: 6, shadowRadius: 5, shadowY: 2.5)
                            .frame(maxWidth: .infinity, maxHeight: 200)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(palette.secondaryText.opacity(0.08))
                            .frame(height: 140)
                            .overlay(ProgressView())
                    }

                    if let meta = imageMetadata {
                        HStack {
                            Text("\(meta.pixelWidth) × \(meta.pixelHeight) 像素")
                                .font(.system(size: 10))
                                .foregroundStyle(palette.secondaryText)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: meta.byteCount, countStyle: .file))
                                .font(.system(size: 10))
                                .foregroundStyle(palette.secondaryText)
                        }
                    }

                    if let ocr = item.ocrText, !ocr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let formatted = OCRTextFormatter.format(ocr)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 4) {
                                Image(systemName: "text.viewfinder")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(palette.accent)
                                Text("识别文字")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(palette.secondaryText)
                                Spacer()
                            }
                            Text(formatted)
                                .font(.system(size: 11))
                                .lineSpacing(4.0)
                                .foregroundStyle(palette.primaryText)
                                .textSelection(.enabled)
                                .lineLimit(8)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(palette.cardBorder.opacity(0.4), lineWidth: 0.5)
                        )
                    }
                }

            case .video:
                VStack(spacing: 8) {
                    ZStack {
                        if let img = previewImage {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.black.opacity(0.1))
                                .frame(height: 120)
                        }
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.95))
                            .shadow(radius: 3)
                    }

                    Text(item.files.first?.name ?? "视频文件")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                }

            case .file:
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item.files.prefix(5), id: \.url) { file in
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.name)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(palette.primaryText)
                                    .lineLimit(1)
                                Text(file.fileExtension.uppercased())
                                    .font(.system(size: 9))
                                    .foregroundStyle(palette.secondaryText)
                            }
                            Spacer()
                        }
                    }
                    if item.files.count > 5 {
                        Text("等共 \(item.files.count) 个文件")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            // Footer prompt & actions
            HStack {
                Text("↵ 直接粘贴 · ⌘C 仅复制")
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.secondaryText.opacity(0.8))
                Spacer()
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(item.text, forType: .string)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                        Text("复制")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
                .help("复制内容到剪贴板")
            }
        }
        .padding(12)
        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.cardBorder.opacity(0.85), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { isOver in
            onHoverChanged?(isOver)
        }
        .task(id: item.sourceBundleIdentifier) {
            guard let bundleID = item.sourceBundleIdentifier,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            sourceIcon = NSWorkspace.shared.icon(forFile: url.path)
        }
        .task(id: item.id) {
            if item.kind == .image || item.kind == .video {
                if let data = await model.thumbnail(for: item, maxPixelSize: 800) {
                    previewImage = NSImage(data: data)
                }
                imageMetadata = await model.imageMetadata(for: item)
            }
        }
    }
}

private struct QuickPasteImage: View {
    let item: HistoryItem
    @ObservedObject var model: QuickPasteViewModel
    @State private var image: NSImage?

    private var cacheKey: String {
        "qp-\(item.id)-100"
    }

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").resizable().scaledToFit() }
        }
        .onAppear {
            if image == nil, let cached = ThumbnailImageCache.shared.image(forKey: cacheKey) {
                image = cached
            }
        }
        .task(id: item.id) {
            if let cached = ThumbnailImageCache.shared.image(forKey: cacheKey) {
                image = cached
                return
            }
            if let data = await model.thumbnail(for: item, maxPixelSize: 100) {
                if let decoded = NSImage(data: data) {
                    ThumbnailImageCache.shared.setImage(decoded, forKey: cacheKey, cost: 100 * 100 * 4)
                    image = decoded
                }
            }
        }
        .onDisappear {
            image = nil
        }
    }
}
