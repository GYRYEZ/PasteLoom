import SwiftUI

struct RulesAndScriptsView: View {
    @ObservedObject var ruleEngine = RuleEngine.shared
    @State private var scripts = ScriptSandbox.shared.loadScripts()
    let palette: PaperPalette

    @State private var showAddRuleSheet = false
    @State private var showScriptEditor = false
    @State private var editingScript: CustomScript? = nil

    @State private var testScriptInput = "{\"name\":\"PasteLoom\",\"type\":\"clipboard\",\"active\":true}"
    @State private var selectedScriptForTest: CustomScript? = nil
    @State private var scriptTestResult: ScriptExecutionResult? = nil
    @State private var isRunningTest = false

    init(palette: PaperPalette) {
        self.palette = palette
    }

    var body: some View {
        VStack(spacing: 22) {
            // MARK: - Automation Rules Section
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("自动化条件动作规则").font(.subheadline.weight(.semibold)).foregroundStyle(palette.secondaryText)
                    Spacer()
                    Button {
                        showAddRuleSheet = true
                    } label: {
                        Label("新建规则", systemImage: "plus")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }

                sectionCard {
                    if ruleEngine.rules.isEmpty {
                        Text("暂无自动化规则").font(.caption).foregroundStyle(palette.secondaryText).padding(16)
                    } else {
                        ForEach(ruleEngine.rules) { rule in
                            settingRow(rule.name, detail: ruleSummary(rule), icon: "bolt.fill") {
                                HStack(spacing: 12) {
                                    Toggle("", isOn: Binding(
                                        get: { rule.isEnabled },
                                        set: { _ in ruleEngine.toggleRule(id: rule.id) }
                                    )).labelsHidden()

                                    Button {
                                        ruleEngine.deleteRule(id: rule.id)
                                    } label: {
                                        Image(systemName: "trash").font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(palette.destructive)
                                }
                            }
                            if rule.id != ruleEngine.rules.last?.id {
                                rowDivider
                            }
                        }
                    }
                }
            }

            // MARK: - Scripts Sandbox Section
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("脚本执行沙盒与模板").font(.subheadline.weight(.semibold)).foregroundStyle(palette.secondaryText)
                    Spacer()
                    Button {
                        editingScript = CustomScript(name: "新建自定义脚本", code: "function transform(input) {\n    return input;\n}")
                        showScriptEditor = true
                    } label: {
                        Label("新建脚本", systemImage: "plus")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }

                sectionCard {
                    ForEach(scripts) { script in
                        settingRow(script.name, detail: script.isBuiltin ? "内置预设模板" : "自定义 JavaScript 脚本", icon: "applescript") {
                            HStack(spacing: 8) {
                                Button("测试") {
                                    selectedScriptForTest = script
                                    runQuickTest(script)
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)

                                Button("编辑") {
                                    editingScript = script
                                    showScriptEditor = true
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)

                                if !script.isBuiltin {
                                    Button {
                                        scripts.removeAll { $0.id == script.id }
                                        ScriptSandbox.shared.saveScripts(scripts)
                                    } label: {
                                        Image(systemName: "trash").font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(palette.destructive)
                                    .padding(.leading, 4)
                                }
                            }
                        }
                        if script.id != scripts.last?.id {
                            rowDivider
                        }
                    }
                }
            }

            // MARK: - Script Test Playground
            if let target = selectedScriptForTest {
                VStack(alignment: .leading, spacing: 9) {
                    Text("脚本实时调试台：\(target.name)").font(.subheadline.weight(.semibold)).foregroundStyle(palette.secondaryText)
                    sectionCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("测试输入：").font(.caption.weight(.semibold))
                            TextField("测试文本", text: $testScriptInput)
                                .textFieldStyle(.roundedBorder)

                            HStack {
                                Spacer()
                                Button("执行脚本") {
                                    runQuickTest(target)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isRunningTest)
                            }

                            if let res = scriptTestResult {
                                Text("输出结果 (\(String(format: "%.1f", res.durationMs)) ms)：").font(.caption.weight(.semibold))
                                Text(res.output)
                                    .font(.callout.monospaced())
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(palette.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))

                                if let err = res.error {
                                    Text("执行错误: \(err)").font(.caption).foregroundStyle(palette.destructive)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddRuleSheet) {
            AddRuleSheet(palette: palette) { newRule in
                ruleEngine.addRule(newRule)
                showAddRuleSheet = false
            } onDismiss: {
                showAddRuleSheet = false
            }
        }
        .sheet(isPresented: $showScriptEditor) {
            if let script = editingScript {
                ScriptEditorSheet(script: script, palette: palette) { updated in
                    if let index = scripts.firstIndex(where: { $0.id == updated.id }) {
                        scripts[index] = updated
                    } else {
                        scripts.append(updated)
                    }
                    ScriptSandbox.shared.saveScripts(scripts)
                    showScriptEditor = false
                } onDismiss: {
                    showScriptEditor = false
                }
            }
        }
    }

    private func runQuickTest(_ script: CustomScript) {
        isRunningTest = true
        Task {
            let res = await ScriptSandbox.shared.execute(code: script.code, input: testScriptInput)
            await MainActor.run {
                self.scriptTestResult = res
                self.isRunningTest = false
            }
        }
    }

    private func ruleSummary(_ rule: AutomationRule) -> String {
        let conds = rule.conditions.map { "\($0.type.rawValue) \($0.op.rawValue) '\($0.value)'" }.joined(separator: " 且 ")
        let acts = rule.actions.map { "\($0.type.rawValue) \($0.parameter.isEmpty ? "" : "(\($0.parameter))")" }.joined(separator: "，")
        return "条件: \(conds) -> 动作: \(acts)"
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.cardBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    private func settingRow<Content: View>(_ title: String, detail: String, icon: String,
                                           @ViewBuilder control: () -> Content) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(palette.accent)
                .frame(width: 36, height: 36)
                .background(palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(palette.secondaryText).lineLimit(2)
            }
            Spacer(minLength: 12)
            control()
        }
        .frame(minHeight: palette.rowHeight)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private var rowDivider: some View {
        Rectangle().fill(palette.divider).frame(height: 1).padding(.leading, 68)
    }
}

// MARK: - Execution Logs Page
struct ExecutionLogsView: View {
    @ObservedObject var logService = ExecutionLogService.shared
    let palette: PaperPalette

    init(palette: PaperPalette) {
        self.palette = palette
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("规则与脚本运行记录").font(.headline)
                    Text("记录剪贴板捕获触发的自动化规则与 JavaScript 沙盒运行详情")
                        .font(.caption).foregroundStyle(palette.secondaryText)
                }
                Spacer()
                Button("清空记录") {
                    logService.clear()
                }
                .buttonStyle(.bordered)
                .disabled(logService.logs.isEmpty)
            }

            if logService.logs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(palette.secondaryText)
                    Text("暂无运行记录").font(.subheadline).foregroundStyle(palette.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                VStack(spacing: 0) {
                    ForEach(logService.logs) { log in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: log.status == "成功" ? "checkmark.circle.fill" : log.status == "已跳过" ? "minus.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(log.status == "成功" ? palette.success : log.status == "已跳过" ? palette.secondaryText : palette.destructive)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(log.title).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    if log.durationMs > 0 {
                                        Text(String(format: "%.1f ms", log.durationMs))
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(palette.secondaryText)
                                    }
                                    Text(log.timestamp, format: .dateTime.hour().minute().second())
                                        .font(.caption).foregroundStyle(palette.secondaryText)
                                }
                                Text(log.detail)
                                    .font(.caption)
                                    .foregroundStyle(palette.secondaryText)
                            }
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        if log.id != logService.logs.last?.id {
                            Divider()
                        }
                    }
                }
                .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.cardBorder))
            }
        }
    }
}

// MARK: - Add Rule Sheet
private struct AddRuleSheet: View {
    let palette: PaperPalette
    let onSave: (AutomationRule) -> Void
    let onDismiss: () -> Void

    @State private var ruleName = ""
    @State private var conditionType: RuleConditionType = .text
    @State private var conditionOp: ConditionOperator = .contains
    @State private var conditionValue = ""

    @State private var actionType: RuleActionType = .addTag
    @State private var actionParam = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新建自动化规则").font(.title3.weight(.bold))

            TextField("规则名称（例如：链接自动打标）", text: $ruleName)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("匹配条件").font(.subheadline.weight(.semibold))
                HStack {
                    Picker("类型", selection: $conditionType) {
                        ForEach(RuleConditionType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(width: 100)

                    Picker("运算符", selection: $conditionOp) {
                        ForEach(ConditionOperator.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(width: 90)

                    TextField("条件值", text: $conditionValue)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("执行动作").font(.subheadline.weight(.semibold))
                HStack {
                    Picker("动作", selection: $actionType) {
                        ForEach(RuleActionType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(width: 140)

                    if actionType != .discard && actionType != .markFavorite && actionType != .markPinned && actionType != .markSnippet {
                        TextField("动作参数 (如标签名/分组名/脚本名)", text: $actionParam)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            HStack {
                Spacer()
                Button("取消") { onDismiss() }.buttonStyle(.bordered)
                Button("创建") {
                    let cond = RuleCondition(type: conditionType, op: conditionOp, value: conditionValue)
                    let act = RuleAction(type: actionType, parameter: actionParam)
                    let rule = AutomationRule(name: ruleName.isEmpty ? "未命名规则" : ruleName,
                                              conditions: [cond], actions: [act])
                    onSave(rule)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 440)
        .background(palette.background)
    }
}

// MARK: - Script Editor Sheet
private struct ScriptEditorSheet: View {
    @State var script: CustomScript
    let palette: PaperPalette
    let onSave: (CustomScript) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("编辑脚本").font(.title3.weight(.bold))
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(palette.secondaryText)
                }
                .buttonStyle(.plain)
            }

            TextField("脚本名称", text: $script.name)
                .textFieldStyle(.roundedBorder)

            Text("JavaScript 代码 (必须包含 transform(input) 函数)：")
                .font(.caption.weight(.semibold)).foregroundStyle(palette.secondaryText)

            TextEditor(text: $script.code)
                .font(.body.monospaced())
                .frame(minHeight: 240)
                .padding(6)
                .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.cardBorder))

            HStack {
                Spacer()
                Button("取消") { onDismiss() }.buttonStyle(.bordered)
                Button("保存") { onSave(script) }.buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 520, height: 420)
        .background(palette.background)
    }
}
