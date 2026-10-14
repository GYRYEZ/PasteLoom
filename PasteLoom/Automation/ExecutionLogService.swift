import Foundation

struct ExecutionLog: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let timestamp: Date
    let title: String
    let status: String // "成功" or "失败" or "跳过"
    let durationMs: Double
    let detail: String

    init(id: UUID = UUID(), timestamp: Date = Date(), title: String, status: String, durationMs: Double = 0.0, detail: String) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.status = status
        self.durationMs = durationMs
        self.detail = detail
    }
}

@MainActor
final class ExecutionLogService: ObservableObject {
    static let shared = ExecutionLogService()

    @Published private(set) var logs: [ExecutionLog] = []

    private let maxLogs = 200

    init() {}

    func record(title: String, status: String, durationMs: Double = 0.0, detail: String) {
        let entry = ExecutionLog(title: title, status: status, durationMs: durationMs, detail: detail)
        logs.insert(entry, at: 0)
        if logs.count > maxLogs {
            logs = Array(logs.prefix(maxLogs))
        }
    }

    func clear() {
        logs.removeAll()
    }
}
