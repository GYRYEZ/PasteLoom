import XCTest
@testable import PasteLoom

final class Stage5Tests: XCTestCase {

    // MARK: - 1. Rule Engine Matching Tests
    @MainActor
    func testRuleConditionMatching() {
        // Text condition
        let textCond = RuleCondition(type: .text, op: .contains, value: "keyword")
        XCTAssertTrue(textCond.matches(text: "Here is a keyword", source: nil, kind: .text))
        XCTAssertFalse(textCond.matches(text: "Nothing here", source: nil, kind: .text))

        // Regex condition
        let regexCond = RuleCondition(type: .text, op: .matchesRegex, value: #"^PR-[0-9]{3}$"#)
        XCTAssertTrue(regexCond.matches(text: "PR-123", source: nil, kind: .text))
        XCTAssertFalse(regexCond.matches(text: "PR-ABCD", source: nil, kind: .text))

        // Source App condition
        let appCond = RuleCondition(type: .sourceApp, op: .contains, value: "Xcode")
        let xcodeSource = CaptureSource(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
        let safariSource = CaptureSource(name: "Safari", bundleIdentifier: "com.apple.Safari")
        XCTAssertTrue(appCond.matches(text: "some code", source: xcodeSource, kind: .text))
        XCTAssertFalse(appCond.matches(text: "some code", source: safariSource, kind: .text))

        // Content Length condition
        let lenCond = RuleCondition(type: .textLength, op: .contains, value: "10")
        XCTAssertTrue(lenCond.matches(text: "This string is long", source: nil, kind: .text))
        XCTAssertFalse(lenCond.matches(text: "Short", source: nil, kind: .text))
    }

    // MARK: - 2. Rule Evaluation and Action Outcomes
    @MainActor
    func testRuleEvaluationAndActions() {
        let engine = RuleEngine()
        engine.rules.removeAll()

        let tagRule = AutomationRule(
            name: "AutoTagAndFavorite",
            isEnabled: true,
            conditions: [RuleCondition(type: .text, op: .hasPrefix, value: "NOTE:")],
            actions: [
                RuleAction(type: .addTag, parameter: "笔记"),
                RuleAction(type: .setGroup, parameter: "工作备忘"),
                RuleAction(type: .markFavorite),
                RuleAction(type: .markSnippet)
            ]
        )
        engine.addRule(tagRule)

        let discardRule = AutomationRule(
            name: "DiscardPasswords",
            isEnabled: true,
            conditions: [RuleCondition(type: .text, op: .contains, value: "PASSWORD_DISCARD")],
            actions: [RuleAction(type: .discard)]
        )
        engine.addRule(discardRule)

        // Test normal matching
        let outcome1 = engine.evaluate(text: "NOTE: Review design doc", source: nil, kind: .text)
        XCTAssertFalse(outcome1.shouldDiscard)
        XCTAssertTrue(outcome1.tagsToAdd.contains("笔记"))
        XCTAssertEqual(outcome1.groupToSet, "工作备忘")
        XCTAssertTrue(outcome1.markFavorite)
        XCTAssertTrue(outcome1.markSnippet)
        XCTAssertEqual(outcome1.matchedRuleNames, ["AutoTagAndFavorite"])

        // Test discard rule
        let outcome2 = engine.evaluate(text: "PASSWORD_DISCARD secret", source: nil, kind: .text)
        XCTAssertTrue(outcome2.shouldDiscard)
        XCTAssertTrue(outcome2.matchedRuleNames.contains("DiscardPasswords"))
    }

    // MARK: - 3. Script Sandbox Execution Tests
    func testScriptSandboxExecution() async {
        let sandbox = ScriptSandbox.shared

        // 1. Test JSON formatting
        let jsonInput = "{\"a\":1,\"b\":\"test\"}"
        let jsonScript = """
        function transform(input) {
            return JSON.stringify(JSON.parse(input), null, 2);
        }
        """
        let jsonResult = await sandbox.execute(code: jsonScript, input: jsonInput)
        XCTAssertTrue(jsonResult.isSuccess)
        XCTAssertTrue(jsonResult.output.contains("\n  \"a\": 1"))

        // 2. Test Base64 Encoding
        let plain = "Hello, PasteLoom!"
        let base64Script = """
        function transform(input) {
            return btoa(input);
        }
        """
        let base64Result = await sandbox.execute(code: base64Script, input: plain)
        XCTAssertTrue(base64Result.isSuccess)
        XCTAssertEqual(base64Result.output, "SGVsbG8sIFBhc3RlTG9vbSE=")

        // 3. Test Base64 Decoding
        let decodeScript = """
        function transform(input) {
            return atob(input);
        }
        """
        let decodeResult = await sandbox.execute(code: decodeScript, input: "SGVsbG8sIFBhc3RlTG9vbSE=")
        XCTAssertTrue(decodeResult.isSuccess)
        XCTAssertEqual(decodeResult.output, plain)

        // 4. Test Error handling (Syntax Error)
        let brokenScript = """
        function transform(input) {
            return invalid syntax here!
        }
        """
        let errorResult = await sandbox.execute(code: brokenScript, input: "test")
        XCTAssertFalse(errorResult.isSuccess)
        XCTAssertNotNil(errorResult.error)
    }

    // MARK: - 4. Execution Log Service Tests
    @MainActor
    func testExecutionLogService() {
        let service = ExecutionLogService.shared
        service.clear()
        XCTAssertTrue(service.logs.isEmpty)

        service.record(title: "测试任务 1", status: "成功", durationMs: 4.2, detail: "详情 A")
        service.record(title: "测试任务 2", status: "失败", durationMs: 1.5, detail: "详情 B")

        XCTAssertEqual(service.logs.count, 2)
        XCTAssertEqual(service.logs.first?.title, "测试任务 2")
        XCTAssertEqual(service.logs.first?.status, "失败")

        service.clear()
        XCTAssertTrue(service.logs.isEmpty)
    }
}
