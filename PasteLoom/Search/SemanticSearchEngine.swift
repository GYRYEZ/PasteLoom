import Foundation
import NaturalLanguage

/// 本地端侧原生语义搜索与相关性排序引擎
/// 基于 Apple 原生 NaturalLanguage.framework，完全离线计算，不依赖任何网络服务
final class SemanticSearchEngine: @unchecked Sendable {
    static let shared = SemanticSearchEngine()

    private let lock = NSLock()
    private var _zhEmbeddingLoaded = false
    private var _zhEmbedding: NLEmbedding?
    private var zhEmbedding: NLEmbedding? {
        lock.lock()
        defer { lock.unlock() }
        if !_zhEmbeddingLoaded {
            _zhEmbedding = NLEmbedding.wordEmbedding(for: .simplifiedChinese)
            _zhEmbeddingLoaded = true
        }
        return _zhEmbedding
    }

    private var _enEmbeddingLoaded = false
    private var _enEmbedding: NLEmbedding?
    private var enEmbedding: NLEmbedding? {
        lock.lock()
        defer { lock.unlock() }
        if !_enEmbeddingLoaded {
            _enEmbedding = NLEmbedding.wordEmbedding(for: .english)
            _enEmbeddingLoaded = true
        }
        return _enEmbedding
    }

    private var memorySource: (any DispatchSourceMemoryPressure)?

    init() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            self?.releaseEmbeddings()
        }
        source.resume()
        self.memorySource = source
    }

    deinit {
        memorySource?.cancel()
    }

    func releaseEmbeddings() {
        lock.lock()
        defer { lock.unlock() }
        _zhEmbedding = nil
        _zhEmbeddingLoaded = false
        _enEmbedding = nil
        _enEmbeddingLoaded = false
    }

    /// 分词并提取语义关键词
    func extractTokens(from text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if word.count >= 2 || (word.count == 1 && word.range(of: "\\p{Han}", options: .regularExpression) != nil) {
                tokens.append(word)
            }
            return true
        }
        return tokens
    }

    /// 计算两个词项之间的语义相似度 (0.0 ~ 1.0)
    func wordSimilarity(_ w1: String, _ w2: String) -> Double {
        if w1 == w2 { return 1.0 }
        if w1.contains(w2) || w2.contains(w1) { return 0.85 }

        var maxSim = 0.0
        if let zh = zhEmbedding {
            let distance = zh.distance(between: w1, and: w2)
            if distance < 2.0 {
                maxSim = max(maxSim, max(0.0, 1.0 - (distance / 2.0)))
            }
        }
        if let en = enEmbedding {
            let distance = en.distance(between: w1, and: w2)
            if distance < 2.0 {
                maxSim = max(maxSim, max(0.0, 1.0 - (distance / 2.0)))
            }
        }
        return maxSim
    }

    /// 计算单条条目与查询词的语义相关度评分 (0.0 ~ 1.0)
    func relevanceScore(item: HistoryItem, query: String) -> Double {
        let queryTokens = extractTokens(from: query)
        guard !queryTokens.isEmpty else { return 0.0 }

        // 构建条目的完整语义文本（正文 + OCR识别字 + 标签 + 来源应用）
        var corpus = item.text
        if let ocr = item.ocrText, !ocr.isEmpty {
            corpus += " " + ocr
        }
        if !item.tags.isEmpty {
            corpus += " " + item.tags.joined(separator: " ")
        }
        if let source = item.sourceName {
            corpus += " " + source
        }

        let corpusLower = corpus.lowercased()
        let queryLower = query.lowercased()

        // 1. 完全包含直接赋较高基础分
        var baseScore = 0.0
        if corpusLower.contains(queryLower) {
            baseScore += 0.5
        }

        // 2. 词元语义向量关联计算
        let itemTokens = extractTokens(from: corpus)
        guard !itemTokens.isEmpty else { return baseScore }

        var tokenMatchScores: [Double] = []
        for qToken in queryTokens {
            var bestTokenSim = 0.0
            for iToken in itemTokens {
                let sim = wordSimilarity(qToken, iToken)
                if sim > bestTokenSim {
                    bestTokenSim = sim
                }
                if bestTokenSim >= 0.99 { break }
            }
            tokenMatchScores.append(bestTokenSim)
        }

        let avgTokenSim = tokenMatchScores.reduce(0.0, +) / Double(tokenMatchScores.count)
        var totalScore = baseScore + (avgTokenSim * 0.5)

        // 3. 置顶与收藏微调权重
        if item.isPinned { totalScore += 0.05 }
        if item.isFavorite { totalScore += 0.03 }

        return min(1.0, totalScore)
    }

    /// 对条目集合进行本地语义排序
    func rank(items: [HistoryItem], query: String) -> [HistoryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        let scored = items.map { item in
            (item: item, score: relevanceScore(item: item, query: trimmed))
        }

        // 过滤并按评分从高到低排序，同分则按置顶与时间降序
        return scored
            .filter { $0.score > 0.15 || $0.item.text.localizedCaseInsensitiveContains(trimmed) }
            .sorted { lhs, rhs in
                if abs(lhs.score - rhs.score) > 0.05 {
                    return lhs.score > rhs.score
                }
                if lhs.item.isPinned != rhs.item.isPinned {
                    return lhs.item.isPinned && !rhs.item.isPinned
                }
                return lhs.item.capturedAt > rhs.item.capturedAt
            }
            .map(\.item)
    }
}
