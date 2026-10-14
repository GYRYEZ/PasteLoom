import XCTest
@testable import PasteLoom

final class Stage4Tests: XCTestCase {

    private func temporaryDatabase() -> (directory: URL, url: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("history.sqlite3"))
    }

    // MARK: - 1. Excluded App Blacklist Tests
    @MainActor
    func testExcludedAppFilter() async throws {
        let filter = CaptureFilterService()
        
        // Default password managers should be present
        let apps = filter.excludedApps
        XCTAssertTrue(apps.contains(where: { $0.name.contains("1Password") }))
        XCTAssertTrue(apps.contains(where: { $0.name.contains("Bitwarden") }))
        
        let opSource = CaptureSource(name: "1Password 7", bundleIdentifier: "com.agilebits.onepassword7")
        let excluded = filter.shouldExclude(app: opSource)
        XCTAssertTrue(excluded)
        
        let safariSource = CaptureSource(name: "Safari", bundleIdentifier: "com.apple.Safari")
        let safariExcluded = filter.shouldExclude(app: safariSource)
        XCTAssertFalse(safariExcluded)
        
        // Add custom app
        filter.addApp(bundleIdentifier: "com.secret.notes", name: "SecretNotes")
        let customSource = CaptureSource(name: "SecretNotes", bundleIdentifier: "com.secret.notes")
        XCTAssertTrue(filter.shouldExclude(app: customSource))
        
        // Toggle off
        if let customApp = filter.excludedApps.first(where: { $0.bundleIdentifier == "com.secret.notes" }) {
            filter.toggleApp(id: customApp.id)
            XCTAssertFalse(filter.shouldExclude(app: customSource))
            
            // Remove
            filter.removeApp(id: customApp.id)
            let remainingApps = filter.excludedApps
            XCTAssertFalse(remainingApps.contains(where: { $0.bundleIdentifier == "com.secret.notes" }))
        } else {
            XCTFail("Custom app not found")
        }
    }

    // MARK: - 2. Excluded Text Rules Tests
    @MainActor
    func testExcludedTextRulesFilter() async throws {
        let filter = CaptureFilterService()
        
        // Contains match
        filter.addTextRule(name: "Passphrase", pattern: "TOPSECRET", matchKind: .contains)
        XCTAssertTrue(filter.shouldExclude(text: "Here is TOPSECRET code"))
        XCTAssertFalse(filter.shouldExclude(text: "Normal text"))
        
        // Prefix match
        filter.addTextRule(name: "PrefixRule", pattern: "PIN:", matchKind: .prefix)
        XCTAssertTrue(filter.shouldExclude(text: "PIN:123456"))
        XCTAssertFalse(filter.shouldExclude(text: "The PIN:123456"))
        
        // Regex match
        filter.addTextRule(name: "TokenRule", pattern: #"^token_[0-9]{4}$"#, matchKind: .regex)
        XCTAssertTrue(filter.shouldExclude(text: "token_9876"))
        XCTAssertFalse(filter.shouldExclude(text: "token_abcd"))
        
        // Toggle rule off
        if let rule = filter.excludedTextRules.first(where: { $0.name == "Passphrase" }) {
            filter.toggleTextRule(id: rule.id)
            XCTAssertFalse(filter.shouldExclude(text: "Here is TOPSECRET code"))
            filter.removeTextRule(id: rule.id)
        }
    }

    // MARK: - 3. Sensitive Content Masking Tests
    func testSensitiveContentMasking() throws {
        let service = SensitiveContentService.shared
        
        // Phone masking
        let phoneResult = service.mask(text: "致电 13812345678 了解详情")
        XCTAssertTrue(phoneResult.hasSensitive)
        XCTAssertTrue(phoneResult.detectedKinds.contains(.phone))
        XCTAssertEqual(phoneResult.maskedText, "致电 138****5678 了解详情")
        
        // Email masking
        let emailResult = service.mask(text: "发送到 alice@company.org 联系")
        XCTAssertTrue(emailResult.hasSensitive)
        XCTAssertTrue(emailResult.detectedKinds.contains(.email))
        XCTAssertTrue(emailResult.maskedText.contains("ali***@company.org"))
        
        // ID card masking (18 digits)
        let idResult = service.mask(text: "身份证号 110101199003072345")
        XCTAssertTrue(idResult.hasSensitive)
        XCTAssertTrue(idResult.detectedKinds.contains(.idCard))
        XCTAssertEqual(idResult.maskedText, "身份证号 110101********2345")
        
        // Bank card masking
        let bankResult = service.mask(text: "卡号 6222021234567890 汇入")
        XCTAssertTrue(bankResult.hasSensitive)
        XCTAssertTrue(bankResult.detectedKinds.contains(.bankCard))
        XCTAssertEqual(bankResult.maskedText, "卡号 6222********7890 汇入")
        
        // API key / Bearer Token masking
        let apiResult = service.mask(text: "Authorization: Bearer sk-abc1234567890abcdef123456")
        XCTAssertTrue(apiResult.hasSensitive)
        XCTAssertTrue(apiResult.detectedKinds.contains(.apiKey))
        XCTAssertTrue(apiResult.maskedText.contains("sk-abc****************"))
        
        // Harmless text
        let cleanResult = service.mask(text: "今天天气真好，Swift 编程很有趣！")
        XCTAssertFalse(cleanResult.hasSensitive)
        XCTAssertEqual(cleanResult.maskedText, "今天天气真好，Swift 编程很有趣！")
    }

    // MARK: - 4. Schema v7, Snippet and Group Tests
    func testSchemaV7SnippetAndGroup() async throws {
        let (dir, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = try SQLiteHistoryRepository(url: url)
        let now = Date()
        
        try await repo.insert(content: .text("常用终端指令 git status"), at: now, source: nil)
        try await repo.insert(content: .text("工作会议纪要"), at: now.addingTimeInterval(-10), source: nil)
        
        let allItems = try await repo.search(text: "", limit: 10, offset: 0, filter: .all, mode: .fullText, scope: .unrestricted)
        XCTAssertEqual(allItems.count, 2)
        
        let gitItem = try XCTUnwrap(allItems.first(where: { $0.text.contains("git") }))
        let workItem = try XCTUnwrap(allItems.first(where: { $0.text.contains("会议") }))
        
        // Set snippet and group
        try await repo.setSnippet(true, for: gitItem.id)
        try await repo.setGroup("开发工具", for: gitItem.id)
        try await repo.setGroup("日常工作", for: workItem.id)
        
        let groups = try await repo.allGroups()
        XCTAssertEqual(Set(groups), Set(["开发工具", "日常工作"]))
        
        // Search by snippet scope
        let snippetScope = HistoryScope(isSnippet: true)
        let snippetItems = try await repo.search(text: "", limit: 10, offset: 0, filter: .all, mode: .fullText, scope: snippetScope)
        XCTAssertEqual(snippetItems.count, 1)
        XCTAssertEqual(snippetItems.first?.id, gitItem.id)
        
        // Search by group scope
        let groupScope = HistoryScope(groupName: "开发工具")
        let devItems = try await repo.search(text: "", limit: 10, offset: 0, filter: .all, mode: .fullText, scope: groupScope)
        XCTAssertEqual(devItems.count, 1)
        XCTAssertEqual(devItems.first?.id, gitItem.id)
    }

    // MARK: - 5. Multi-Item Text Merge Tests
    func testMultiItemTextMerge() async throws {
        let (dir, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = try SQLiteHistoryRepository(url: url)
        let now = Date()
        
        try await repo.insert(content: .text("First paragraph."), at: now.addingTimeInterval(-20), source: CaptureSource(name: "Notes", bundleIdentifier: nil))
        try await repo.insert(content: .text("Second paragraph."), at: now.addingTimeInterval(-10), source: CaptureSource(name: "Safari", bundleIdentifier: nil))
        
        let items = try await repo.search(text: "", limit: 10, offset: 0, filter: .all, mode: .fullText, scope: .unrestricted)
        XCTAssertEqual(items.count, 2)
        
        let item1 = items[0]
        let item2 = items[1]
        
        try await repo.setTags(["标签1"], for: item1.id)
        try await repo.setTags(["标签2"], for: item2.id)
        
        let merged = try await repo.merge(ids: [item1.id, item2.id], separator: "\n---\n")
        XCTAssertNotNil(merged)
        XCTAssertEqual(merged?.sourceName, "Merge")
        XCTAssertTrue(merged?.text.contains("---") ?? false)
        XCTAssertTrue(merged?.tags.contains("标签1") ?? false)
        XCTAssertTrue(merged?.tags.contains("标签2") ?? false)
        
        // Check database count is now 3
        let updatedItems = try await repo.search(text: "", limit: 10, offset: 0, filter: .all, mode: .fullText, scope: .unrestricted)
        XCTAssertEqual(updatedItems.count, 3)
    }

    // MARK: - 6. Retention Engine Safety & Protection Tests
    func testRetentionEngineProtection() async throws {
        let (dir, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = try SQLiteHistoryRepository(url: url)
        let oldDate = Date().addingTimeInterval(-45 * 24 * 3600) // 45 days ago
        let recentDate = Date().addingTimeInterval(-5 * 24 * 3600) // 5 days ago
        
        // 1. Normal old item (should be purged by 30-day retention)
        try await repo.insert(content: .text("Old normal item"), at: oldDate, source: nil)
        
        // 2. Old pinned item (MUST BE PROTECTED)
        try await repo.insert(content: .text("Old pinned item"), at: oldDate, source: nil)
        
        // 3. Old favorite item (MUST BE PROTECTED)
        try await repo.insert(content: .text("Old favorite item"), at: oldDate, source: nil)
        
        // 4. Old snippet item (MUST BE PROTECTED)
        try await repo.insert(content: .text("Old snippet item"), at: oldDate, source: nil)
        
        // 5. Recent normal item (within 30 days, kept)
        try await repo.insert(content: .text("Recent normal item"), at: recentDate, source: nil)
        
        let allItems = try await repo.search(text: "", limit: 10, offset: 0, filter: .all, mode: .fullText, scope: .unrestricted)
        XCTAssertEqual(allItems.count, 5)
        
        let pinnedItem = try XCTUnwrap(allItems.first(where: { $0.text == "Old pinned item" }))
        let favoriteItem = try XCTUnwrap(allItems.first(where: { $0.text == "Old favorite item" }))
        let snippetItem = try XCTUnwrap(allItems.first(where: { $0.text == "Old snippet item" }))
        
        try await repo.setPinned(true, for: pinnedItem.id)
        try await repo.setFavorite(true, for: favoriteItem.id)
        try await repo.setSnippet(true, for: snippetItem.id)
        
        // Run retention with 30 days threshold
        let purgedCount = try await repo.runRetention(retentionDays: 30, trashRetentionDays: 7)
        XCTAssertEqual(purgedCount, 1) // Only "Old normal item" should be purged
        
        let remainingItems = try await repo.search(text: "", limit: 10, offset: 0, filter: .all, mode: .fullText, scope: .unrestricted)
        XCTAssertEqual(remainingItems.count, 4)
        
        let remainingTexts = Set(remainingItems.map(\.text))
        XCTAssertFalse(remainingTexts.contains("Old normal item"))
        XCTAssertTrue(remainingTexts.contains("Old pinned item"))
        XCTAssertTrue(remainingTexts.contains("Old favorite item"))
        XCTAssertTrue(remainingTexts.contains("Old snippet item"))
        XCTAssertTrue(remainingTexts.contains("Recent normal item"))
    }

    // MARK: - 7. Usage Statistics & Copy Count Tests
    func testStatisticsAndCopyCount() async throws {
        let (dir, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = try SQLiteHistoryRepository(url: url)
        let now = Date()
        
        try await repo.insert(content: .text("Frequent item A"), at: now, source: nil)
        try await repo.insert(content: .text("Frequent item B"), at: now.addingTimeInterval(-1), source: nil)
        
        let items = try await repo.search(text: "", limit: 10, offset: 0, filter: .all, mode: .fullText, scope: .unrestricted)
        let itemA = try XCTUnwrap(items.first(where: { $0.text == "Frequent item A" }))
        let itemB = try XCTUnwrap(items.first(where: { $0.text == "Frequent item B" }))
        
        try await repo.incrementCopyCount(for: itemA.id)
        try await repo.incrementCopyCount(for: itemA.id)
        try await repo.incrementCopyCount(for: itemA.id)
        try await repo.incrementCopyCount(for: itemB.id)
        
        let stats = try await repo.fetchStatistics()
        XCTAssertEqual(stats.totalItems, 2)
        XCTAssertEqual(stats.totalCopies, 4)
        XCTAssertEqual(stats.textCount, 2)
        XCTAssertEqual(stats.topCopied.count, 2)
        XCTAssertEqual(stats.topCopied[0].id, itemA.id)
        XCTAssertEqual(stats.topCopied[0].copyCount, 3)
        XCTAssertEqual(stats.topCopied[1].id, itemB.id)
        XCTAssertEqual(stats.topCopied[1].copyCount, 1)
        
        // Reset statistics
        try await repo.resetStatistics()
        let resetStats = try await repo.fetchStatistics()
        XCTAssertEqual(resetStats.totalCopies, 0)
        XCTAssertEqual(resetStats.topCopied.first?.copyCount ?? 0, 0)
    }

    // MARK: - 5. OCR & Text Extraction Tests
    @MainActor
    func testPerformOCRAndExtractText() async throws {
        let model = AppModel()
        let textItem = HistoryItem(
            id: UUID(),
            kind: .text,
            text: "Hello OCR Plain Text Extraction",
            capturedAt: Date(),
            imageRelativePath: nil,
            contentHash: "hash-text",
            files: [],
            sourceName: "TestApp",
            sourceBundleIdentifier: "com.test.app"
        )
        
        let extracted = await model.performOCRAsync(for: textItem)
        XCTAssertEqual(extracted, "Hello OCR Plain Text Extraction")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Hello OCR Plain Text Extraction")

        let imageItemWithOCR = HistoryItem(
            id: UUID(),
            kind: .image,
            text: "image.png",
            capturedAt: Date(),
            imageRelativePath: "relative/path.png",
            contentHash: "hash-image",
            files: [],
            sourceName: "TestApp",
            sourceBundleIdentifier: "com.test.app",
            ocrText: "Recognized Text Inside Image"
        )
        let extractedFromImage = await model.performOCRAsync(for: imageItemWithOCR)
        XCTAssertEqual(extractedFromImage, "Recognized Text Inside Image")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Recognized Text Inside Image")
    }

    func testOCRTextFormatterMenuConsolidation() {
        let rawMenu = """
        文件
        显示
        窗口
        帮助
        """
        let formatted = OCRTextFormatter.format(rawMenu)
        XCTAssertEqual(formatted, "文件  显示  窗口  帮助")
    }

    func testOCRTextFormatterDataPreservation() {
        let rawData = """
        文件
        显示
        窗口
        帮助
        日 一 二 三 四 五 六
        3004388 2439
        上海浦左全桥路 2221年 RA1号 张酒
        1. 第一步
        2. 第二步
        IP: 192.168.1.1
        """
        let formatted = OCRTextFormatter.format(rawData)
        let lines = formatted.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "文件  显示  窗口  帮助")
        XCTAssertEqual(lines[1], "日 一 二 三 四 五 六")
        XCTAssertEqual(lines[2], "3004388 2439")
        XCTAssertEqual(lines[3], "上海浦左全桥路 2221年 RA1号 张酒")
        XCTAssertEqual(lines[4], "1. 第一步")
        XCTAssertEqual(lines[5], "2. 第二步")
        XCTAssertEqual(lines[6], "IP: 192.168.1.1")
    }

    func testOCRTextFormatterParagraphFlow() {
        let rawParagraph = """
        PasteLoom 是一款专为
        macOS 设计的剪贴板管理工具，
        支持全量历史回溯与智能 OCR 识别。
        """
        let formatted = OCRTextFormatter.format(rawParagraph)
        XCTAssertTrue(formatted.contains("专为 macOS 设计的剪贴板管理工具"))
    }

    func testOCRTextFormatterMetadataPackingAndFragmentedDetection() {
        let rawCard = """
        BlackBerry Passport App De...
        20d
        全部
        文本
        图像
        昨天 23:42
        562 x 600 110 KB
        文件
        收藏
        三 高级筛选
        """
        let formatted = OCRTextFormatter.formatIfFragmented(rawCard)
        XCTAssertTrue(formatted.contains("20d  全部  文本  图像"))
        XCTAssertTrue(formatted.contains("文件  收藏"))
    }
}
