import Foundation

enum SensitiveKind: String, CaseIterable, Sendable {
    case phone = "手机号"
    case email = "电子邮箱"
    case idCard = "身份证号"
    case bankCard = "银行卡号"
    case apiKey = "API 密钥 / Token"
}

struct SensitiveMaskResult: Sendable {
    let maskedText: String
    let detectedKinds: Set<SensitiveKind>
    var hasSensitive: Bool { !detectedKinds.isEmpty }
}

final class SensitiveContentService: Sendable {
    static let shared = SensitiveContentService()

    var isMaskingEnabled: Bool {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: "sensitive_masking_enabled") != nil else { return true }
            return defaults.bool(forKey: "sensitive_masking_enabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "sensitive_masking_enabled") }
    }

    // Precompiled regex patterns
    private let phoneRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"(?:\+?86)?\b(1[3-9]\d)(\d{4})(\d{4})\b"#)
    }()

    private let emailRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\b([A-Za-z0-9._%+-]{1,3})[A-Za-z0-9._%+-]*(@[A-Za-z0-9.-]+\.[A-Za-z]{2,})\b"#)
    }()

    private let idCardRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\b(\d{6})(?:\d{8})(\d{3}[\dXx])\b"#)
    }()

    private let bankCardRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\b(\d{4})(\d{8,11})(\d{4})\b"#)
    }()

    private let apiKeyRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\b(sk-[A-Za-z0-9]{3})[A-Za-z0-9]{15,}|(ghp_[A-Za-z0-9]{3})[A-Za-z0-9]{15,}|(glpat-[A-Za-z0-9\-]{3})[A-Za-z0-9\-]{15,}|(Bearer\s+[A-Za-z0-9._\-]{4})[A-Za-z0-9._\-]{16,}\b"#)
    }()

    func mask(_ text: String) -> String {
        mask(text: text).maskedText
    }

    func containsSensitiveContent(_ text: String) -> Bool {
        mask(text: text).hasSensitive
    }

    func mask(text: String) -> SensitiveMaskResult {
        guard !text.isEmpty else {
            return SensitiveMaskResult(maskedText: text, detectedKinds: [])
        }

        var result = text
        var kinds = Set<SensitiveKind>()

        // Mask Phone: 13812345678 -> 138****5678
        if let phoneRegex {
            let matches = phoneRegex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))
            if !matches.isEmpty {
                kinds.insert(.phone)
                result = phoneRegex.stringByReplacingMatches(in: result, options: [],
                                                            range: NSRange(result.startIndex..., in: result),
                                                            withTemplate: "$1****$3")
            }
        }

        // Mask Email: test@example.com -> tes***@example.com
        if let emailRegex {
            let matches = emailRegex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))
            if !matches.isEmpty {
                kinds.insert(.email)
                result = emailRegex.stringByReplacingMatches(in: result, options: [],
                                                            range: NSRange(result.startIndex..., in: result),
                                                            withTemplate: "$1***$2")
            }
        }

        // Mask ID Card: 110101199003072345 -> 110101********2345
        if let idCardRegex {
            let matches = idCardRegex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))
            if !matches.isEmpty {
                kinds.insert(.idCard)
                result = idCardRegex.stringByReplacingMatches(in: result, options: [],
                                                             range: NSRange(result.startIndex..., in: result),
                                                             withTemplate: "$1********$2")
            }
        }

        // Mask Bank Card: 6222021234567890 -> 6222********7890
        if let bankCardRegex {
            let matches = bankCardRegex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))
            if !matches.isEmpty {
                kinds.insert(.bankCard)
                result = bankCardRegex.stringByReplacingMatches(in: result, options: [],
                                                               range: NSRange(result.startIndex..., in: result),
                                                               withTemplate: "$1********$3")
            }
        }

        // Mask API Keys / Tokens: sk-abc12345... -> sk-abc*** (Masked Token)
        if let apiKeyRegex {
            let matches = apiKeyRegex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))
            if !matches.isEmpty {
                kinds.insert(.apiKey)
                // Process in reverse to maintain string index validity
                for match in matches.reversed() {
                    if let range = Range(match.range, in: result) {
                        let matchedStr = String(result[range])
                        if matchedStr.hasPrefix("Bearer ") {
                            let tokenPart = String(matchedStr.dropFirst(7))
                            let subPrefix = String(tokenPart.prefix(6))
                            result.replaceSubrange(range, with: "Bearer \(subPrefix)****************")
                        } else {
                            let prefix = String(matchedStr.prefix(6))
                            result.replaceSubrange(range, with: "\(prefix)****************")
                        }
                    }
                }
            }
        }

        return SensitiveMaskResult(maskedText: result, detectedKinds: kinds)
    }
}
