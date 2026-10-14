import XCTest
@testable import PasteLoom

final class Stage6Tests: XCTestCase {

    // MARK: - 1. JSON-RPC Protocol Serialization & Handshake
    func testJSONRPCProtocolSerialization() throws {
        // Test request encoding/decoding
        let req = JSONRPCRequest(id: .int(42), method: "initialize", params: ["key": .string("val")])
        let data = try JSONEncoder().encode(req)
        let decoded = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
        XCTAssertEqual(decoded.method, "initialize")
        XCTAssertEqual(decoded.id, .int(42))
        XCTAssertEqual(decoded.params?["key"]?.stringValue, "val")

        // Test response success
        let respSuccess = JSONRPCResponse.success(id: .int(42), result: .string("ok"))
        let respData = try JSONEncoder().encode(respSuccess)
        let decodedResp = try JSONDecoder().decode(JSONRPCResponse.self, from: respData)
        XCTAssertEqual(decodedResp.result?.stringValue, "ok")
        XCTAssertNil(decodedResp.error)

        // Test response failure
        let respError = JSONRPCResponse.failure(id: .int(42), code: -32601, message: "Method not found")
        let errData = try JSONEncoder().encode(respError)
        let decodedErr = try JSONDecoder().decode(JSONRPCResponse.self, from: errData)
        XCTAssertEqual(decodedErr.error?.code, -32601)
        XCTAssertEqual(decodedErr.error?.message, "Method not found")
    }

    // MARK: - 2. MCP Handshake & Tools List Dispatch
    @MainActor
    func testMCPInitializeAndToolsList() async throws {
        let server = MCPServer()

        // 1. Initialize
        let initReq = JSONRPCRequest(id: .int(1), method: "initialize")
        let initData = try JSONEncoder().encode(initReq)
        let initRespData = await server.handleRequest(data: initData)
        let initResp = try JSONDecoder().decode(JSONRPCResponse.self, from: initRespData)

        XCTAssertEqual(initResp.id, .int(1))
        let serverInfo = initResp.result?.objectValue?["serverInfo"]?.objectValue
        XCTAssertEqual(serverInfo?["name"]?.stringValue, "PasteLoom-MCP")
        XCTAssertEqual(serverInfo?["version"]?.stringValue, "1.0.0")

        // 2. Tools list
        let toolsReq = JSONRPCRequest(id: .int(2), method: "tools/list")
        let toolsData = try JSONEncoder().encode(toolsReq)
        let toolsRespData = await server.handleRequest(data: toolsData)
        let toolsResp = try JSONDecoder().decode(JSONRPCResponse.self, from: toolsRespData)

        let toolsArray = toolsResp.result?.objectValue?["tools"]?.arrayValue
        XCTAssertNotNil(toolsArray)
        let toolNames = toolsArray?.compactMap { $0.objectValue?["name"]?.stringValue } ?? []
        XCTAssertTrue(toolNames.contains("search_history"))
        XCTAssertTrue(toolNames.contains("get_item"))
        XCTAssertTrue(toolNames.contains("add_snippet"))
        XCTAssertTrue(toolNames.contains("get_statistics"))
        XCTAssertTrue(toolNames.contains("run_script"))
    }

    // MARK: - 3. MCP Tool Call - Run Script
    @MainActor
    func testMCPToolCallRunScript() async throws {
        let server = MCPServer()

        let scriptCode = """
        function transform(input) {
            return input.toUpperCase();
        }
        """

        let callReq = JSONRPCRequest(
            id: .int(3),
            method: "tools/call",
            params: [
                "name": .string("run_script"),
                "arguments": .object([
                    "code": .string(scriptCode),
                    "input": .string("hello mcp")
                ])
            ]
        )
        let reqData = try JSONEncoder().encode(callReq)
        let respData = await server.handleRequest(data: reqData)
        let resp = try JSONDecoder().decode(JSONRPCResponse.self, from: respData)

        let contentArray = resp.result?.objectValue?["content"]?.arrayValue
        let textResult = contentArray?.first?.objectValue?["text"]?.stringValue
        XCTAssertEqual(textResult, "HELLO MCP")
    }

    // MARK: - 4. MCP Tool Call - Add Snippet & Statistics
    @MainActor
    func testMCPToolCallAddSnippetAndStatistics() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let repoURL = tempDir.appendingPathComponent("mcp_test.sqlite3")
        let repo = try SQLiteHistoryRepository(url: repoURL)

        let server = MCPServer()
        server.setRepository(repo)

        // 1. Add snippet
        let addReq = JSONRPCRequest(
            id: .int(10),
            method: "tools/call",
            params: [
                "name": .string("add_snippet"),
                "arguments": .object([
                    "content": .string("let sample = 42"),
                    "title": .string("Sample Swift Code"),
                    "tags": .string("swift,test"),
                    "group": .string("代码段")
                ])
            ]
        )
        let addData = try JSONEncoder().encode(addReq)
        let addRespData = await server.handleRequest(data: addData)
        let addResp = try JSONDecoder().decode(JSONRPCResponse.self, from: addRespData)
        let addText = addResp.result?.objectValue?["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue
        XCTAssertTrue(addText?.contains("已成功") == true)

        // 2. Search history tool
        let searchReq = JSONRPCRequest(
            id: .int(11),
            method: "tools/call",
            params: [
                "name": .string("search_history"),
                "arguments": .object([
                    "query": .string("sample")
                ])
            ]
        )
        let searchData = try JSONEncoder().encode(searchReq)
        let searchRespData = await server.handleRequest(data: searchData)
        let searchResp = try JSONDecoder().decode(JSONRPCResponse.self, from: searchRespData)
        let searchText = searchResp.result?.objectValue?["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue
        XCTAssertTrue(searchText?.contains("let sample = 42") == true)

        // 3. Get statistics tool
        let statsReq = JSONRPCRequest(
            id: .int(12),
            method: "tools/call",
            params: [
                "name": .string("get_statistics"),
                "arguments": .object([:])
            ]
        )
        let statsData = try JSONEncoder().encode(statsReq)
        let statsRespData = await server.handleRequest(data: statsData)
        let statsResp = try JSONDecoder().decode(JSONRPCResponse.self, from: statsRespData)
        let statsText = statsResp.result?.objectValue?["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue
        XCTAssertTrue(statsText?.contains("snippet_count") == true)
        XCTAssertTrue(statsText?.contains("total_items") == true)
    }

    // MARK: - 5. Sensitive Content Protection in MCP
    @MainActor
    func testMCPSensitiveContentMasking() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let repoURL = tempDir.appendingPathComponent("mcp_mask_test.sqlite3")
        let repo = try SQLiteHistoryRepository(url: repoURL)

        // Insert item with sensitive info
        let sensitiveText = "My phone is 13812345678 and token is Bearer sk-1234567890abcdef123456"
        try await repo.insert(content: .text(sensitiveText), at: Date())

        let server = MCPServer()
        server.setRepository(repo)
        server.allowSensitiveExport = false // Protection ON

        let searchReq = JSONRPCRequest(
            id: .int(20),
            method: "tools/call",
            params: [
                "name": .string("search_history"),
                "arguments": .object(["query": .string("phone")])
            ]
        )
        let searchData = try JSONEncoder().encode(searchReq)
        let searchRespData = await server.handleRequest(data: searchData)
        let searchResp = try JSONDecoder().decode(JSONRPCResponse.self, from: searchRespData)
        let text = searchResp.result?.objectValue?["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue ?? ""

        // Verify phone is masked
        XCTAssertFalse(text.contains("13812345678"))
        XCTAssertTrue(text.contains("138****5678") || text.contains("****"))
    }
}
