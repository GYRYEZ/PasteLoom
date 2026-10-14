import SwiftUI

struct StatisticsDashboardView: View {
    @ObservedObject var model: AppModel
    let palette: PaperPalette

    @State private var statistics: HistoryStatistics?
    @State private var isLoading = false
    @State private var showResetConfirmation = false
    @State private var hoveredImageID: UUID? = nil
    @State private var hoveredRowID: UUID? = nil
    @State private var copiedNoticeItemID: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("复制与使用统计").font(.headline.weight(.bold))
                    Text("本地统计剪贴板内容的复用频次与类型分布")
                        .font(.caption).foregroundStyle(palette.secondaryText)
                }
                Spacer()
                Button { loadStats() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("刷新统计数据")

                Button { showResetConfirmation = true } label: {
                    Text("重置计数")
                }
                .buttonStyle(.bordered)
                .confirmationDialog("确定要重置所有条目的复制计数吗？", isPresented: $showResetConfirmation, titleVisibility: .visible) {
                    Button("确认重置", role: .destructive) {
                        Task {
                            await model.resetStatistics()
                            loadStats()
                        }
                    }
                    Button("取消", role: .cancel) {}
                }
            }

            if let stats = statistics {
                HStack(spacing: 14) {
                    statTile(title: "总历史条目", value: "\(stats.totalItems)", icon: "tray.full.fill", color: palette.accent)
                    statTile(title: "总复用复制", value: "\(stats.totalCopies)", icon: "doc.on.doc.fill", color: .green)
                    statTile(title: "常用片段", value: "\(stats.snippetCount)", icon: "bookmark.fill", color: .orange)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("内容类型分布").font(.subheadline.weight(.semibold))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        typeMetric("纯文本", count: stats.textCount, icon: "text.alignleft")
                        typeMetric("富文本", count: stats.richTextCount, icon: "text.quote")
                        typeMetric("网页链接", count: stats.urlCount, icon: "link")
                        typeMetric("图片", count: stats.imageCount, icon: "photo")
                        typeMetric("视频", count: stats.videoCount, icon: "video.fill")
                        typeMetric("文件引用", count: stats.fileCount, icon: "folder")
                    }
                }
                .padding(14)
                .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.cardBorder))

                if !stats.topCopied.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("最常复用条目 Top 5").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("鼠标移动至图片可预览 · 点击可打开大图")
                                .font(.caption2)
                                .foregroundStyle(palette.secondaryText)
                        }
                        ForEach(Array(stats.topCopied.enumerated()), id: \.element.id) { index, item in
                            let isHovered = hoveredRowID == item.id
                            let isImage = (item.kind == .image)
                            HStack(spacing: 10) {
                                Text("#\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(index == 0 ? palette.accent : palette.secondaryText)
                                    .frame(width: 24)
                                Image(systemName: iconFor(item.kind))
                                    .font(.caption)
                                    .foregroundStyle(palette.accent)

                                if isImage {
                                    HStack(spacing: 6) {
                                        Text("(图片)")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(palette.primaryText)

                                        if let ocr = item.ocrText, !ocr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            Text(ocr.prefix(35))
                                                .font(.caption)
                                                .foregroundStyle(palette.secondaryText)
                                                .lineLimit(1)
                                        }
                                    }
                                } else {
                                    Text(item.text.isEmpty ? "(空条目)" : item.text.prefix(45))
                                        .font(.caption)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if copiedNoticeItemID == item.id {
                                    Text("已复制")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(palette.success.opacity(0.15), in: Capsule())
                                        .foregroundStyle(palette.success)
                                }

                                if isImage {
                                    Button {
                                        HistoryPreviewWindowController.shared.show(item: item, model: model, palette: palette)
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "eye.fill")
                                                .font(.system(size: 9))
                                            Text("预览")
                                                .font(.caption2.weight(.semibold))
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(palette.accent.opacity(0.12), in: Capsule())
                                        .foregroundStyle(palette.accent)
                                    }
                                    .buttonStyle(.plain)
                                    .help("点击打开高清大图预览与 OCR 检视")
                                }

                                Text("\(item.copyCount) 次")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(palette.accent.opacity(0.12), in: Capsule())
                                    .foregroundStyle(palette.accent)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isHovered ? palette.accent.opacity(0.08) : Color.clear)
                            )
                            .contentShape(Rectangle())
                            .onHover { over in
                                if over {
                                    hoveredRowID = item.id
                                    if isImage {
                                        hoveredImageID = item.id
                                    }
                                } else {
                                    if hoveredRowID == item.id { hoveredRowID = nil }
                                    if hoveredImageID == item.id { hoveredImageID = nil }
                                }
                            }
                            .onTapGesture {
                                if isImage {
                                    HistoryPreviewWindowController.shared.show(item: item, model: model, palette: palette)
                                } else if !item.text.isEmpty {
                                    let pb = NSPasteboard.general
                                    pb.clearContents()
                                    pb.setString(item.text, forType: .string)
                                    copiedNoticeItemID = item.id
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        if copiedNoticeItemID == item.id { copiedNoticeItemID = nil }
                                    }
                                }
                            }
                            .popover(isPresented: Binding(
                                get: { hoveredImageID == item.id },
                                set: { if !$0 && hoveredImageID == item.id { hoveredImageID = nil } }
                            ), arrowEdge: .top) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "photo")
                                            .font(.caption)
                                            .foregroundStyle(palette.accent)
                                        Text("图片预览 (第 \(index + 1) 名 · 复用 \(item.copyCount) 次)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(palette.primaryText)
                                        Spacer()
                                        Text("点击查看大图")
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(palette.secondaryText)
                                    }

                                    ImageThumbnailView(item: item, model: model, pixelSize: 450)
                                        .scaledToFit()
                                        .frame(maxWidth: 240, maxHeight: 180)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.cardBorder.opacity(0.8), lineWidth: 0.8))
                                        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)

                                    if let ocr = item.ocrText, !ocr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("识别文字:")
                                                .font(.system(size: 9.5, weight: .semibold))
                                                .foregroundStyle(palette.secondaryText)
                                            Text(ocr.prefix(120))
                                                .font(.system(size: 10))
                                                .foregroundStyle(palette.primaryText)
                                                .lineLimit(3)
                                        }
                                    }
                                }
                                .padding(10)
                                .frame(width: 255)
                                .background(palette.cardBackground)
                                .onTapGesture {
                                    hoveredImageID = nil
                                    HistoryPreviewWindowController.shared.show(item: item, model: model, palette: palette)
                                }
                            }

                            if index < stats.topCopied.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(14)
                    .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.cardBorder))
                }
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Text("暂无统计数据").font(.subheadline).foregroundStyle(palette.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
        }
        .onAppear { loadStats() }
    }

    private func loadStats() {
        isLoading = true
        Task {
            let stats = await model.fetchStatistics()
            await MainActor.run {
                self.statistics = stats
                self.isLoading = false
            }
        }
    }

    private func statTile(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title3.weight(.bold))
                Text(title).font(.caption).foregroundStyle(palette.secondaryText)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.cardBorder))
    }

    private func typeMetric(_ name: String, count: Int, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(palette.accent)
            Text(name).font(.caption).foregroundStyle(palette.secondaryText)
            Spacer()
            Text("\(count)").font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(palette.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }

    private func iconFor(_ kind: HistoryKind) -> String {
        switch kind {
        case .text: return "text.alignleft"
        case .richText: return "text.quote"
        case .url: return "link"
        case .image: return "photo"
        case .video: return "video.fill"
        case .file: return "folder"
        }
    }
}
