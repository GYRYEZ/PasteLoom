import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case zh = "zh-Hans"
    case en = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "跟随系统 (System Default)"
        case .zh: "简体中文"
        case .en: "English"
        }
    }
}

@MainActor
final class LocalizationService: ObservableObject {
    static let shared = LocalizationService()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "app_language") }
    }

    private let localizedStrings: [String: [AppLanguage: String]] = [
        "app.name": [.zh: "PasteLoom", .en: "PasteLoom"],
        "history.title": [.zh: "剪贴板历史", .en: "Clipboard History"],
        "quickpaste.title": [.zh: "快速粘贴", .en: "Quick Paste"],
        "search.placeholder": [.zh: "搜索剪贴板历史...", .en: "Search history..."],
        "filter.all": [.zh: "全部", .en: "All"],
        "filter.favorites": [.zh: "收藏", .en: "Favorites"],
        "filter.trash": [.zh: "废纸篓", .en: "Trash"],
        "card.pin": [.zh: "置顶", .en: "Pin"],
        "card.unpin": [.zh: "取消置顶", .en: "Unpin"],
        "card.copy": [.zh: "复制", .en: "Copy"],
        "card.paste": [.zh: "粘贴", .en: "Paste"],
        "settings.title": [.zh: "设置", .en: "Settings"],
        "settings.general": [.zh: "通用", .en: "General"],
        "settings.keyboard": [.zh: "快捷键", .en: "Shortcuts"],
        "settings.screenshot": [.zh: "截图", .en: "Screenshots"],
        "settings.scripts": [.zh: "脚本", .en: "Scripts"],
        "settings.ai": [.zh: "AI", .en: "AI"],
        "settings.data": [.zh: "数据", .en: "Data"],
        "settings.sync": [.zh: "同步", .en: "Sync"],
        "settings.backup": [.zh: "导入与导出", .en: "Import & Export"]
    ]

    private init() {
        let stored = UserDefaults.standard.string(forKey: "app_language") ?? "system"
        self.language = AppLanguage(rawValue: stored) ?? .system
    }

    func string(_ key: String) -> String {
        let targetLang: AppLanguage
        if language == .system {
            let preferred = Locale.preferredLanguages.first ?? "zh"
            targetLang = preferred.starts(with: "zh") ? .zh : .en
        } else {
            targetLang = language
        }

        return localizedStrings[key]?[targetLang] ?? key
    }
}
