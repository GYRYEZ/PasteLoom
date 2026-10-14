import Foundation

enum ConditionOperator: String, Codable, CaseIterable, Sendable {
    case contains = "包含"
    case equals = "等于"
    case matchesRegex = "正则匹配"
    case hasPrefix = "前缀为"
    case hasSuffix = "后缀为"
}

enum RuleConditionType: String, Codable, CaseIterable, Sendable {
    case text = "文本内容"
    case sourceApp = "来源应用"
    case kind = "内容类型"
    case textLength = "文本长度大于"
}

struct RuleCondition: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var type: RuleConditionType
    var op: ConditionOperator
    var value: String

    init(id: UUID = UUID(), type: RuleConditionType = .text, op: ConditionOperator = .contains, value: String = "") {
        self.id = id
        self.type = type
        self.op = op
        self.value = value
    }

    func matches(text: String, source: CaptureSource?, kind: HistoryKind) -> Bool {
        switch type {
        case .text:
            return matchesString(text, op: op, target: value)
        case .sourceApp:
            let appName = source?.name ?? ""
            let bundleId = source?.bundleIdentifier ?? ""
            return matchesString(appName, op: op, target: value) || matchesString(bundleId, op: op, target: value)
        case .kind:
            return kind.rawValue.localizedCaseInsensitiveContains(value)
        case .textLength:
            let targetLen = Int(value) ?? 0
            return text.count > targetLen
        }
    }

    private func matchesString(_ candidate: String, op: ConditionOperator, target: String) -> Bool {
        guard !target.isEmpty else { return true }
        switch op {
        case .contains:
            return candidate.localizedCaseInsensitiveContains(target)
        case .equals:
            return candidate.caseInsensitiveCompare(target) == .orderedSame
        case .hasPrefix:
            return candidate.hasPrefix(target)
        case .hasSuffix:
            return candidate.hasSuffix(target)
        case .matchesRegex:
            guard let regex = try? NSRegularExpression(pattern: target, options: [.caseInsensitive]) else { return false }
            return regex.firstMatch(in: candidate, options: [], range: NSRange(candidate.startIndex..., in: candidate)) != nil
        }
    }
}

enum RuleActionType: String, Codable, CaseIterable, Sendable {
    case addTag = "自动添加标签"
    case setGroup = "自动移至分组"
    case markFavorite = "标为收藏"
    case markPinned = "标为置顶"
    case markSnippet = "设为常用片段"
    case runScript = "运行脚本处理"
    case discard = "静默丢弃 (不保存)"
}

struct RuleAction: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var type: RuleActionType
    var parameter: String

    init(id: UUID = UUID(), type: RuleActionType = .addTag, parameter: String = "") {
        self.id = id
        self.type = type
        self.parameter = parameter
    }
}

struct AutomationRule: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var conditions: [RuleCondition]
    var actions: [RuleAction]

    init(id: UUID = UUID(), name: String, isEnabled: Bool = true, conditions: [RuleCondition] = [], actions: [RuleAction] = []) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.conditions = conditions
        self.actions = actions
    }

    func matches(text: String, source: CaptureSource?, kind: HistoryKind) -> Bool {
        guard isEnabled, !conditions.isEmpty else { return false }
        for cond in conditions {
            if !cond.matches(text: text, source: source, kind: kind) {
                return false
            }
        }
        return true
    }
}

@MainActor
final class RuleEngine: ObservableObject {
    static let shared = RuleEngine()

    @Published var rules: [AutomationRule] = [] {
        didSet { saveRules() }
    }

    private let rulesStorageKey = "automation_rules_storage"

    init() {
        loadRules()
    }

    private func loadRules() {
        if let data = UserDefaults.standard.data(forKey: rulesStorageKey),
           let saved = try? JSONDecoder().decode([AutomationRule].self, from: data) {
            self.rules = saved
        } else {
            // Built-in starter rules
            self.rules = [
                AutomationRule(
                    name: "自动标记链接",
                    isEnabled: true,
                    conditions: [RuleCondition(type: .text, op: .hasPrefix, value: "http")],
                    actions: [RuleAction(type: .addTag, parameter: "链接")]
                ),
                AutomationRule(
                    name: "代码片段归类",
                    isEnabled: true,
                    conditions: [
                        RuleCondition(type: .text, op: .contains, value: "func "),
                        RuleCondition(type: .text, op: .contains, value: "import ")
                    ],
                    actions: [
                        RuleAction(type: .setGroup, parameter: "代码"),
                        RuleAction(type: .addTag, parameter: "代码")
                    ]
                )
            ]
            saveRules()
        }
    }

    private func saveRules() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: rulesStorageKey)
        }
    }

    func addRule(_ rule: AutomationRule) {
        rules.append(rule)
    }

    func updateRule(_ rule: AutomationRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        }
    }

    func deleteRule(id: UUID) {
        rules.removeAll { $0.id == id }
    }

    func toggleRule(id: UUID) {
        if let index = rules.firstIndex(where: { $0.id == id }) {
            rules[index].isEnabled.toggle()
        }
    }

    struct EvaluationOutcome: Sendable {
        var shouldDiscard: Bool = false
        var tagsToAdd: Set<String> = []
        var groupToSet: String? = nil
        var markFavorite: Bool = false
        var markPinned: Bool = false
        var markSnippet: Bool = false
        var matchedRuleNames: [String] = []
        var scriptNamesToRun: [String] = []
    }

    func evaluate(text: String, source: CaptureSource?, kind: HistoryKind) -> EvaluationOutcome {
        var outcome = EvaluationOutcome()
        for rule in rules where rule.isEnabled {
            if rule.matches(text: text, source: source, kind: kind) {
                outcome.matchedRuleNames.append(rule.name)
                for action in rule.actions {
                    switch action.type {
                    case .discard:
                        outcome.shouldDiscard = true
                    case .addTag:
                        let tag = action.parameter.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !tag.isEmpty { outcome.tagsToAdd.insert(tag) }
                    case .setGroup:
                        let grp = action.parameter.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !grp.isEmpty { outcome.groupToSet = grp }
                    case .markFavorite:
                        outcome.markFavorite = true
                    case .markPinned:
                        outcome.markPinned = true
                    case .markSnippet:
                        outcome.markSnippet = true
                    case .runScript:
                        let script = action.parameter.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !script.isEmpty { outcome.scriptNamesToRun.append(script) }
                    }
                }
            }
        }
        return outcome
    }
}
