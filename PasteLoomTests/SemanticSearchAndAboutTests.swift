import XCTest
@testable import PasteLoom

final class SemanticSearchAndAboutTests: XCTestCase {

    func testSemanticSearchTokenExtraction() {
        let engine = SemanticSearchEngine.shared
        let tokensZh = engine.extractTokens(from: "苹果 手机 剪贴板 设计")
        XCTAssertTrue(tokensZh.contains("苹果") || tokensZh.contains("手机") || tokensZh.contains("剪贴板"))

        let tokensEn = engine.extractTokens(from: "Quick brown fox jumps over lazy dog")
        XCTAssertTrue(tokensEn.contains("quick"))
        XCTAssertTrue(tokensEn.contains("brown"))
    }

    func testSemanticWordSimilarity() {
        let engine = SemanticSearchEngine.shared
        // 相同词相似度应为 1.0
        let identical = engine.wordSimilarity("swift", "swift")
        XCTAssertEqual(identical, 1.0, accuracy: 0.001)

        // 包含词相似度应较高
        let substringSim = engine.wordSimilarity("database", "base")
        XCTAssertGreaterThanOrEqual(substringSim, 0.8)
    }

    func testSemanticRelevanceAndRanking() {
        let engine = SemanticSearchEngine.shared
        let item1 = HistoryItem(
            id: UUID(),
            kind: .text,
            text: "macOS 应用程序开发与 Swift 编程指南",
            capturedAt: Date().addingTimeInterval(-100),
            imageRelativePath: nil,
            contentHash: "hash1",
            files: [],
            isFavorite: false,
            isPinned: false,
            isDeleted: false,
            tags: ["编程", "开发"],
            sourceName: "Xcode"
        )

        let item2 = HistoryItem(
            id: UUID(),
            kind: .text,
            text: "晚餐菜单：番茄炒蛋与清蒸鲈鱼配米饭",
            capturedAt: Date().addingTimeInterval(-200),
            imageRelativePath: nil,
            contentHash: "hash2",
            files: [],
            isFavorite: false,
            isPinned: false,
            isDeleted: false,
            tags: ["美食"],
            sourceName: "Safari"
        )

        let scoreCode = engine.relevanceScore(item: item1, query: "Swift 开发")
        let scoreFood = engine.relevanceScore(item: item2, query: "Swift 开发")

        XCTAssertGreaterThan(scoreCode, scoreFood)

        let ranked = engine.rank(items: [item2, item1], query: "Swift 开发")
        XCTAssertEqual(ranked.first?.id, item1.id)
    }

    func testSearchModeEnumCases() {
        let allModes = HistorySearchMode.allCases
        XCTAssertTrue(allModes.contains(.fullText))
        XCTAssertTrue(allModes.contains(.semantic))
        XCTAssertTrue(allModes.contains(.tags))
        XCTAssertEqual(HistorySearchMode.semantic.rawValue, "semantic")
    }
}
