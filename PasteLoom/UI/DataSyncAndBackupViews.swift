import SwiftUI
import AppKit

// MARK: - Sync Settings Page View
struct SyncSettingsView: View {
    @ObservedObject var syncService = SyncService.shared
    let repository: any HistoryRepository
    let palette: PaperPalette

    @State private var isSyncing = false
    @State private var syncNotice: String?

    var body: some View {
        VStack(spacing: 22) {
            // MARK: - Target Selector
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("同步方式与适配器")
                sectionCard {
                    settingRow("同步模式", detail: syncService.mode.displayName, icon: "arrow.triangle.2.circlepath") {
                        Picker("", selection: $syncService.mode) {
                            ForEach(SyncMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }

                    if syncService.mode != .none {
                        rowDivider
                        settingRow("自动后台同步", detail: "在数据变动时自动增量同步", icon: "clock.arrow.2.circlepath") {
                            Toggle("", isOn: $syncService.autoSyncEnabled).labelsHidden()
                        }
                    }
                }
            }

            // MARK: - Specific Configuration
            if syncService.mode != .none {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("目标配置与连接凭证")
                    sectionCard {
                        switch syncService.mode {
                        case .localFolder:
                            settingRow("本地同步目录", detail: syncService.localFolderPath.isEmpty ? "未选择目录" : syncService.localFolderPath, icon: "folder") {
                                Button("选择目录...") {
                                    chooseFolder()
                                }
                                .buttonStyle(.bordered)
                            }

                        case .iCloud:
                            settingRow("iCloud 云盘状态", detail: "使用 iCloud Drive/PasteLoom 专用同步目录", icon: "icloud") {
                                Text("已就绪").font(.caption.weight(.medium)).foregroundStyle(.green)
                            }

                        case .webDAV:
                            VStack(spacing: 0) {
                                settingRow("服务端 URL", detail: "WebDAV 端点地址", icon: "network") {
                                    TextField("https://example.com/dav/", text: $syncService.webDAVURL)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 220)
                                }
                                rowDivider
                                settingRow("用户名", detail: "认证用户名", icon: "person") {
                                    TextField("用户名", text: $syncService.webDAVUser)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 220)
                                }
                            }

                        case .s3:
                            VStack(spacing: 0) {
                                settingRow("S3 端点 URL", detail: "S3 兼容对象存储端点", icon: "server.rack") {
                                    TextField("https://s3.example.com", text: $syncService.s3Endpoint)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 220)
                                }
                                rowDivider
                                settingRow("存储桶名称", detail: "Bucket 名称", icon: "cylinder") {
                                    TextField("bucket-name", text: $syncService.s3Bucket)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 220)
                                }
                            }

                        case .none:
                            EmptyView()
                        }
                    }
                }

                // MARK: - Status & Trigger
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("同步状态与操作")
                    sectionCard {
                        settingRow("当前同步状态", detail: syncService.status.description, icon: "chart.bar.doc.horizontal") {
                            Button {
                                performSyncNow()
                            } label: {
                                if isSyncing {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("立即同步")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSyncing)
                        }
                    }
                }
            }

            if let notice = syncNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(palette.accent)
                    .padding(.top, 4)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            syncService.localFolderPath = url.path
        }
    }

    private func performSyncNow() {
        isSyncing = true
        Task {
            await syncService.syncNow(repository: repository)
            isSyncing = false
            syncNotice = "同步操作已完成"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { syncNotice = nil }
        }
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
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(palette.accent)
                .frame(width: 36, height: 36)
                .background(palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(palette.secondaryText)
            }
            Spacer(minLength: 12)
            control()
        }
        .frame(minHeight: palette.rowHeight)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private var rowDivider: some View {
        Rectangle().fill(palette.divider).frame(height: 1).padding(.leading, 68)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(palette.secondaryText)
    }
}

// MARK: - Import & Export Settings Page View
struct ImportExportSettingsView: View {
    let repository: any HistoryRepository
    let palette: PaperPalette

    @State private var maskSensitiveExport = true
    @State private var snippetsOnlyExport = false
    @State private var actionMessage: String?
    @State private var isProcessing = false

    var body: some View {
        VStack(spacing: 22) {
            // MARK: - SQLite Full Backup
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("SQLite 原生物理备份")
                sectionCard {
                    settingRow("创建 SQLite 数据库备份", detail: "通过 SQLite 在线备份 API 生成完整无损的 .sqlite3 物理文件", icon: "cylinder.split.1x2") {
                        Button("导出备份文件...") {
                            exportSQLiteBackup()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isProcessing)
                    }
                }
            }

            // MARK: - JSON Export
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("JSON 全量通用导出")
                sectionCard {
                    settingRow("脱敏导出敏感信息", detail: "自动对手机、邮箱、身份证、银行卡及密钥打码遮蔽", icon: "shield") {
                        Toggle("", isOn: $maskSensitiveExport).labelsHidden()
                    }
                    rowDivider
                    settingRow("仅导出常用片段", detail: "仅导出已标记为常用片段 (Snippets) 的内容", icon: "bookmark") {
                        Toggle("", isOn: $snippetsOnlyExport).labelsHidden()
                    }
                    rowDivider
                    settingRow("导出 JSON 数据包", detail: "导出为可跨平台阅读的标准化 JSON 数据文件", icon: "arrow.up.doc") {
                        Button("导出 JSON...") {
                            exportJSON()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isProcessing)
                    }
                }
            }

            // MARK: - Data Import
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("数据导入与恢复")
                sectionCard {
                    settingRow("从 JSON 备份导入", detail: "读取备份文件并将条目安全合并至当前数据库", icon: "arrow.down.doc") {
                        Button("选择文件并导入...") {
                            importJSON()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isProcessing)
                    }
                }
            }

            // MARK: - macOS Widget
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("macOS 通知中心小组件 (Widget)")
                sectionCard {
                    settingRow("小组件数据共享", detail: "刷新共享数据 (widget_data.json) 供系统小组件显示常用片段", icon: "square.grid.2x2") {
                        Button("刷新小组件数据") {
                            refreshWidget()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isProcessing)
                    }
                }
            }

            if let message = actionMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(message).font(.subheadline)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.cardBorder))
            }
        }
    }

    private func exportSQLiteBackup() {
        guard let dbURL = try? SQLiteHistoryRepository.defaultURL() else {
            actionMessage = "未找到主数据库文件路径"
            return
        }

        let panel = NSSavePanel()
        panel.title = "保存 SQLite 备份"
        panel.nameFieldStringValue = "PasteLoom_Backup_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).sqlite3"
        panel.prompt = "保存"

        if panel.runModal() == .OK, let targetURL = panel.url {
            isProcessing = true
            do {
                let result = try BackupService.shared.createSQLiteBackup(sourceDatabaseURL: dbURL, destinationURL: targetURL)
                actionMessage = result.message
            } catch {
                actionMessage = "备份失败: \(error.localizedDescription)"
            }
            isProcessing = false
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.title = "保存 JSON 导出文件"
        panel.nameFieldStringValue = "PasteLoom_Export_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).json"
        panel.prompt = "导出"

        if panel.runModal() == .OK, let targetURL = panel.url {
            isProcessing = true
            Task {
                var opts = ExportOptions()
                opts.maskSensitive = maskSensitiveExport
                opts.includeSnippetsOnly = snippetsOnlyExport
                do {
                    let result = try await BackupService.shared.exportToJSON(repository: repository, destinationURL: targetURL, options: opts)
                    actionMessage = result.message
                } catch {
                    actionMessage = "导出失败: \(error.localizedDescription)"
                }
                isProcessing = false
            }
        }
    }

    private func importJSON() {
        let panel = NSOpenPanel()
        panel.title = "选择要导入的 JSON 备份文件"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.prompt = "导入"

        if panel.runModal() == .OK, let sourceURL = panel.url {
            isProcessing = true
            Task {
                do {
                    let result = try await BackupService.shared.importFromJSON(sourceURL: sourceURL, repository: repository)
                    actionMessage = result.message
                } catch {
                    actionMessage = "导入失败: \(error.localizedDescription)"
                }
                isProcessing = false
            }
        }
    }

    private func refreshWidget() {
        isProcessing = true
        Task {
            do {
                try await WidgetDataSharingService.shared.exportForWidget(repository: repository)
                actionMessage = "小组件共享数据已更新"
            } catch {
                actionMessage = "小组件数据更新失败: \(error.localizedDescription)"
            }
            isProcessing = false
        }
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
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(palette.accent)
                .frame(width: 36, height: 36)
                .background(palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(palette.secondaryText)
            }
            Spacer(minLength: 12)
            control()
        }
        .frame(minHeight: palette.rowHeight)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private var rowDivider: some View {
        Rectangle().fill(palette.divider).frame(height: 1).padding(.leading, 68)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(palette.secondaryText)
    }
}
