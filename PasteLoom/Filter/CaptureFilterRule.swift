import Foundation

enum TextMatchKind: String, Codable, CaseIterable, Sendable {
    case contains = "包含"
    case prefix = "前缀"
    case regex = "正则"
}

struct ExcludedApp: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var bundleIdentifier: String
    var name: String
    var isEnabled: Bool

    init(id: UUID = UUID(), bundleIdentifier: String, name: String, isEnabled: Bool = true) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.isEnabled = isEnabled
    }
}

struct ExcludedTextRule: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var pattern: String
    var matchKind: TextMatchKind
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, pattern: String, matchKind: TextMatchKind = .contains, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.matchKind = matchKind
        self.isEnabled = isEnabled
    }
}

@MainActor
final class CaptureFilterService: ObservableObject {
    static let shared = CaptureFilterService()

    @Published var excludedApps: [ExcludedApp] = [] {
        didSet { saveApps() }
    }
    @Published var excludedTextRules: [ExcludedTextRule] = [] {
        didSet { saveRules() }
    }

    private let appsKey = "capture_excluded_apps"
    private let rulesKey = "capture_excluded_text_rules"

    init() {
        loadRules()
    }

    private func loadRules() {
        if let data = UserDefaults.standard.data(forKey: appsKey),
           let apps = try? JSONDecoder().decode([ExcludedApp].self, from: data) {
            self.excludedApps = apps
        } else {
            // Default excluded apps: common password managers and privacy apps
            self.excludedApps = [
                ExcludedApp(bundleIdentifier: "com.agilebits.onepassword7", name: "1Password 7"),
                ExcludedApp(bundleIdentifier: "com.1password.1password", name: "1Password"),
                ExcludedApp(bundleIdentifier: "com.bitwarden.desktop", name: "Bitwarden"),
                ExcludedApp(bundleIdentifier: "com.apple.keychainaccess", name: "钥匙串访问 (Keychain)")
            ]
            saveApps()
        }

        if let data = UserDefaults.standard.data(forKey: rulesKey),
           let rules = try? JSONDecoder().decode([ExcludedTextRule].self, from: data) {
            self.excludedTextRules = rules
        } else {
            self.excludedTextRules = []
            saveRules()
        }
    }

    private func saveApps() {
        if let data = try? JSONEncoder().encode(excludedApps) {
            UserDefaults.standard.set(data, forKey: appsKey)
        }
    }

    private func saveRules() {
        if let data = try? JSONEncoder().encode(excludedTextRules) {
            UserDefaults.standard.set(data, forKey: rulesKey)
        }
    }

    func shouldExclude(app: CaptureSource?) -> Bool {
        guard let app else { return false }
        for rule in excludedApps where rule.isEnabled {
            if let bundleId = app.bundleIdentifier,
               !rule.bundleIdentifier.isEmpty,
               bundleId.localizedCaseInsensitiveContains(rule.bundleIdentifier) {
                return true
            }
            if !rule.name.isEmpty, app.name.localizedCaseInsensitiveContains(rule.name) {
                return true
            }
        }
        return false
    }

    func shouldExclude(text: String) -> Bool {
        guard !text.isEmpty else { return false }
        for rule in excludedTextRules where rule.isEnabled {
            switch rule.matchKind {
            case .contains:
                if text.localizedCaseInsensitiveContains(rule.pattern) { return true }
            case .prefix:
                if text.hasPrefix(rule.pattern) { return true }
            case .regex:
                if let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]) {
                    let range = NSRange(text.startIndex..., in: text)
                    if regex.firstMatch(in: text, options: [], range: range) != nil {
                        return true
                    }
                }
            }
        }
        return false
    }

    func addApp(bundleIdentifier: String, name: String) {
        let newApp = ExcludedApp(bundleIdentifier: bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                                 name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        excludedApps.append(newApp)
    }

    func removeApp(id: UUID) {
        excludedApps.removeAll { $0.id == id }
    }

    func toggleApp(id: UUID) {
        if let index = excludedApps.firstIndex(where: { $0.id == id }) {
            excludedApps[index].isEnabled.toggle()
        }
    }

    func addTextRule(name: String, pattern: String, matchKind: TextMatchKind) {
        let rule = ExcludedTextRule(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                    pattern: pattern.trimmingCharacters(in: .whitespacesAndNewlines),
                                    matchKind: matchKind)
        excludedTextRules.append(rule)
    }

    func removeTextRule(id: UUID) {
        excludedTextRules.removeAll { $0.id == id }
    }

    func toggleTextRule(id: UUID) {
        if let index = excludedTextRules.firstIndex(where: { $0.id == id }) {
            excludedTextRules[index].isEnabled.toggle()
        }
    }
}
