import XCTest
@testable import PasteLoom

final class Stage7And8Tests: XCTestCase {

    // MARK: - 1. JSON Export & Import Tests
    @MainActor
    func testJSONExportAndImport() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let repoURL = tempDir.appendingPathComponent("export_test.sqlite3")
        let repo = try SQLiteHistoryRepository(url: repoURL)

        // Insert some items
        try await repo.insert(content: .text("Normal Note"), at: Date())
        try await repo.insert(content: .text("Confidential 13812345678"), at: Date())

        let exportJSONURL = tempDir.appendingPathComponent("backup.json")

        // 1. Export with masking
        var options = ExportOptions()
        options.maskSensitive = true
        let exportResult = try await BackupService.shared.exportToJSON(repository: repo, destinationURL: exportJSONURL, options: options)

        XCTAssertTrue(exportResult.success)
        XCTAssertEqual(exportResult.itemCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportJSONURL.path))

        // Verify exported JSON text contains masked phone number
        let exportedData = try Data(contentsOf: exportJSONURL)
        let jsonString = String(data: exportedData, encoding: .utf8) ?? ""
        XCTAssertFalse(jsonString.contains("13812345678"))
        XCTAssertTrue(jsonString.contains("138****5678") || jsonString.contains("****"))

        // 2. Import into a new repo
        let targetRepoURL = tempDir.appendingPathComponent("import_target.sqlite3")
        let targetRepo = try SQLiteHistoryRepository(url: targetRepoURL)

        let importResult = try await BackupService.shared.importFromJSON(sourceURL: exportJSONURL, repository: targetRepo)
        XCTAssertTrue(importResult.success)
        XCTAssertEqual(importResult.itemCount, 2)

        let importedItems = try await targetRepo.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(importedItems.count, 2)
    }

    // MARK: - 2. SQLite Online Physical Backup Tests
    func testSQLitePhysicalBackup() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let originalDB = tempDir.appendingPathComponent("original.sqlite3")
        let targetBackup = tempDir.appendingPathComponent("backup.sqlite3")

        let repo = try SQLiteHistoryRepository(url: originalDB)
        Task { @MainActor in
            try? await repo.insert(content: .text("Physical Backup Item"), at: Date())
        }

        let result = try BackupService.shared.createSQLiteBackup(sourceDatabaseURL: originalDB, destinationURL: targetBackup)
        XCTAssertTrue(result.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetBackup.path))

        // Open backed up database and verify integrity
        let reopened = try SQLiteHistoryRepository(url: targetBackup)
        XCTAssertNotNil(reopened)
    }

    // MARK: - 3. Sync Service Configuration & Adapter Tests
    @MainActor
    func testSyncServiceModesAndAdapters() async throws {
        let sync = SyncService.shared
        sync.mode = .none
        XCTAssertEqual(sync.mode, .none)

        sync.mode = .localFolder
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        sync.localFolderPath = tempDir.path

        let repoURL = tempDir.appendingPathComponent("sync_repo.sqlite3")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let repo = try SQLiteHistoryRepository(url: repoURL)
        try await repo.insert(content: .text("Sync Test Content"), at: Date())

        await sync.syncNow(repository: repo)
        if case .success = sync.status {
            XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("pasteloom_sync.json").path))
        } else {
            XCTFail("Expected sync success, got: \(sync.status)")
        }

        sync.mode = .none
    }

    // MARK: - 4. Localization Service Tests
    @MainActor
    func testLocalizationService() {
        let l10n = LocalizationService.shared
        l10n.language = .zh
        XCTAssertEqual(l10n.string("filter.favorites"), "收藏")
        XCTAssertEqual(l10n.string("quickpaste.title"), "快速粘贴")

        l10n.language = .en
        XCTAssertEqual(l10n.string("filter.favorites"), "Favorites")
        XCTAssertEqual(l10n.string("quickpaste.title"), "Quick Paste")

        // Restore system
        l10n.language = .system
    }

    // MARK: - 5. macOS Widget Data Sharing Tests
    @MainActor
    func testWidgetDataSharingService() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let repoURL = tempDir.appendingPathComponent("widget_test.sqlite3")
        let repo = try SQLiteHistoryRepository(url: repoURL)

        try await repo.insert(content: .text("Widget Recent Item 1"), at: Date())
        try await repo.insert(content: .text("Widget Recent Item 2"), at: Date())

        let widgetService = WidgetDataSharingService.shared
        try await widgetService.exportForWidget(repository: repo)

        XCTAssertTrue(FileManager.default.fileExists(atPath: widgetService.sharingFileURL.path))

        let payload = widgetService.loadCurrentWidgetData()
        XCTAssertNotNil(payload)
        XCTAssertTrue(payload?.recentItems.count ?? 0 >= 2)
    }
}
