import Foundation
import SQLite3

struct ExportOptions: Sendable {
    var maskSensitive: Bool = true
    var includeSnippetsOnly: Bool = false
    var includeTrash: Bool = false
}

struct ExportedHistoryItem: Codable, Sendable {
    let id: UUID
    let kind: String
    let text: String
    let capturedAt: Date
    let isFavorite: Bool
    let isPinned: Bool
    let isSnippet: Bool
    let tags: [String]
    let groupName: String?
    let sourceName: String?
    let copyCount: Int
}

struct ExportManifest: Codable, Sendable {
    let appVersion: String
    let exportedAt: Date
    let totalItems: Int
    let options: [String: Bool]
    let items: [ExportedHistoryItem]
}

struct BackupResult: Sendable {
    let success: Bool
    let itemCount: Int
    let filePath: URL
    let message: String
}

final class BackupService: Sendable {
    static let shared = BackupService()

    private init() {}

    // MARK: - JSON Export
    func exportToJSON(repository: any HistoryRepository,
                      destinationURL: URL,
                      options: ExportOptions = ExportOptions()) async throws -> BackupResult {
        let allItems = try await repository.search(text: "", limit: 10000, offset: 0, filter: .all)

        let filteredItems = allItems.filter { item in
            if options.includeSnippetsOnly && !item.isSnippet { return false }
            if !options.includeTrash && item.isDeleted { return false }
            return true
        }

        let exportedItems: [ExportedHistoryItem] = filteredItems.map { item in
            let textToExport = options.maskSensitive
                ? SensitiveContentService.shared.mask(text: item.text).maskedText
                : item.text

            return ExportedHistoryItem(
                id: item.id,
                kind: item.kind.rawValue,
                text: textToExport,
                capturedAt: item.capturedAt,
                isFavorite: item.isFavorite,
                isPinned: item.isPinned,
                isSnippet: item.isSnippet,
                tags: item.tags,
                groupName: item.groupName,
                sourceName: item.sourceName,
                copyCount: item.copyCount
            )
        }

        let manifest = ExportManifest(
            appVersion: "1.0.0",
            exportedAt: Date(),
            totalItems: exportedItems.count,
            options: [
                "maskSensitive": options.maskSensitive,
                "includeSnippetsOnly": options.includeSnippetsOnly,
                "includeTrash": options.includeTrash
            ],
            items: exportedItems
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: destinationURL, options: .atomic)

        return BackupResult(
            success: true,
            itemCount: exportedItems.count,
            filePath: destinationURL,
            message: "已成功导出 \(exportedItems.count) 条历史数据至 JSON 文件"
        )
    }

    // MARK: - JSON Import
    func importFromJSON(sourceURL: URL,
                        repository: any HistoryRepository) async throws -> BackupResult {
        let data = try Data(contentsOf: sourceURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(ExportManifest.self, from: data)

        var importedCount = 0
        for item in manifest.items {
            let kind = HistoryKind(rawValue: item.kind) ?? .text
            let content: CapturedContent
            switch kind {
            case .text, .richText:
                content = .text(item.text)
            case .url:
                content = .url(item.text)
            case .image:
                // Without raw image payload, store placeholder text
                content = .text(item.text)
            case .file, .video:
                content = .text(item.text)
            }

            let source = item.sourceName.map { CaptureSource(name: $0, bundleIdentifier: nil) }
            let insertedID = try await repository.insert(content: content, at: item.capturedAt, source: source)

            if item.isFavorite {
                try await repository.setFavorite(true, for: insertedID)
            }
            if item.isPinned {
                try await repository.setPinned(true, for: insertedID)
            }
            if item.isSnippet {
                try await repository.setSnippet(true, for: insertedID)
            }
            if !item.tags.isEmpty {
                try await repository.setTags(item.tags, for: insertedID)
            }
            if let group = item.groupName {
                try await repository.setGroup(group, for: insertedID)
            }
            importedCount += 1
        }

        return BackupResult(
            success: true,
            itemCount: importedCount,
            filePath: sourceURL,
            message: "成功从备份文件导入并合并 \(importedCount) 条记录"
        )
    }

    // MARK: - SQLite Online Backup
    func createSQLiteBackup(sourceDatabaseURL: URL, destinationURL: URL) throws -> BackupResult {
        var sourceDB: OpaquePointer?
        var destDB: OpaquePointer?

        guard sqlite3_open_v2(sourceDatabaseURL.path, &sourceDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw NSError(domain: "BackupService", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法打开源数据库"])
        }
        defer { sqlite3_close(sourceDB) }

        // Remove old destination file if it exists
        try? FileManager.default.removeItem(at: destinationURL)

        guard sqlite3_open_v2(destinationURL.path, &destDB, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw NSError(domain: "BackupService", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法创建目标备份文件"])
        }
        defer { sqlite3_close(destDB) }

        guard let backup = sqlite3_backup_init(destDB, "main", sourceDB, "main") else {
            let errorMsg = String(cString: sqlite3_errmsg(destDB))
            throw NSError(domain: "BackupService", code: 3, userInfo: [NSLocalizedDescriptionKey: "初始化备份失败: \(errorMsg)"])
        }

        let stepResult = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)

        guard stepResult == SQLITE_DONE else {
            throw NSError(domain: "BackupService", code: 4, userInfo: [NSLocalizedDescriptionKey: "备份复制过程中断 (错误代码: \(stepResult))"])
        }

        return BackupResult(
            success: true,
            itemCount: 0,
            filePath: destinationURL,
            message: "SQLite 数据库物理备份完成"
        )
    }
}
