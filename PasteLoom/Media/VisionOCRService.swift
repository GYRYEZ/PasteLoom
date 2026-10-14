import AppKit
import Foundation
import Vision

enum VisionOCRError: LocalizedError {
    case invalidImageData
    case noTextFound
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImageData: "无法解析图片数据以进行文字识别。"
        case .noTextFound: "图片中未识别到有效文字。"
        case .processingFailed(let message): "文字识别失败：\(message)"
        }
    }
}

final class VisionOCRService: Sendable {
    static let shared = VisionOCRService()

    func recognizeText(from imageData: Data) async throws -> String {
        let cgImage: CGImage = try autoreleasepool {
            if let source = CGImageSourceCreateWithData(imageData as CFData, nil),
               let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                return cg
            }
            if let rep = NSBitmapImageRep(data: imageData), let cg = rep.cgImage {
                return cg
            }
            if let image = NSImage(data: imageData),
               let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return cg
            }
            throw VisionOCRError.invalidImageData
        }
        return try await recognizeText(from: cgImage)
    }

    func recognizeText(from cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            autoreleasepool {
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: VisionOCRError.processingFailed(error.localizedDescription))
                        return
                    }
                    guard let observations = request.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(returning: "")
                        return
                    }
                    let formatted = OCRTextFormatter.assembleAndFormat(observations: observations)
                    continuation.resume(returning: formatted)
                }

                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: VisionOCRError.processingFailed(error.localizedDescription))
                }
            }
        }
    }
}

/// OCR 文本智能排版与几何重组引擎
public struct OCRTextFormatter: Sendable {
    public static func isCJK(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        return (scalar.value >= 0x4E00 && scalar.value <= 0x9FFF) ||
               (scalar.value >= 0x3400 && scalar.value <= 0x4DBF) ||
               (scalar.value >= 0xF900 && scalar.value <= 0xFAFF)
    }

    public static func isSentenceTerminator(_ s: String) -> Bool {
        guard let last = s.last else { return false }
        return "。！？!?…；;".contains(last)
    }

    public static func isColonOrHeader(_ s: String) -> Bool {
        guard let last = s.last else { return false }
        return "：:".contains(last)
    }

    public static func isListItem(_ s: String) -> Bool {
        let pattern = #"^(?:[0-9]+[\.\)、]|[•\-\*\+①②③④⑤⑥⑦⑧⑨⑩]|\([0-9a-zA-Z]+\))\s*"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }

    public static func isKeyValue(_ s: String) -> Bool {
        let pattern = #"^[A-Za-z0-9_\u4e00-\u9fa5\s]{1,16}[:：]"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }

    public static func isStandaloneDataRecord(_ s: String) -> Bool {
        let parts = s.split(separator: " ")
        if parts.count >= 4 && parts.allSatisfy({ $0.count <= 2 }) {
            return true
        }
        let stripped = s.replacingOccurrences(of: " ", with: "")
                        .replacingOccurrences(of: "-", with: "")
                        .replacingOccurrences(of: "+", with: "")
        if !stripped.isEmpty && stripped.allSatisfy(\.isNumber) && stripped.count >= 5 {
            return true
        }
        return false
    }

    public static func isShortTagLine(_ s: String) -> Bool {
        let count = s.count
        guard count >= 1 && count <= 14 else { return false }
        if isSentenceTerminator(s) || isColonOrHeader(s) || isListItem(s) || isKeyValue(s) || isStandaloneDataRecord(s) {
            return false
        }
        return true
    }

    public static func isInlineMetadataOrItem(_ s: String) -> Bool {
        if isStandaloneDataRecord(s) || isListItem(s) || isKeyValue(s) || isSentenceTerminator(s) || isColonOrHeader(s) {
            return false
        }
        if isShortTagLine(s) { return true }
        if ("•·x×".contains(where: { s.contains($0) }) || s.contains("KB") || s.contains("MB") || s.contains("GB")) && s.count <= 28 {
            return true
        }
        return false
    }

    /// 如果文本具有大量碎片化断行（如 OCR 提取文本或标签清单），则智能格式化；否则保持原样（如代码块、长文章）
    public static func formatIfFragmented(_ raw: String) -> String {
        let lines = raw.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count >= 2 else { return raw }
        let shortLines = lines.filter { isInlineMetadataOrItem($0) }
        if Double(shortLines.count) / Double(lines.count) >= 0.45 {
            return format(raw)
        }
        return raw
    }

    /// 对纯文本形式的 OCR 结果进行段落与短标签智能重组
    public static func format(_ raw: String) -> String {
        let rawLines = raw.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var cleaned: [String] = []
        for line in rawLines {
            if !line.isEmpty {
                cleaned.append(line)
            } else if let last = cleaned.last, !last.isEmpty {
                cleaned.append("")
            }
        }
        guard !cleaned.isEmpty else { return "" }

        var result: [String] = []
        var i = 0

        while i < cleaned.count {
            let line = cleaned[i]

            if line.isEmpty {
                result.append("")
                i += 1
                continue
            }

            // 模式 1：连续短行（菜单项、导航栏标签、状态标、星期表头、元数据条等），合并为同行紧凑排版
            if isInlineMetadataOrItem(line) {
                var group = [line]
                var j = i + 1
                while j < cleaned.count && isInlineMetadataOrItem(cleaned[j]) {
                    group.append(cleaned[j])
                    j += 1
                }
                if group.count >= 2 {
                    var currentPacked: [String] = []
                    var currentLen = 0
                    for item in group {
                        let itemLen = item.count
                        if currentLen + itemLen + 2 > 42 && !currentPacked.isEmpty {
                            result.append(currentPacked.joined(separator: "  "))
                            currentPacked = [item]
                            currentLen = itemLen
                        } else {
                            currentPacked.append(item)
                            currentLen += itemLen + 2
                        }
                    }
                    if !currentPacked.isEmpty {
                        result.append(currentPacked.joined(separator: "  "))
                    }
                    i = j
                    continue
                }
            }

            // 模式 2：列表项、键值对、独立数据记录（电话、星期行、带冒号标题），保持独立单行
            if isListItem(line) || isKeyValue(line) || isColonOrHeader(line) || isStandaloneDataRecord(line) {
                result.append(line)
                i += 1
                continue
            }

            // 模式 3：自然段落跨行流动折行合并
            if let last = result.last, !last.isEmpty {
                let canMerge = !isSentenceTerminator(last) &&
                               !isColonOrHeader(last) &&
                               !isListItem(last) &&
                               !isKeyValue(last) &&
                               !isStandaloneDataRecord(last) &&
                               !last.contains("  ") &&
                               (last.count >= 14 || last.hasSuffix("，") || last.hasSuffix(",")) &&
                               !isStandaloneDataRecord(line) &&
                               !isListItem(line) &&
                               !isKeyValue(line)

                if canMerge {
                    let isLastCJK = last.last.map { isCJK($0) } ?? false
                    let isCurrCJK = line.first.map { isCJK($0) } ?? false
                    if isLastCJK && isCurrCJK {
                        result[result.count - 1] = last + line
                    } else {
                        result[result.count - 1] = last + " " + line
                    }
                    i += 1
                    continue
                }
            }

            result.append(line)
            i += 1
        }

        return result.joined(separator: "\n")
    }

    private struct OCRToken {
        let text: String
        let box: CGRect
    }

    private struct OCRLine {
        var tokens: [OCRToken]

        var midY: CGFloat {
            let sum = tokens.reduce(0.0) { $0 + $1.box.midY }
            return sum / CGFloat(max(1, tokens.count))
        }

        var avgHeight: CGFloat {
            let sum = tokens.reduce(0.0) { $0 + $1.box.height }
            return sum / CGFloat(max(1, tokens.count))
        }
    }

    /// 基于 Vision 识别项的几何坐标（BoundingBox）按水平行聚类、从上至下从左至右排序并智能拼装
    public static func assembleAndFormat(observations: [VNRecognizedTextObservation]) -> String {
        let rawTokens: [OCRToken] = observations.compactMap { obs in
            guard let str = obs.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines),
                  !str.isEmpty else { return nil }
            return OCRToken(text: str, box: obs.boundingBox)
        }

        guard !rawTokens.isEmpty else { return "" }

        // 1. 从上往下粗排（Vision 坐标系 y=1 为顶部，因此降序）
        let sortedTokens = rawTokens.sorted { $0.box.midY > $1.box.midY }

        // 2. 聚类为几何水平行
        var lines: [OCRLine] = []
        for token in sortedTokens {
            if let lineIdx = lines.firstIndex(where: { line in
                let diff = abs(line.midY - token.box.midY)
                let tolerance = max(line.avgHeight, token.box.height) * 0.85
                return diff <= tolerance
            }) {
                lines[lineIdx].tokens.append(token)
            } else {
                lines.append(OCRLine(tokens: [token]))
            }
        }

        // 3. 行按纵向 midY 从上往下排序
        lines.sort { $0.midY > $1.midY }

        // 4. 每行内部从左至右排序并根据距离拼装
        var assembledLines: [String] = []
        for i in 0..<lines.count {
            lines[i].tokens.sort { $0.box.minX < $1.box.minX }

            var lineStr = ""
            for (idx, token) in lines[i].tokens.enumerated() {
                if idx == 0 {
                    lineStr = token.text
                } else {
                    let prev = lines[i].tokens[idx - 1]
                    let gap = token.box.minX - prev.box.maxX
                    let isPrevCJK = prev.text.last.map { isCJK($0) } ?? false
                    let isCurrCJK = token.text.first.map { isCJK($0) } ?? false

                    if gap > lines[i].avgHeight * 0.8 {
                        lineStr += "  " + token.text
                    } else if isPrevCJK && isCurrCJK && gap <= lines[i].avgHeight * 0.25 {
                        lineStr += token.text
                    } else {
                        lineStr += " " + token.text
                    }
                }
            }
            if !lineStr.isEmpty {
                assembledLines.append(lineStr)
            }
        }

        // 5. 应用段落与短词排版规则
        return format(assembledLines.joined(separator: "\n"))
    }
}
