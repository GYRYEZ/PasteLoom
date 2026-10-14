import Foundation
import Network

@MainActor
final class MCPServer: ObservableObject {
    static let shared = MCPServer()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "mcp_server_enabled")
            if isEnabled {
                start()
            } else {
                stop()
            }
        }
    }

    @Published var port: Int {
        didSet {
            UserDefaults.standard.set(port, forKey: "mcp_server_port")
            if isRunning {
                restart()
            }
        }
    }

    @Published var allowSensitiveExport: Bool {
        didSet {
            UserDefaults.standard.set(allowSensitiveExport, forKey: "mcp_allow_sensitive_export")
        }
    }

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var requestCount: Int = 0
    @Published private(set) var lastRequestTime: Date?
    @Published private(set) var lastError: String?

    private var listener: NWListener?
    private var repository: (any HistoryRepository)?

    private let availableTools: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: "search_history",
            description: "在 PasteLoom 剪贴板历史记录中搜索内容。支持关键词检索、类型过滤及返回数量限制。",
            inputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "query": .object(["type": .string("string"), "description": .string("要搜索的关键词")]),
                    "limit": .object(["type": .string("integer"), "description": .string("返回结果数量，默认 10")]),
                    "kind": .object(["type": .string("string"), "description": .string("类型过滤，可选值: text, image, file, url")])
                ]),
                "required": .array([.string("query")])
            ]
        ),
        MCPToolDefinition(
            name: "get_item",
            description: "根据条目 ID 获取剪贴板历史条目的完整详情（包括正文、类型、来源应用、标签、分组等）。",
            inputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "id": .object(["type": .string("string"), "description": .string("历史条目的 UUID")])
                ]),
                "required": .array([.string("id")])
            ]
        ),
        MCPToolDefinition(
            name: "add_snippet",
            description: "向 PasteLoom 常用片段库（Snippets）中添加一条新的文本片段或代码模板。",
            inputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "content": .object(["type": .string("string"), "description": .string("片段文本或代码内容")]),
                    "title": .object(["type": .string("string"), "description": .string("片段标题或备注")]),
                    "tags": .object(["type": .string("string"), "description": .string("逗号分隔的标签列表，例如 'swift,api'")]),
                    "group": .object(["type": .string("string"), "description": .string("所属分组名称")])
                ]),
                "required": .array([.string("content")])
            ]
        ),
        MCPToolDefinition(
            name: "get_statistics",
            description: "获取 PasteLoom 剪贴板历史库的统计指标（总条目数、各类型数量、收藏数、置顶数、片段数及复制频次统计）。",
            inputSchema: [
                "type": .string("object"),
                "properties": .object([:])
            ]
        ),
        MCPToolDefinition(
            name: "run_script",
            description: "在 PasteLoom 本地 JavaScript 安全沙盒中执行文本转换脚本（支持内置模板或即席代码）。",
            inputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "name": .object(["type": .string("string"), "description": .string("内置脚本名称（如 'JSON 格式化', 'Base64 编码'）")]),
                    "code": .object(["type": .string("string"), "description": .string("自定义 JavaScript 代码（须定义 transform(input) 函数）")]),
                    "input": .object(["type": .string("string"), "description": .string("待处理的输入文本")])
                ]),
                "required": .array([.string("input")])
            ]
        )
    ]

    var tools: [MCPToolDefinition] { availableTools }

    init() {
        let storedEnabled = UserDefaults.standard.bool(forKey: "mcp_server_enabled")
        let storedPort = UserDefaults.standard.integer(forKey: "mcp_server_port")
        let storedAllowSensitive = UserDefaults.standard.bool(forKey: "mcp_allow_sensitive_export")

        self.isEnabled = storedEnabled
        self.port = storedPort > 0 ? storedPort : 28833
        self.allowSensitiveExport = storedAllowSensitive

        if let defaultURL = try? SQLiteHistoryRepository.defaultURL(),
           let repo = try? SQLiteHistoryRepository(url: defaultURL) {
            self.repository = repo
        }

        if isEnabled {
            start()
        }
    }

    func setRepository(_ repo: any HistoryRepository) {
        self.repository = repo
    }

    func start() {
        guard !isRunning else { return }
        do {
            guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
                lastError = "无效的端口号: \(port)"
                return
            }
            let parameters = NWParameters.tcp
            let newListener = try NWListener(using: parameters, on: nwPort)

            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.lastError = nil
                    case .failed(let error):
                        self?.isRunning = false
                        self?.lastError = "MCP 服务启动失败: \(error.localizedDescription)"
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleIncomingConnection(connection)
                }
            }

            newListener.start(queue: .global(qos: .userInitiated))
            self.listener = newListener
            self.isRunning = true
            self.lastError = nil
        } catch {
            self.isRunning = false
            self.lastError = "无法启动监听器: \(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    func restart() {
        stop()
        start()
    }

    // MARK: - Connection & HTTP Handling
    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveNextMessage(from: connection)
    }

    private func receiveNextMessage(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            if let data = content, !data.isEmpty, let self = self {
                Task {
                    let responseData = await self.processHTTPPayload(data)
                    connection.send(content: responseData, completion: .contentProcessed({ _ in
                        connection.cancel()
                    }))
                }
            } else {
                connection.cancel()
            }
        }
    }

    private func processHTTPPayload(_ rawData: Data) async -> Data {
        guard let requestString = String(data: rawData, encoding: .utf8) else {
            return makeHTTPResponse(status: 400, body: #"{"error":"Invalid UTF-8"}"#)
        }

        // Extract HTTP body after \r\n\r\n or \n\n
        let bodyString: String
        if let range = requestString.range(of: "\r\n\r\n") {
            bodyString = String(requestString[range.upperBound...])
        } else if let range = requestString.range(of: "\n\n") {
            bodyString = String(requestString[range.upperBound...])
        } else {
            bodyString = requestString
        }

        guard let bodyData = bodyString.data(using: .utf8), !bodyData.isEmpty else {
            // Handshake or GET ping
            if requestString.hasPrefix("GET ") {
                let info = #"{"status":"ok","server":"PasteLoom-MCP","version":"1.0.0"}"#
                return makeHTTPResponse(status: 200, body: info)
            }
            return makeHTTPResponse(status: 400, body: #"{"error":"Empty body"}"#)
        }

        let resultData = await handleRequest(data: bodyData)
        let responseBody = String(data: resultData, encoding: .utf8) ?? "{}"
        return makeHTTPResponse(status: 200, body: responseBody)
    }

    private func makeHTTPResponse(status: Int, body: String) -> Data {
        let statusText = status == 200 ? "OK" : "Bad Request"
        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: POST, GET, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        \r
        \(body)
        """
        return response.data(using: .utf8) ?? Data()
    }

    // MARK: - Core JSON-RPC 2.0 / MCP Dispatcher
    func handleRequest(data: Data) async -> Data {
        requestCount += 1
        lastRequestTime = Date()

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let request = try? decoder.decode(JSONRPCRequest.self, from: data) else {
            let errorResponse = JSONRPCResponse.failure(id: nil, code: -32700, message: "Parse error: Invalid JSON-RPC request")
            return (try? encoder.encode(errorResponse)) ?? Data()
        }

        let response = await dispatchMethod(request)
        return (try? encoder.encode(response)) ?? Data()
    }

    private func dispatchMethod(_ req: JSONRPCRequest) async -> JSONRPCResponse {
        switch req.method {
        case "initialize":
            let result: [String: JSONValue] = [
                "protocolVersion": .string("2024-11-05"),
                "capabilities": .object([
                    "tools": .object([:])
                ]),
                "serverInfo": .object([
                    "name": .string("PasteLoom-MCP"),
                    "version": .string("1.0.0")
                ])
            ]
            return .success(id: req.id, result: .object(result))

        case "notifications/initialized":
            return .success(id: req.id, result: .object([:]))

        case "tools/list":
            let toolsJSON = availableTools.compactMap { tool -> JSONValue? in
                guard let data = try? JSONEncoder().encode(tool),
                      let val = try? JSONDecoder().decode(JSONValue.self, from: data) else {
                    return nil
                }
                return val
            }
            return .success(id: req.id, result: .object(["tools": .array(toolsJSON)]))

        case "tools/call":
            guard let params = req.params,
                  let toolName = params["name"]?.stringValue else {
                return .failure(id: req.id, code: -32602, message: "Missing tool 'name' in parameters")
            }
            let arguments = params["arguments"]?.objectValue ?? [:]
            let callResult = await executeTool(name: toolName, args: arguments)
            guard let resultData = try? JSONEncoder().encode(callResult),
                  let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: resultData) else {
                return .failure(id: req.id, code: -32603, message: "Internal serialization error")
            }
            return .success(id: req.id, result: jsonValue)

        default:
            return .failure(id: req.id, code: -32601, message: "Method not found: \(req.method)")
        }
    }

    // MARK: - Tool Implementations
    private func executeTool(name: String, args: [String: JSONValue]) async -> MCPCallToolResult {
        switch name {
        case "search_history":
            return await executeSearchHistory(args: args)
        case "get_item":
            return await executeGetItem(args: args)
        case "add_snippet":
            return await executeAddSnippet(args: args)
        case "get_statistics":
            return await executeGetStatistics(args: args)
        case "run_script":
            return await executeRunScript(args: args)
        default:
            return MCPCallToolResult(text: "未知工具: \(name)", isError: true)
        }
    }

    private func executeSearchHistory(args: [String: JSONValue]) async -> MCPCallToolResult {
        guard let repo = repository else {
            return MCPCallToolResult(text: "本地剪贴板历史存储不可用", isError: true)
        }
        let query = args["query"]?.stringValue ?? ""
        let limit = min(max(args["limit"]?.intValue ?? 10, 1), 50)
        let kindFilter = args["kind"]?.stringValue?.lowercased()

        var scope = HistoryScope.unrestricted
        if let kind = kindFilter {
            switch kind {
            case "text": scope.kind = .text
            case "image": scope.kind = .image
            case "file": scope.kind = .file
            case "url": scope.kind = .url
            default: break
            }
        }

        do {
            let items = try await repo.search(text: query, limit: limit, offset: 0, filter: .all, mode: .fullText, scope: scope)
            var formattedList: [[String: Any]] = []

            for item in items {
                var textContent = item.text
                if !allowSensitiveExport {
                    textContent = SensitiveContentService.shared.mask(text: textContent).maskedText
                }

                var dict: [String: Any] = [
                    "id": item.id.uuidString,
                    "kind": item.kind.rawValue,
                    "text": textContent,
                    "created_at": ISO8601DateFormatter().string(from: item.capturedAt),
                    "is_favorite": item.isFavorite,
                    "is_pinned": item.isPinned,
                    "is_snippet": item.isSnippet,
                    "tags": item.tags
                ]
                if let app = item.sourceName {
                    dict["source_app"] = app
                }
                if let group = item.groupName {
                    dict["group"] = group
                }
                formattedList.append(dict)
            }

            guard let jsonData = try? JSONSerialization.data(withJSONObject: formattedList, options: [.prettyPrinted]),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                return MCPCallToolResult(text: "[]")
            }
            return MCPCallToolResult(text: jsonString)
        } catch {
            return MCPCallToolResult(text: "搜索失败: \(error.localizedDescription)", isError: true)
        }
    }

    private func executeGetItem(args: [String: JSONValue]) async -> MCPCallToolResult {
        guard let repo = repository else {
            return MCPCallToolResult(text: "本地剪贴板历史存储不可用", isError: true)
        }
        guard let idString = args["id"]?.stringValue, let uuid = UUID(uuidString: idString) else {
            return MCPCallToolResult(text: "参数错误: 请提供有效的 UUID", isError: true)
        }

        do {
            let items = try await repo.search(text: "", limit: 1000, offset: 0)
            guard let item = items.first(where: { $0.id == uuid }) else {
                return MCPCallToolResult(text: "未找到 ID 为 \(idString) 的条目", isError: true)
            }

            var textContent = item.text
            if !allowSensitiveExport {
                textContent = SensitiveContentService.shared.mask(text: textContent).maskedText
            }

            var dict: [String: Any] = [
                "id": item.id.uuidString,
                "kind": item.kind.rawValue,
                "text": textContent,
                "created_at": ISO8601DateFormatter().string(from: item.capturedAt),
                "is_favorite": item.isFavorite,
                "is_pinned": item.isPinned,
                "is_snippet": item.isSnippet,
                "tags": item.tags,
                "copy_count": item.copyCount
            ]
            if let sourceName = item.sourceName {
                dict["source_app"] = sourceName
            }
            if let bundleId = item.sourceBundleIdentifier {
                dict["bundle_id"] = bundleId
            }
            if let group = item.groupName {
                dict["group"] = group
            }
            if let ocr = item.ocrText, !ocr.isEmpty {
                dict["ocr_text"] = ocr
            }

            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
            return MCPCallToolResult(text: String(data: data, encoding: .utf8) ?? "{}")
        } catch {
            return MCPCallToolResult(text: "读取条目失败: \(error.localizedDescription)", isError: true)
        }
    }

    private func executeAddSnippet(args: [String: JSONValue]) async -> MCPCallToolResult {
        guard let repo = repository else {
            return MCPCallToolResult(text: "本地剪贴板历史存储不可用", isError: true)
        }
        guard let content = args["content"]?.stringValue, !content.isEmpty else {
            return MCPCallToolResult(text: "参数错误: 片段内容不能为空", isError: true)
        }

        let group = args["group"]?.stringValue
        let tagsRaw = args["tags"]?.stringValue ?? ""
        let tags = tagsRaw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        do {
            let captured = CapturedContent.text(content)
            try await repo.insert(content: captured, at: Date(), source: CaptureSource(name: "MCP Client", bundleIdentifier: "ai.mcp.client"))

            // Find inserted item to update snippet flags
            let latest = try await repo.search(text: content, limit: 5, offset: 0)
            if let item = latest.first(where: { $0.text == content }) {
                try await repo.setSnippet(true, for: item.id)
                if !tags.isEmpty {
                    try await repo.setTags(tags, for: item.id)
                }
                if let group = group, !group.isEmpty {
                    try await repo.setGroup(group, for: item.id)
                }
                return MCPCallToolResult(text: "已成功将片段存入 PasteLoom (ID: \(item.id.uuidString))")
            }
            return MCPCallToolResult(text: "片段已成功插入")
        } catch {
            return MCPCallToolResult(text: "添加片段失败: \(error.localizedDescription)", isError: true)
        }
    }

    private func executeGetStatistics(args: [String: JSONValue]) async -> MCPCallToolResult {
        guard let repo = repository else {
            return MCPCallToolResult(text: "本地剪贴板历史存储不可用", isError: true)
        }
        do {
            let stats = try await repo.fetchStatistics()
            let dict: [String: Any] = [
                "total_items": stats.totalItems,
                "text_count": stats.textCount,
                "image_count": stats.imageCount,
                "file_count": stats.fileCount,
                "url_count": stats.urlCount,
                "rich_text_count": stats.richTextCount,
                "video_count": stats.videoCount,
                "snippet_count": stats.snippetCount,
                "total_copies": stats.totalCopies
            ]
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
            return MCPCallToolResult(text: String(data: data, encoding: .utf8) ?? "{}")
        } catch {
            return MCPCallToolResult(text: "获取统计失败: \(error.localizedDescription)", isError: true)
        }
    }

    private func executeRunScript(args: [String: JSONValue]) async -> MCPCallToolResult {
        guard let input = args["input"]?.stringValue else {
            return MCPCallToolResult(text: "参数错误: 缺少 input 文本", isError: true)
        }

        let scriptCode: String
        if let directCode = args["code"]?.stringValue, !directCode.isEmpty {
            scriptCode = directCode
        } else if let scriptName = args["name"]?.stringValue {
            let scripts = ScriptSandbox.shared.loadScripts()
            if let matched = scripts.first(where: { $0.name == scriptName }) {
                scriptCode = matched.code
            } else {
                return MCPCallToolResult(text: "未找到名为 '\(scriptName)' 的脚本", isError: true)
            }
        } else {
            return MCPCallToolResult(text: "参数错误: 请提供 scriptName 或 JavaScript code", isError: true)
        }

        let result = await ScriptSandbox.shared.execute(code: scriptCode, input: input)
        if let err = result.error {
            return MCPCallToolResult(text: "脚本执行异常: \(err)", isError: true)
        }
        return MCPCallToolResult(text: result.output)
    }

    // MARK: - Client Configuration Helpers
    func claudeDesktopConfigJSON() -> String {
        """
        {
          "mcpServers": {
            "pasteloom": {
              "command": "curl",
              "args": [
                "-s",
                "-X",
                "POST",
                "http://127.0.0.1:\(port)/mcp",
                "-H",
                "Content-Type: application/json",
                "-d"
              ]
            }
          }
        }
        """
    }

    func genericClientConfigJSON() -> String {
        """
        {
          "server_name": "PasteLoom-MCP",
          "endpoint": "http://127.0.0.1:\(port)/mcp",
          "transport": "http-jsonrpc-2.0",
          "protocol_version": "2024-11-05",
          "capabilities": ["tools"],
          "available_tools": [
            "search_history",
            "get_item",
            "add_snippet",
            "get_statistics",
            "run_script"
          ]
        }
        """
    }
}
