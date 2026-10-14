import SwiftUI

struct MCPServerConfigView: View {
    @ObservedObject var mcp = MCPServer.shared
    let palette: PaperPalette
    @State private var copyNotice: String?

    var body: some View {
        VStack(spacing: 20) {
            // MARK: - Server Status Card
            sectionCard {
                settingRow("MCP 本地服务状态", detail: mcp.isRunning ? "服务正在监听 127.0.0.1:\(mcp.port)" : "服务已停止", icon: "globe") {
                    HStack(spacing: 12) {
                        if mcp.isRunning {
                            HStack(spacing: 6) {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                                Text("运行中").font(.caption.weight(.medium)).foregroundStyle(.green)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Circle().fill(palette.secondaryText).frame(width: 8, height: 8)
                                Text("已停止").font(.caption.weight(.medium)).foregroundStyle(palette.secondaryText)
                            }
                        }
                        Toggle("", isOn: $mcp.isEnabled).labelsHidden()
                    }
                }
                rowDivider

                settingRow("监听端口", detail: "默认端口 28833 (只绑定本地回环 127.0.0.1)", icon: "network") {
                    HStack(spacing: 6) {
                        TextField("端口", value: $mcp.port, format: .number)
                            .frame(width: 70)
                            .textFieldStyle(.roundedBorder)
                        if mcp.isRunning {
                            Button("重启") {
                                mcp.restart()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                rowDivider

                settingRow("请求统计与审计", detail: "已接收请求: \(mcp.requestCount) 次" + (mcp.lastRequestTime != nil ? " | 最近请求: \(mcp.lastRequestTime!.formatted(date: .omitted, time: .standard))" : ""), icon: "chart.bar.doc.horizontal") {
                    EmptyView()
                }
            }

            // MARK: - Privacy & Security
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("隐私与安全保护")
                sectionCard {
                    settingRow("允许向 AI 外发敏感原文", detail: "关闭时自动对输出结果中的手机号、邮箱、身份证及 API 密钥进行脱敏打码", icon: "shield.lefthalf.filled") {
                        Toggle("", isOn: $mcp.allowSensitiveExport).labelsHidden()
                    }
                }
            }

            // MARK: - Local Test Command
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("本地连通性测试")
                sectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("可在终端运行以下 curl 命令测试本地 MCP JSON-RPC 握手：")
                            .font(.caption).foregroundStyle(palette.secondaryText)

                        let curlTest = """
                        curl -s -X POST http://127.0.0.1:\(mcp.port)/mcp \\
                          -H "Content-Type: application/json" \\
                          -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
                        """

                        Text(curlTest)
                            .font(.system(.caption, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.background, in: RoundedRectangle(cornerRadius: 8))

                        HStack {
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(curlTest, forType: .string)
                                copyNotice = "已复制 curl 命令"
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copyNotice = nil }
                            } label: {
                                Label(copyNotice ?? "复制测试命令", systemImage: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(16)
                }
            }
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

// MARK: - AI Clients Configuration View
// MARK: - AI Clients Configuration View
struct InstalledAIClient: Identifiable {
    let id: String
    let name: String
    let iconSymbol: String
    let bundleId: String?
    let fallbackPaths: [String]
    let configPath: String?
    let description: String

    var appURL: URL? {
        if let bundleId, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return url
        }
        for path in fallbackPaths {
            let expanded = (path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }
        return nil
    }

    var isInstalled: Bool {
        appURL != nil
    }

    var isRunning: Bool {
        if let bundleId {
            return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
        }
        return false
    }
}

struct AIClientsConfigView: View {
    @ObservedObject var mcp = MCPServer.shared
    let palette: PaperPalette
    @State private var copyNotice: String?
    @State private var actionMessage: String?
    @State private var showManualConfig = false

    private let supportedClients: [InstalledAIClient] = [
        InstalledAIClient(
            id: "claude",
            name: "Claude Desktop",
            iconSymbol: "brain.head.profile",
            bundleId: "com.anthropic.claudefordesktop",
            fallbackPaths: ["/Applications/Claude.app"],
            configPath: "~/Library/Application Support/Claude/claude_desktop_config.json",
            description: "Anthropic 官方桌面客户端，原生支持本地 MCP 工具扩展"
        ),
        InstalledAIClient(
            id: "cursor",
            name: "Cursor AI",
            iconSymbol: "chevron.left.forwardslash.chevron.right",
            bundleId: "com.todesktop.230313mzl4w4u92",
            fallbackPaths: ["/Applications/Cursor.app"],
            configPath: "~/.cursor/mcp.json",
            description: "新一代 AI 智能代码编辑器，支持 MCP 协议无缝联动"
        ),
        InstalledAIClient(
            id: "chatgpt",
            name: "ChatGPT Desktop",
            iconSymbol: "bubble.left.and.bubble.right.fill",
            bundleId: "com.openai.chat",
            fallbackPaths: ["/Applications/ChatGPT.app"],
            configPath: nil,
            description: "OpenAI 官方 macOS 客户端"
        ),
        InstalledAIClient(
            id: "ollama",
            name: "Ollama 本地大模型",
            iconSymbol: "terminal.fill",
            bundleId: nil,
            fallbackPaths: ["/Applications/Ollama.app", "/usr/local/bin/ollama", "/opt/homebrew/bin/ollama"],
            configPath: nil,
            description: "轻量级本地开源大模型运行框架 (Llama, DeepSeek, Qwen 等)"
        ),
        InstalledAIClient(
            id: "vscode",
            name: "Visual Studio Code",
            iconSymbol: "macwindow",
            bundleId: "com.microsoft.VSCode",
            fallbackPaths: ["/Applications/Visual Studio Code.app"],
            configPath: nil,
            description: "支持 Roo Code / Continue / Cline 等 AI 插件直连 MCP"
        ),
        InstalledAIClient(
            id: "deepseek-harness",
            name: "DeepSeek Harness",
            iconSymbol: "brain",
            bundleId: "com.deepseek.harness",
            fallbackPaths: [
                "/Applications/DeepSeek Harness.app",
                "/Applications/DeepSeek.app",
                "/usr/local/bin/deepseek-harness",
                "/opt/homebrew/bin/deepseek-harness",
                "~/.deepseek/harness"
            ],
            configPath: "~/.deepseek/harness/config.json",
            description: "DeepSeek 官方/生态高性能推理执行与工作流客户端，支持 MCP 剪贴板工具直连"
        ),
        InstalledAIClient(
            id: "windsurf",
            name: "Windsurf Editor",
            iconSymbol: "wind",
            bundleId: "com.codeium.windsurf",
            fallbackPaths: ["/Applications/Windsurf.app"],
            configPath: "~/.codeium/windsurf/mcp_config.json",
            description: "Codeium 打造的智能代理代码编辑器，支持 MCP 架构"
        )
    ]

    var body: some View {
        VStack(spacing: 20) {
            // MARK: - Auto-detected Clients List
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    sectionLabel("本机 AI 客户端探测与一键启动")
                    Spacer()
                    Button {
                        actionMessage = "已刷新检测状态"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { actionMessage = nil }
                    } label: {
                        Label("重新探测", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.accent)
                }

                if let message = actionMessage {
                    Text(message)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.accent)
                        .padding(.vertical, 2)
                }

                sectionCard {
                    VStack(spacing: 0) {
                        ForEach(Array(supportedClients.enumerated()), id: \.element.id) { index, client in
                            HStack(spacing: 12) {
                                Image(systemName: client.iconSymbol)
                                    .font(.system(size: 16))
                                    .foregroundStyle(client.isInstalled ? palette.accent : palette.secondaryText.opacity(0.6))
                                    .frame(width: 28, height: 28)
                                    .background(
                                        (client.isInstalled ? palette.accent.opacity(0.12) : palette.secondaryText.opacity(0.08)),
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(client.name)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(palette.primaryText)

                                        if client.isRunning {
                                            Text("运行中")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(.green)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Color.green.opacity(0.12), in: Capsule())
                                        } else if client.isInstalled {
                                            Text("已安装")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(palette.accent)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(palette.accent.opacity(0.1), in: Capsule())
                                        } else {
                                            Text("未检测到")
                                                .font(.system(size: 10))
                                                .foregroundStyle(palette.secondaryText)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(palette.secondaryText.opacity(0.08), in: Capsule())
                                        }
                                    }

                                    Text(client.description)
                                        .font(.caption)
                                        .foregroundStyle(palette.secondaryText)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if client.isInstalled {
                                    HStack(spacing: 8) {
                                        if client.id == "claude" {
                                            Button("一键配置 MCP") {
                                                configureClaudeDesktop()
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        } else if client.id == "deepseek-harness" {
                                            Button("一键配置 MCP") {
                                                configureDeepseekHarness()
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }

                                        Button(client.isRunning ? "切换至应用" : "一键启动") {
                                            launchClient(client)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    }
                                } else {
                                    Text("未安装")
                                        .font(.caption)
                                        .foregroundStyle(palette.secondaryText)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)

                            if index < supportedClients.count - 1 {
                                Divider().padding(.leading, 50)
                            }
                        }
                    }
                }
            }

            // MARK: - Manual Configuration & Command Line
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showManualConfig.toggle()
                    }
                } label: {
                    HStack {
                        sectionLabel("高级：手动配置代码与命令行")
                        Image(systemName: showManualConfig ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                if showManualConfig {
                    sectionCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("标准 Model Context Protocol 配置 JSON：")
                                .font(.caption).foregroundStyle(palette.secondaryText)

                            let genericConfig = mcp.genericClientConfigJSON()
                            Text(genericConfig)
                                .font(.system(.caption, design: .monospaced))
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(palette.background, in: RoundedRectangle(cornerRadius: 8))

                            HStack {
                                Spacer()
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(genericConfig, forType: .string)
                                    actionMessage = "已复制标准 MCP 配置"
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { actionMessage = nil }
                                } label: {
                                    Label("复制 MCP 配置 JSON", systemImage: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(14)
                    }
                }
            }
        }
    }

    private func launchClient(_ client: InstalledAIClient) {
        if let appURL = client.appURL {
            let conf = NSWorkspace.OpenConfiguration()
            conf.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: conf) { _, error in
                DispatchQueue.main.async {
                    if let error {
                        self.actionMessage = "启动失败: \(error.localizedDescription)"
                    } else {
                        self.actionMessage = "已启动 \(client.name)"
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.actionMessage = nil }
                }
            }
        }
    }

    private func configureClaudeDesktop() {
        let configPath = ("~/Library/Application Support/Claude/claude_desktop_config.json" as NSString).expandingTildeInPath
        let folder = (configPath as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            var configDict: [String: Any] = [:]
            if FileManager.default.fileExists(atPath: configPath),
               let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                configDict = json
            }
            var mcpServers = (configDict["mcpServers"] as? [String: Any]) ?? [:]
            mcpServers["pasteloom"] = [
                "url": "http://127.0.0.1:\(mcp.port)/mcp"
            ]
            configDict["mcpServers"] = mcpServers
            let outData = try JSONSerialization.data(withJSONObject: configDict, options: [.prettyPrinted, .sortedKeys])
            try outData.write(to: URL(fileURLWithPath: configPath))
            actionMessage = "已成功写入 Claude Desktop 配置文件！"
        } catch {
            actionMessage = "写入配置失败: \(error.localizedDescription)"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { actionMessage = nil }
    }

    private func configureDeepseekHarness() {
        let configPath = ("~/.deepseek/harness/config.json" as NSString).expandingTildeInPath
        let folder = (configPath as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            var configDict: [String: Any] = [:]
            if FileManager.default.fileExists(atPath: configPath),
               let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                configDict = json
            }
            var mcpServers = (configDict["mcpServers"] as? [String: Any]) ?? [:]
            mcpServers["pasteloom"] = [
                "url": "http://127.0.0.1:\(mcp.port)/mcp"
            ]
            configDict["mcpServers"] = mcpServers
            let outData = try JSONSerialization.data(withJSONObject: configDict, options: [.prettyPrinted, .sortedKeys])
            try outData.write(to: URL(fileURLWithPath: configPath))
            actionMessage = "已成功写入 DeepSeek Harness 配置文件！"
        } catch {
            actionMessage = "写入配置失败: \(error.localizedDescription)"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { actionMessage = nil }
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.cardBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(palette.secondaryText)
    }
}

// MARK: - Available Tools View
struct MCPAvailableToolsView: View {
    @ObservedObject var mcp = MCPServer.shared
    let palette: PaperPalette

    var body: some View {
        VStack(spacing: 14) {
            ForEach(mcp.tools) { tool in
                sectionCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .foregroundStyle(palette.accent)
                            Text(tool.name)
                                .font(.headline.weight(.semibold))
                            Spacer()
                            Text("已就绪")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12), in: Capsule())
                        }

                        Text(tool.description)
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryText)

                        Divider().padding(.vertical, 2)

                        Text("参数架构 (Schema)：")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(palette.secondaryText)

                        if let props = tool.inputSchema["properties"]?.objectValue {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(props.keys.sorted()), id: \.self) { key in
                                    if let propObj = props[key]?.objectValue,
                                       let desc = propObj["description"]?.stringValue {
                                        HStack(alignment: .top, spacing: 6) {
                                            Text("• `\(key)`")
                                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                            Text("— \(desc)")
                                                .font(.caption)
                                                .foregroundStyle(palette.secondaryText)
                                        }
                                    }
                                }
                            }
                        } else {
                            Text("无需参数").font(.caption).foregroundStyle(palette.secondaryText)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.cardBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }
}
