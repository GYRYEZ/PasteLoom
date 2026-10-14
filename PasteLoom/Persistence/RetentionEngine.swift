import Foundation

struct RetentionReport: Sendable, Equatable {
    let purgedItemsCount: Int
    let executedAt: Date
}

@MainActor
final class RetentionEngine: ObservableObject {
    static let shared = RetentionEngine()

    @Published var retentionDays: Int {
        didSet { UserDefaults.standard.set(retentionDays, forKey: "retentionDays") }
    }
    @Published var trashRetentionDays: Int {
        didSet { UserDefaults.standard.set(trashRetentionDays, forKey: "trashRetentionDays") }
    }
    @Published var autoRunEnabled: Bool {
        didSet { UserDefaults.standard.set(autoRunEnabled, forKey: "autoRetentionEnabled") }
    }
    @Published var lastReport: RetentionReport?

    private let defaults = UserDefaults.standard

    init() {
        let storedDays = defaults.object(forKey: "retentionDays") as? Int ?? 30
        let storedTrash = defaults.object(forKey: "trashRetentionDays") as? Int ?? 7
        let storedAuto = defaults.object(forKey: "autoRetentionEnabled") as? Bool ?? true

        self.retentionDays = storedDays
        self.trashRetentionDays = storedTrash
        self.autoRunEnabled = storedAuto
    }

    func checkAndRunPeriodicRetention(repository: HistoryRepository) async {
        guard autoRunEnabled else { return }
        let lastRun = defaults.double(forKey: "lastRetentionRunTimestamp")
        let now = Date().timeIntervalSince1970
        // Run once every 24 hours (86400 seconds)
        if now - lastRun >= 86400 {
            _ = try? await runRetentionNow(repository: repository)
        }
    }

    @discardableResult
    func runRetentionNow(repository: HistoryRepository) async throws -> RetentionReport {
        let purged = try await repository.runRetention(retentionDays: retentionDays,
                                                        trashRetentionDays: trashRetentionDays)
        defaults.set(Date().timeIntervalSince1970, forKey: "lastRetentionRunTimestamp")
        let report = RetentionReport(purgedItemsCount: purged, executedAt: Date())
        self.lastReport = report
        return report
    }
}
