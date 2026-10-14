import Foundation
import JavaScriptCore

struct ScriptExecutionResult: Sendable, Equatable {
    let output: String
    let durationMs: Double
    let error: String?
    var isSuccess: Bool { error == nil }
}

struct CustomScript: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var code: String
    var isBuiltin: Bool

    init(id: UUID = UUID(), name: String, code: String, isBuiltin: Bool = false) {
        self.id = id
        self.name = name
        self.code = code
        self.isBuiltin = isBuiltin
    }
}

final class ScriptSandbox: @unchecked Sendable {
    static let shared = ScriptSandbox()

    private let storageKey = "custom_scripts_storage"

    static let defaultScripts: [CustomScript] = [
        CustomScript(
            name: "JSON 格式化",
            code: """
            function transform(input) {
                try {
                    var obj = JSON.parse(input);
                    return JSON.stringify(obj, null, 2);
                } catch(e) {
                    return input;
                }
            }
            """,
            isBuiltin: true
        ),
        CustomScript(
            name: "JSON 压缩",
            code: """
            function transform(input) {
                try {
                    var obj = JSON.parse(input);
                    return JSON.stringify(obj);
                } catch(e) {
                    return input;
                }
            }
            """,
            isBuiltin: true
        ),
        CustomScript(
            name: "Base64 编码",
            code: """
            function transform(input) {
                return btoa(unescape(encodeURIComponent(input)));
            }
            """,
            isBuiltin: true
        ),
        CustomScript(
            name: "Base64 解码",
            code: """
            function transform(input) {
                try {
                    return decodeURIComponent(escape(atob(input)));
                } catch(e) {
                    return input;
                }
            }
            """,
            isBuiltin: true
        ),
        CustomScript(
            name: "转为 snake_case",
            code: """
            function transform(input) {
                return input.replace(/([A-Z])/g, "_$1").toLowerCase().replace(/^_/, "").replace(/\\s+/g, "_");
            }
            """,
            isBuiltin: true
        ),
        CustomScript(
            name: "转为 camelCase",
            code: """
            function transform(input) {
                return input.toLowerCase().replace(/[^a-zA-Z0-9]+(.)/g, function(m, chr) {
                    return chr.toUpperCase();
                });
            }
            """,
            isBuiltin: true
        ),
        CustomScript(
            name: "URL 编码解码",
            code: """
            function transform(input) {
                try {
                    return decodeURIComponent(input);
                } catch(e) {
                    return input;
                }
            }
            """,
            isBuiltin: true
        ),
        CustomScript(
            name: "去除首尾空格与空行",
            code: """
            function transform(input) {
                return input.split('\\n')
                    .map(function(line) { return line.trim(); })
                    .filter(function(line) { return line.length > 0; })
                    .join('\\n');
            }
            """,
            isBuiltin: true
        )
    ]

    func loadScripts() -> [CustomScript] {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([CustomScript].self, from: data) {
            return saved
        }
        return Self.defaultScripts
    }

    func saveScripts(_ scripts: [CustomScript]) {
        if let data = try? JSONEncoder().encode(scripts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func execute(code: String, input: String) async -> ScriptExecutionResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                autoreleasepool {
                    guard let context = JSContext() else {
                        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
                        continuation.resume(returning: ScriptExecutionResult(output: input, durationMs: elapsed, error: "无法初始化 JavaScript 运行环境"))
                        return
                    }

                    // Inject polyfills (btoa, atob) for JavaScriptCore
                    let polyfills = """
                    function btoa(str) {
                        var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
                        var encoded = '';
                        for (var c1, c2, c3, e1, e2, e3, e4, n = 0; n < str.length;) {
                            c1 = str.charCodeAt(n++);
                            c2 = str.charCodeAt(n++);
                            c3 = str.charCodeAt(n++);
                            e1 = c1 >> 2;
                            e2 = ((c1 & 3) << 4) | (c2 >> 4);
                            e3 = ((c2 & 15) << 2) | (c3 >> 6);
                            e4 = c3 & 63;
                            if (isNaN(c2)) { e3 = e4 = 64; } else if (isNaN(c3)) { e4 = 64; }
                            encoded += chars.charAt(e1) + chars.charAt(e2) + chars.charAt(e3) + chars.charAt(e4);
                        }
                        return encoded;
                    }
                    function atob(input) {
                        var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
                        var str = input.replace(/=+$/, '');
                        var output = '';
                        if (str.length % 4 == 1) { throw new Error('Invalid Base64 string'); }
                        for (var bc = 0, bs = 0, buffer, idx = 0; buffer = str.charAt(idx++); ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer, bc++ % 4) ? output += String.fromCharCode(255 & bs >> (-2 * bc & 6)) : 0) {
                            buffer = chars.indexOf(buffer);
                        }
                        return output;
                    }
                    """
                    context.evaluateScript(polyfills)

                    var capturedError: String? = nil
                    context.exceptionHandler = { _, exception in
                        capturedError = exception?.toString() ?? "未知脚本异常"
                    }

                    context.evaluateScript(code)

                    if let err = capturedError {
                        context.exceptionHandler = nil
                        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
                        continuation.resume(returning: ScriptExecutionResult(output: input, durationMs: elapsed, error: err))
                        return
                    }

                    let transformFunc = context.objectForKeyedSubscript("transform")
                    guard let transformFunc, !transformFunc.isUndefined else {
                        context.exceptionHandler = nil
                        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
                        continuation.resume(returning: ScriptExecutionResult(output: input, durationMs: elapsed, error: "未找到 transform(input) 函数定义"))
                        return
                    }

                    let resultVal = transformFunc.call(withArguments: [input])
                    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
                    context.exceptionHandler = nil

                    if let err = capturedError {
                        continuation.resume(returning: ScriptExecutionResult(output: input, durationMs: elapsed, error: err))
                    } else if let str = resultVal?.toString() {
                        continuation.resume(returning: ScriptExecutionResult(output: str, durationMs: elapsed, error: nil))
                    } else {
                        continuation.resume(returning: ScriptExecutionResult(output: input, durationMs: elapsed, error: "脚本返回值不是字符串"))
                    }
                }
            }
        }
    }
}
