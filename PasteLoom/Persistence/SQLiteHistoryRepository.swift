import Foundation
import SQLite3

enum HistoryStoreError: Error {
    case open(String)
    case database(String)
    case invalidAssetPath
}

actor SQLiteHistoryRepository: HistoryRepository {
    private var database: OpaquePointer?
    private let directory: URL

    init(url: URL) throws {
        directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            if let handle { sqlite3_close(handle) }
            throw HistoryStoreError.open(message)
        }
        do {
            try Self.execute("PRAGMA foreign_keys = ON", on: handle)
            try Self.execute("PRAGMA journal_mode = WAL", on: handle)
            try Self.execute("PRAGMA synchronous = NORMAL", on: handle)
            try Self.execute("PRAGMA cache_size = -2000", on: handle)
            try Self.execute("PRAGMA temp_store = MEMORY", on: handle)
            try Self.execute("PRAGMA busy_timeout = 5000", on: handle)
            try Self.execute("PRAGMA wal_autocheckpoint = 100", on: handle)
            try Self.migrate(handle)
            try Self.cleanupLegacyTextDuplicates(handle)
            try Self.healLegacyOCRTexts(handle)
        } catch {
            sqlite3_close(handle)
            throw error
        }
        database = handle
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    func flushMemory() {
        if let database {
            sqlite3_db_cacheflush(database)
        }
        sqlite3_release_memory(0)
    }

    static func defaultURL() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let newDir = base.appendingPathComponent("com.gyryez.pasteloom", isDirectory: true)
        let legacyDir = base.appendingPathComponent("com.gyryez.pasteloom.next", isDirectory: true)

        let targetDB = newDir.appendingPathComponent("history.sqlite3")
        let legacyDB = legacyDir.appendingPathComponent("history.sqlite3")

        // Auto-migration: if new DB does not exist, but legacy DB does exist, copy all contents over
        if !fm.fileExists(atPath: targetDB.path) && fm.fileExists(atPath: legacyDB.path) {
            try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
            if let items = try? fm.contentsOfDirectory(atPath: legacyDir.path) {
                for item in items {
                    let src = legacyDir.appendingPathComponent(item)
                    let dst = newDir.appendingPathComponent(item)
                    if !fm.fileExists(atPath: dst.path) {
                        try? fm.copyItem(at: src, to: dst)
                    }
                }
            }
        }

        return targetDB
    }

    @discardableResult
    func insert(content: CapturedContent, at date: Date, source: CaptureSource? = nil) throws -> UUID {
        let id = UUID()
        var text = ""
        var searchText = ""
        var kind: HistoryKind
        var assetPath: String?
        var contentHash: String?
        var files: [FileReference] = []
        var ocrText: String? = nil
        var rtfData: Data? = nil

        switch content {
        case .text(let value):
            kind = .text
            text = value
            searchText = value
        case .url(let value):
            kind = .url
            text = value
            searchText = value + " " + (URLComponents(string: value)?.host ?? "")
        case .image(let image):
            kind = .image
            contentHash = image.pixelHash
            let relative = "Assets/Images/\(image.pixelHash).png"
            let target = directory.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: target.path) {
                try image.pngData.write(to: target, options: .atomic)
            }
            assetPath = relative
        case .files(let references):
            guard !references.isEmpty else { return id }
            kind = .file
            files = references
            searchText = references.map { "\($0.name) \($0.fileExtension)" }.joined(separator: " ")
        case .richText(let plain, let rtf):
            kind = .richText
            text = plain
            searchText = plain
            rtfData = rtf
        case .video(let reference, let duration, let thumbnail):
            kind = .video
            files = [reference]
            let durationString = duration.map { Self.formatDuration($0) } ?? ""
            text = reference.name + (durationString.isEmpty ? "" : " (\(durationString))")
            searchText = "\(reference.name) \(reference.fileExtension) \(durationString)"
            if let thumbnail {
                contentHash = thumbnail.pixelHash
                let relative = "Assets/Images/\(thumbnail.pixelHash).png"
                let target = directory.appendingPathComponent(relative)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: target.path) {
                    try thumbnail.pngData.write(to: target, options: .atomic)
                }
                assetPath = relative
            }
        }

        do {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                let resolvedID: UUID
                if kind == .image {
                    let insertSQL = "INSERT INTO history_items (id, text, captured_at, kind, asset_path, content_hash, search_text, source_name, source_bundle_id, ocr_text, rtf_data) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(content_hash) WHERE kind = 'image' AND content_hash IS NOT NULL DO UPDATE SET captured_at = MAX(history_items.captured_at, excluded.captured_at), deleted_at = NULL, source_name = excluded.source_name, source_bundle_id = excluded.source_bundle_id RETURNING id"
                    let statement = try prepare(insertSQL)
                    defer { sqlite3_finalize(statement) }
                    bind(id.uuidString, to: 1, in: statement)
                    bind(text, to: 2, in: statement)
                    sqlite3_bind_double(statement, 3, date.timeIntervalSince1970)
                    bind(kind.rawValue, to: 4, in: statement)
                    bind(assetPath, to: 5, in: statement)
                    bind(contentHash, to: 6, in: statement)
                    bind(searchText, to: 7, in: statement)
                    bind(source?.name, to: 8, in: statement)
                    bind(source?.bundleIdentifier, to: 9, in: statement)
                    bind(ocrText, to: 10, in: statement)
                    bind(rtfData, to: 11, in: statement)
                    let stepResult = sqlite3_step(statement)
                    guard stepResult == SQLITE_ROW,
                          let idPointer = sqlite3_column_text(statement, 0),
                          let returnedID = UUID(uuidString: String(cString: idPointer)) else {
                        throw databaseError()
                    }
                    resolvedID = returnedID
                } else if (kind == .text || kind == .richText) && !text.isEmpty {
                    let selectSQL = "SELECT id FROM history_items WHERE kind IN ('text', 'richText') AND text = ? ORDER BY captured_at DESC, id DESC LIMIT 1"
                    let selectStmt = try prepare(selectSQL)
                    bind(text, to: 1, in: selectStmt)
                    var foundID: UUID? = nil
                    if sqlite3_step(selectStmt) == SQLITE_ROW,
                       let idPtr = sqlite3_column_text(selectStmt, 0),
                       let existingUUID = UUID(uuidString: String(cString: idPtr)) {
                        foundID = existingUUID
                    }
                    sqlite3_finalize(selectStmt)

                    if let existingID = foundID {
                        let updateSQL = """
                        UPDATE history_items
                        SET captured_at = MAX(captured_at, ?),
                            deleted_at = NULL,
                            source_name = COALESCE(?, source_name),
                            source_bundle_id = COALESCE(?, source_bundle_id),
                            kind = CASE WHEN ? = 'richText' THEN 'richText' ELSE kind END,
                            rtf_data = COALESCE(?, rtf_data)
                        WHERE id = ?
                        """
                        let updateStmt = try prepare(updateSQL)
                        sqlite3_bind_double(updateStmt, 1, date.timeIntervalSince1970)
                        bind(source?.name, to: 2, in: updateStmt)
                        bind(source?.bundleIdentifier, to: 3, in: updateStmt)
                        bind(kind.rawValue, to: 4, in: updateStmt)
                        bind(rtfData, to: 5, in: updateStmt)
                        bind(existingID.uuidString, to: 6, in: updateStmt)
                        let updateRes = sqlite3_step(updateStmt)
                        sqlite3_finalize(updateStmt)
                        guard updateRes == SQLITE_DONE else { throw databaseError() }

                        let mergeTagsSQL = """
                        INSERT OR IGNORE INTO history_tags (item_id, tag)
                        SELECT ?, tag FROM history_tags WHERE item_id IN (
                            SELECT id FROM history_items WHERE kind IN ('text', 'richText') AND text = ? AND id != ?
                        )
                        """
                        let mergeTagsStmt = try prepare(mergeTagsSQL)
                        bind(existingID.uuidString, to: 1, in: mergeTagsStmt)
                        bind(text, to: 2, in: mergeTagsStmt)
                        bind(existingID.uuidString, to: 3, in: mergeTagsStmt)
                        _ = sqlite3_step(mergeTagsStmt)
                        sqlite3_finalize(mergeTagsStmt)

                        let deleteDupSQL = "DELETE FROM history_items WHERE kind IN ('text', 'richText') AND text = ? AND id != ?"
                        let deleteDupStmt = try prepare(deleteDupSQL)
                        bind(text, to: 1, in: deleteDupStmt)
                        bind(existingID.uuidString, to: 2, in: deleteDupStmt)
                        _ = sqlite3_step(deleteDupStmt)
                        sqlite3_finalize(deleteDupStmt)

                        resolvedID = existingID
                    } else {
                        let insertSQL = "INSERT INTO history_items (id, text, captured_at, kind, asset_path, content_hash, search_text, source_name, source_bundle_id, ocr_text, rtf_data) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id"
                        let statement = try prepare(insertSQL)
                        defer { sqlite3_finalize(statement) }
                        bind(id.uuidString, to: 1, in: statement)
                        bind(text, to: 2, in: statement)
                        sqlite3_bind_double(statement, 3, date.timeIntervalSince1970)
                        bind(kind.rawValue, to: 4, in: statement)
                        bind(assetPath, to: 5, in: statement)
                        bind(contentHash, to: 6, in: statement)
                        bind(searchText, to: 7, in: statement)
                        bind(source?.name, to: 8, in: statement)
                        bind(source?.bundleIdentifier, to: 9, in: statement)
                        bind(ocrText, to: 10, in: statement)
                        bind(rtfData, to: 11, in: statement)
                        let stepResult = sqlite3_step(statement)
                        guard stepResult == SQLITE_ROW,
                              let idPointer = sqlite3_column_text(statement, 0),
                              let returnedID = UUID(uuidString: String(cString: idPointer)) else {
                            throw databaseError()
                        }
                        resolvedID = returnedID
                    }
                } else if kind == .url && !text.isEmpty {
                    let selectSQL = "SELECT id FROM history_items WHERE (kind = 'url' OR (kind IN ('text', 'richText') AND text = ?)) AND text = ? ORDER BY captured_at DESC, id DESC LIMIT 1"
                    let selectStmt = try prepare(selectSQL)
                    bind(text, to: 1, in: selectStmt)
                    bind(text, to: 2, in: selectStmt)
                    var foundID: UUID? = nil
                    if sqlite3_step(selectStmt) == SQLITE_ROW,
                       let idPtr = sqlite3_column_text(selectStmt, 0),
                       let existingUUID = UUID(uuidString: String(cString: idPtr)) {
                        foundID = existingUUID
                    }
                    sqlite3_finalize(selectStmt)

                    if let existingID = foundID {
                        let updateSQL = """
                        UPDATE history_items
                        SET captured_at = MAX(captured_at, ?),
                            deleted_at = NULL,
                            source_name = COALESCE(?, source_name),
                            source_bundle_id = COALESCE(?, source_bundle_id),
                            kind = 'url'
                        WHERE id = ?
                        """
                        let updateStmt = try prepare(updateSQL)
                        sqlite3_bind_double(updateStmt, 1, date.timeIntervalSince1970)
                        bind(source?.name, to: 2, in: updateStmt)
                        bind(source?.bundleIdentifier, to: 3, in: updateStmt)
                        bind(existingID.uuidString, to: 4, in: updateStmt)
                        let updateRes = sqlite3_step(updateStmt)
                        sqlite3_finalize(updateStmt)
                        guard updateRes == SQLITE_DONE else { throw databaseError() }

                        let mergeTagsSQL = """
                        INSERT OR IGNORE INTO history_tags (item_id, tag)
                        SELECT ?, tag FROM history_tags WHERE item_id IN (
                            SELECT id FROM history_items WHERE text = ? AND id != ?
                        )
                        """
                        let mergeTagsStmt = try prepare(mergeTagsSQL)
                        bind(existingID.uuidString, to: 1, in: mergeTagsStmt)
                        bind(text, to: 2, in: mergeTagsStmt)
                        bind(existingID.uuidString, to: 3, in: mergeTagsStmt)
                        _ = sqlite3_step(mergeTagsStmt)
                        sqlite3_finalize(mergeTagsStmt)

                        let deleteDupSQL = "DELETE FROM history_items WHERE text = ? AND id != ?"
                        let deleteDupStmt = try prepare(deleteDupSQL)
                        bind(text, to: 1, in: deleteDupStmt)
                        bind(existingID.uuidString, to: 2, in: deleteDupStmt)
                        _ = sqlite3_step(deleteDupStmt)
                        sqlite3_finalize(deleteDupStmt)

                        resolvedID = existingID
                    } else {
                        let insertSQL = "INSERT INTO history_items (id, text, captured_at, kind, asset_path, content_hash, search_text, source_name, source_bundle_id, ocr_text, rtf_data) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id"
                        let statement = try prepare(insertSQL)
                        defer { sqlite3_finalize(statement) }
                        bind(id.uuidString, to: 1, in: statement)
                        bind(text, to: 2, in: statement)
                        sqlite3_bind_double(statement, 3, date.timeIntervalSince1970)
                        bind(kind.rawValue, to: 4, in: statement)
                        bind(assetPath, to: 5, in: statement)
                        bind(contentHash, to: 6, in: statement)
                        bind(searchText, to: 7, in: statement)
                        bind(source?.name, to: 8, in: statement)
                        bind(source?.bundleIdentifier, to: 9, in: statement)
                        bind(ocrText, to: 10, in: statement)
                        bind(rtfData, to: 11, in: statement)
                        let stepResult = sqlite3_step(statement)
                        guard stepResult == SQLITE_ROW,
                              let idPointer = sqlite3_column_text(statement, 0),
                              let returnedID = UUID(uuidString: String(cString: idPointer)) else {
                            throw databaseError()
                        }
                        resolvedID = returnedID
                    }
                } else {
                    let insertSQL = "INSERT INTO history_items (id, text, captured_at, kind, asset_path, content_hash, search_text, source_name, source_bundle_id, ocr_text, rtf_data) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id"
                    let statement = try prepare(insertSQL)
                    defer { sqlite3_finalize(statement) }
                    bind(id.uuidString, to: 1, in: statement)
                    bind(text, to: 2, in: statement)
                    sqlite3_bind_double(statement, 3, date.timeIntervalSince1970)
                    bind(kind.rawValue, to: 4, in: statement)
                    bind(assetPath, to: 5, in: statement)
                    bind(contentHash, to: 6, in: statement)
                    bind(searchText, to: 7, in: statement)
                    bind(source?.name, to: 8, in: statement)
                    bind(source?.bundleIdentifier, to: 9, in: statement)
                    bind(ocrText, to: 10, in: statement)
                    bind(rtfData, to: 11, in: statement)
                    let stepResult = sqlite3_step(statement)
                    guard stepResult == SQLITE_ROW,
                          let idPointer = sqlite3_column_text(statement, 0),
                          let returnedID = UUID(uuidString: String(cString: idPointer)) else {
                        throw databaseError()
                    }
                    resolvedID = returnedID
                }

                if !files.isEmpty {
                    let fileStatement = try prepare("INSERT INTO file_references (item_id, position, url, name, file_extension, type_identifier) VALUES (?, ?, ?, ?, ?, ?)")
                    defer { sqlite3_finalize(fileStatement) }
                    for (index, file) in files.enumerated() {
                        sqlite3_reset(fileStatement)
                        sqlite3_clear_bindings(fileStatement)
                        bind(resolvedID.uuidString, to: 1, in: fileStatement)
                        sqlite3_bind_int(fileStatement, 2, Int32(index))
                        bind(file.url.absoluteString, to: 3, in: fileStatement)
                        bind(file.name, to: 4, in: fileStatement)
                        bind(file.fileExtension, to: 5, in: fileStatement)
                        bind(file.typeIdentifier, to: 6, in: fileStatement)
                        guard sqlite3_step(fileStatement) == SQLITE_DONE else { throw databaseError() }
                    }
                }
                try execute("COMMIT")
                return resolvedID
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        } catch { throw error }
    }

    func search(text: String, limit: Int, offset: Int) throws -> [HistoryItem] {
        try search(text: text, limit: limit, offset: offset, filter: .all)
    }

    func search(text: String, limit: Int, offset: Int, filter: HistoryFilter) throws -> [HistoryItem] {
        try search(text: text, limit: limit, offset: offset, filter: filter, mode: .fullText)
    }

    func search(text: String, limit: Int, offset: Int, filter: HistoryFilter,
                mode: HistorySearchMode) throws -> [HistoryItem] {
        try search(text: text, limit: limit, offset: offset, filter: filter, mode: mode, scope: .unrestricted)
    }

    func search(text: String, limit: Int, offset: Int, filter: HistoryFilter,
                mode: HistorySearchMode, scope: HistoryScope) throws -> [HistoryItem] {
        let filterSQL: String
        switch filter {
        case .all: filterSQL = "deleted_at IS NULL"
        case .favorites: filterSQL = "deleted_at IS NULL AND favorite = 1"
        case .trash: filterSQL = "deleted_at IS NOT NULL"
        }
        let matching: String
        if text.isEmpty {
            matching = mode == .tags ? " AND id IN (SELECT item_id FROM history_tags)" : ""
        } else if mode == .tags {
            matching = " AND id IN (SELECT item_id FROM history_tags WHERE tag LIKE ? ESCAPE '\\')"
        } else {
            // .fullText 或 .semantic 均检索全文、OCR、来源应用与标签
            matching = " AND (search_text LIKE ? ESCAPE '\\' OR source_name LIKE ? ESCAPE '\\' OR ocr_text LIKE ? ESCAPE '\\' OR id IN (SELECT item_id FROM history_tags WHERE tag LIKE ? ESCAPE '\\'))"
        }
        let selectedTags = Array(Set(scope.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })).sorted()
        let tagSQL: String
        if selectedTags.isEmpty {
            tagSQL = ""
        } else if scope.tagMatch == .all {
            tagSQL = selectedTags.map { _ in
                " AND EXISTS (SELECT 1 FROM history_tags WHERE item_id = history_items.id AND tag = ? COLLATE NOCASE)"
            }.joined()
        } else {
            tagSQL = " AND EXISTS (SELECT 1 FROM history_tags WHERE item_id = history_items.id AND tag COLLATE NOCASE IN (\(Array(repeating: "?", count: selectedTags.count).joined(separator: ","))))"
        }
        let scopeSQL = (scope.kind == nil ? "" : " AND kind = ?")
            + (scope.sourceName.isEmpty ? "" : " AND source_name LIKE ? ESCAPE '\\'")
            + (scope.since == nil ? "" : " AND captured_at >= ?")
            + (scope.groupName == nil ? "" : " AND group_name = ?")
            + (scope.isSnippet == nil ? "" : " AND is_snippet = ?") + tagSQL
        let order = filter == .trash ? "deleted_at DESC, id DESC" : "pinned DESC, captured_at DESC, id DESC"
        let query = "SELECT id, kind, text, captured_at, asset_path, content_hash, favorite, pinned, deleted_at, source_name, source_bundle_id, ocr_text, rtf_data, is_snippet, group_name, copy_count FROM history_items WHERE \(filterSQL)\(matching)\(scopeSQL) ORDER BY \(order) LIMIT ? OFFSET ?"
        let statement = try prepare(query)
        defer { sqlite3_finalize(statement) }
        let firstIndex: Int32
        if text.isEmpty {
            firstIndex = 1
        } else {
            let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            bind("%\(escaped)%", to: 1, in: statement)
            if mode == .fullText || mode == .semantic {
                bind("%\(escaped)%", to: 2, in: statement)
                bind("%\(escaped)%", to: 3, in: statement)
                bind("%\(escaped)%", to: 4, in: statement)
                firstIndex = 5
            } else {
                firstIndex = 2
            }
        }
        var nextIndex = firstIndex
        if let kind = scope.kind {
            bind(kind.rawValue, to: nextIndex, in: statement)
            nextIndex += 1
        }
        if !scope.sourceName.isEmpty {
            let escapedSource = scope.sourceName.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            bind("%\(escapedSource)%", to: nextIndex, in: statement)
            nextIndex += 1
        }
        if let since = scope.since {
            sqlite3_bind_double(statement, nextIndex, since.timeIntervalSince1970)
            nextIndex += 1
        }
        if let group = scope.groupName {
            bind(group, to: nextIndex, in: statement)
            nextIndex += 1
        }
        if let isSnippet = scope.isSnippet {
            sqlite3_bind_int(statement, nextIndex, isSnippet ? 1 : 0)
            nextIndex += 1
        }
        for tag in selectedTags {
            bind(tag, to: nextIndex, in: statement)
            nextIndex += 1
        }
        sqlite3_bind_int(statement, nextIndex, Int32(max(1, limit)))
        sqlite3_bind_int(statement, nextIndex + 1, Int32(max(0, offset)))
        struct RawRow {
            let id: UUID
            let kind: HistoryKind
            let text: String
            let capturedAt: Date
            let imageRelativePath: String?
            let contentHash: String?
            let isFavorite: Bool
            let isPinned: Bool
            let isDeleted: Bool
            let sourceName: String?
            let sourceBundleIdentifier: String?
            let ocrText: String?
            let rtfData: Data?
            let isSnippet: Bool
            let groupName: String?
            let copyCount: Int
        }
        var rawRows: [RawRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw databaseError() }
            guard let idPointer = sqlite3_column_text(statement, 0),
                  let kindPointer = sqlite3_column_text(statement, 1),
                  let textPointer = sqlite3_column_text(statement, 2),
                  let id = UUID(uuidString: String(cString: idPointer)),
                  let kind = HistoryKind(rawValue: String(cString: kindPointer)) else { continue }
            rawRows.append(RawRow(id: id,
                                  kind: kind,
                                  text: String(cString: textPointer),
                                  capturedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                                  imageRelativePath: columnString(statement, at: 4),
                                  contentHash: columnString(statement, at: 5),
                                  isFavorite: sqlite3_column_int(statement, 6) != 0,
                                  isPinned: sqlite3_column_int(statement, 7) != 0,
                                  isDeleted: sqlite3_column_type(statement, 8) != SQLITE_NULL,
                                  sourceName: columnString(statement, at: 9),
                                  sourceBundleIdentifier: columnString(statement, at: 10),
                                  ocrText: columnString(statement, at: 11),
                                  rtfData: columnBlob(statement, at: 12),
                                  isSnippet: sqlite3_column_int(statement, 13) != 0,
                                  groupName: columnString(statement, at: 14),
                                  copyCount: Int(sqlite3_column_int(statement, 15))))
        }
        guard !rawRows.isEmpty else { return [] }

        let allIDs = rawRows.map(\.id)
        let tagMap = try tagsBatch(for: allIDs)
        let fileIDs = rawRows.filter { $0.kind == .file || $0.kind == .video }.map(\.id)
        let fileMap = try fileReferencesBatch(for: fileIDs)

        var items: [HistoryItem] = []
        items.reserveCapacity(rawRows.count)
        for row in rawRows {
            items.append(HistoryItem(id: row.id,
                                     kind: row.kind,
                                     text: row.text,
                                     capturedAt: row.capturedAt,
                                     imageRelativePath: row.imageRelativePath,
                                     contentHash: row.contentHash,
                                     files: fileMap[row.id] ?? [],
                                     isFavorite: row.isFavorite,
                                     isPinned: row.isPinned,
                                     isDeleted: row.isDeleted,
                                     tags: tagMap[row.id] ?? [],
                                     sourceName: row.sourceName,
                                     sourceBundleIdentifier: row.sourceBundleIdentifier,
                                     ocrText: row.ocrText,
                                     rtfData: row.rtfData,
                                     isSnippet: row.isSnippet,
                                     groupName: row.groupName,
                                     copyCount: row.copyCount))
        }
        if mode == .semantic && !text.isEmpty {
            return SemanticSearchEngine.shared.rank(items: items, query: text)
        }
        return items
    }

    func imageData(relativePath: String) throws -> Data {
        try Data(contentsOf: validatedAssetURL(relativePath))
    }

    func setFavorite(_ favorite: Bool, for id: UUID) throws {
        try updateFlag("favorite", value: favorite, id: id)
    }

    func setPinned(_ pinned: Bool, for id: UUID) throws {
        try updateFlag("pinned", value: pinned, id: id)
    }

    func setTags(_ tags: [String], for id: UUID) throws {
        let normalized = Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 40 })).sorted()
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let deleteStatement = try prepare("DELETE FROM history_tags WHERE item_id = ?")
            bind(id.uuidString, to: 1, in: deleteStatement)
            guard sqlite3_step(deleteStatement) == SQLITE_DONE else { throw databaseError() }
            sqlite3_finalize(deleteStatement)
            let statement = try prepare("INSERT INTO history_tags (item_id, tag) VALUES (?, ?)")
            defer { sqlite3_finalize(statement) }
            for tag in normalized {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bind(id.uuidString, to: 1, in: statement)
                bind(tag, to: 2, in: statement)
                guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func addTags(_ tags: [String], for id: UUID) throws {
        let normalized = Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 40 })).sorted()
        guard !normalized.isEmpty else { return }
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let statement = try prepare("INSERT OR IGNORE INTO history_tags (item_id, tag) VALUES (?, ?)")
            defer { sqlite3_finalize(statement) }
            for tag in normalized {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bind(id.uuidString, to: 1, in: statement)
                bind(tag, to: 2, in: statement)
                guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func moveToTrash(id: UUID) throws {
        let statement = try prepare("UPDATE history_items SET deleted_at = ? WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
        bind(id.uuidString, to: 2, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }

    func restore(id: UUID) throws {
        let statement = try prepare("UPDATE history_items SET deleted_at = NULL WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }

    func delete(id: UUID) throws {
        let current = try assetPath(for: id)
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let statement = try prepare("DELETE FROM history_items WHERE id = ?")
            defer { sqlite3_finalize(statement) }
            bind(id.uuidString, to: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
        if let current, try countReferences(to: current) == 0 {
            try FileManager.default.removeItem(at: validatedAssetURL(current))
        }
    }

    func updateOCRText(_ ocrText: String, for id: UUID) throws {
        let sql = "UPDATE history_items SET ocr_text = ?, search_text = CASE WHEN search_text = '' THEN ? ELSE search_text || ' ' || ? END WHERE id = ?"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(ocrText, to: 1, in: statement)
        bind(ocrText, to: 2, in: statement)
        bind(ocrText, to: 3, in: statement)
        bind(id.uuidString, to: 4, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }

    func setSnippet(_ isSnippet: Bool, for id: UUID) throws {
        let statement = try prepare("UPDATE history_items SET is_snippet = ? WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, isSnippet ? 1 : 0)
        bind(id.uuidString, to: 2, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }

    func setGroup(_ groupName: String?, for id: UUID) throws {
        let statement = try prepare("UPDATE history_items SET group_name = ? WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        bind(groupName?.trimmingCharacters(in: .whitespacesAndNewlines), to: 1, in: statement)
        bind(id.uuidString, to: 2, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }

    func allGroups() throws -> [String] {
        let statement = try prepare("SELECT DISTINCT group_name FROM history_items WHERE group_name IS NOT NULL AND group_name != '' AND deleted_at IS NULL ORDER BY group_name")
        defer { sqlite3_finalize(statement) }
        var result: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let group = columnString(statement, at: 0) {
                result.append(group)
            }
        }
        return result
    }

    func incrementCopyCount(for id: UUID) throws {
        let statement = try prepare("UPDATE history_items SET copy_count = copy_count + 1 WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }

    func resetStatistics() throws {
        try execute("UPDATE history_items SET copy_count = 0")
    }

    func fetchStatistics() throws -> HistoryStatistics {
        let statement = try prepare("""
            SELECT
                COUNT(*),
                COALESCE(SUM(copy_count), 0),
                COALESCE(SUM(CASE WHEN kind = 'text' THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN kind = 'image' THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN kind = 'url' THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN kind = 'file' THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN kind = 'richText' THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN kind = 'video' THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN is_snippet = 1 THEN 1 ELSE 0 END), 0)
            FROM history_items WHERE deleted_at IS NULL
        """)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return HistoryStatistics(totalItems: 0, totalCopies: 0, textCount: 0, imageCount: 0, urlCount: 0, fileCount: 0, richTextCount: 0, videoCount: 0, snippetCount: 0, topCopied: [])
        }
        let total = Int(sqlite3_column_int(statement, 0))
        let copies = Int(sqlite3_column_int(statement, 1))
        let texts = Int(sqlite3_column_int(statement, 2))
        let images = Int(sqlite3_column_int(statement, 3))
        let urls = Int(sqlite3_column_int(statement, 4))
        let files = Int(sqlite3_column_int(statement, 5))
        let rich = Int(sqlite3_column_int(statement, 6))
        let videos = Int(sqlite3_column_int(statement, 7))
        let snippets = Int(sqlite3_column_int(statement, 8))

        let topStatement = try prepare("SELECT id, kind, text, captured_at, asset_path, content_hash, favorite, pinned, deleted_at, source_name, source_bundle_id, ocr_text, rtf_data, is_snippet, group_name, copy_count FROM history_items WHERE deleted_at IS NULL AND copy_count > 0 ORDER BY copy_count DESC, captured_at DESC LIMIT 5")
        defer { sqlite3_finalize(topStatement) }
        var topItems: [HistoryItem] = []
        while sqlite3_step(topStatement) == SQLITE_ROW {
            guard let idPointer = sqlite3_column_text(topStatement, 0),
                  let kindPointer = sqlite3_column_text(topStatement, 1),
                  let textPointer = sqlite3_column_text(topStatement, 2),
                  let id = UUID(uuidString: String(cString: idPointer)),
                  let kind = HistoryKind(rawValue: String(cString: kindPointer)) else { continue }
            topItems.append(HistoryItem(id: id,
                                        kind: kind,
                                        text: String(cString: textPointer),
                                        capturedAt: Date(timeIntervalSince1970: sqlite3_column_double(topStatement, 3)),
                                        imageRelativePath: columnString(topStatement, at: 4),
                                        contentHash: columnString(topStatement, at: 5),
                                        files: (kind == .file || kind == .video) ? try fileReferences(for: id) : [],
                                        isFavorite: sqlite3_column_int(topStatement, 6) != 0,
                                        isPinned: sqlite3_column_int(topStatement, 7) != 0,
                                        isDeleted: false,
                                        tags: try tags(for: id),
                                        sourceName: columnString(topStatement, at: 9),
                                        sourceBundleIdentifier: columnString(topStatement, at: 10),
                                        ocrText: columnString(topStatement, at: 11),
                                        rtfData: columnBlob(topStatement, at: 12),
                                        isSnippet: sqlite3_column_int(topStatement, 13) != 0,
                                        groupName: columnString(topStatement, at: 14),
                                        copyCount: Int(sqlite3_column_int(topStatement, 15))))
        }

        return HistoryStatistics(totalItems: total, totalCopies: copies, textCount: texts,
                                 imageCount: images, urlCount: urls, fileCount: files,
                                 richTextCount: rich, videoCount: videos, snippetCount: snippets,
                                 topCopied: topItems)
    }

    func merge(ids: [UUID], separator: String) throws -> HistoryItem? {
        guard !ids.isEmpty else { return nil }
        var texts: [String] = []
        var mergedTags: Set<String> = []
        for id in ids {
            let statement = try prepare("SELECT text FROM history_items WHERE id = ?")
            bind(id.uuidString, to: 1, in: statement)
            if sqlite3_step(statement) == SQLITE_ROW, let pointer = sqlite3_column_text(statement, 0) {
                texts.append(String(cString: pointer))
            }
            sqlite3_finalize(statement)
            if let itemTags = try? tags(for: id) {
                mergedTags.formUnion(itemTags)
            }
        }
        guard !texts.isEmpty else { return nil }
        let mergedText = texts.joined(separator: separator)
        let newContent = CapturedContent.text(mergedText)
        let now = Date()
        try insert(content: newContent, at: now, source: CaptureSource(name: "Merge", bundleIdentifier: "com.gyryez.pasteloom"))
        let found = try search(text: "", limit: 1, offset: 0)
        guard let first = found.first else { return nil }
        if !mergedTags.isEmpty {
            try setTags(Array(mergedTags), for: first.id)
            let updated = try search(text: "", limit: 1, offset: 0)
            return updated.first
        }
        return first
    }

    func runRetention(retentionDays: Int, trashRetentionDays: Int) throws -> Int {
        var purgedCount = 0
        let now = Date().timeIntervalSince1970

        if trashRetentionDays > 0 {
            let trashCutoff = now - Double(trashRetentionDays * 86400)
            let selectTrash = try prepare("SELECT id FROM history_items WHERE deleted_at IS NOT NULL AND deleted_at < ?")
            sqlite3_bind_double(selectTrash, 1, trashCutoff)
            var trashIds: [UUID] = []
            while sqlite3_step(selectTrash) == SQLITE_ROW {
                if let idPointer = sqlite3_column_text(selectTrash, 0), let id = UUID(uuidString: String(cString: idPointer)) {
                    trashIds.append(id)
                }
            }
            sqlite3_finalize(selectTrash)

            for id in trashIds {
                try delete(id: id)
                purgedCount += 1
            }
        }

        if retentionDays > 0 {
            let historyCutoff = now - Double(retentionDays * 86400)
            // ABSOLUTE SAFETY LAW: pinned = 0 AND favorite = 0 AND is_snippet = 0 are required!
            let selectExpired = try prepare("SELECT id FROM history_items WHERE deleted_at IS NULL AND pinned = 0 AND favorite = 0 AND is_snippet = 0 AND captured_at < ?")
            sqlite3_bind_double(selectExpired, 1, historyCutoff)
            var expiredIds: [UUID] = []
            while sqlite3_step(selectExpired) == SQLITE_ROW {
                if let idPointer = sqlite3_column_text(selectExpired, 0), let id = UUID(uuidString: String(cString: idPointer)) {
                    expiredIds.append(id)
                }
            }
            sqlite3_finalize(selectExpired)

            for id in expiredIds {
                try delete(id: id)
                purgedCount += 1
            }
        }

        if purgedCount > 0 {
            try? execute("PRAGMA wal_checkpoint(PASSIVE)")
        }

        return purgedCount
    }

    private func tagsBatch(for ids: [UUID]) throws -> [UUID: [String]] {
        guard !ids.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let statement = try prepare("SELECT item_id, tag FROM history_tags WHERE item_id IN (\(placeholders)) ORDER BY tag ASC")
        defer { sqlite3_finalize(statement) }
        for (index, id) in ids.enumerated() {
            bind(id.uuidString, to: Int32(index + 1), in: statement)
        }
        var map: [UUID: [String]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(statement, 0),
                  let tagPtr = sqlite3_column_text(statement, 1),
                  let id = UUID(uuidString: String(cString: idPtr)) else { continue }
            map[id, default: []].append(String(cString: tagPtr))
        }
        return map
    }

    private func fileReferencesBatch(for ids: [UUID]) throws -> [UUID: [FileReference]] {
        guard !ids.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let statement = try prepare("SELECT item_id, url, name, file_extension, type_identifier FROM file_references WHERE item_id IN (\(placeholders)) ORDER BY position ASC")
        defer { sqlite3_finalize(statement) }
        for (index, id) in ids.enumerated() {
            bind(id.uuidString, to: Int32(index + 1), in: statement)
        }
        var map: [UUID: [FileReference]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(statement, 0),
                  let id = UUID(uuidString: String(cString: idPtr)),
                  let raw = columnString(statement, at: 1),
                  let url = URL(string: raw), url.isFileURL else { continue }
            let ref = FileReference(url: url,
                                    name: columnString(statement, at: 2) ?? url.lastPathComponent,
                                    fileExtension: columnString(statement, at: 3) ?? url.pathExtension,
                                    typeIdentifier: columnString(statement, at: 4))
            map[id, default: []].append(ref)
        }
        return map
    }

    private func fileReferences(for id: UUID) throws -> [FileReference] {
        let statement = try prepare("SELECT url, name, file_extension, type_identifier FROM file_references WHERE item_id = ? ORDER BY position")
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: 1, in: statement)
        var files: [FileReference] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw databaseError() }
            guard let raw = columnString(statement, at: 0), let url = URL(string: raw), url.isFileURL else { continue }
            files.append(FileReference(url: url,
                                       name: columnString(statement, at: 1) ?? url.lastPathComponent,
                                       fileExtension: columnString(statement, at: 2) ?? url.pathExtension,
                                       typeIdentifier: columnString(statement, at: 3)))
        }
        return files
    }

    private func tags(for id: UUID) throws -> [String] {
        let statement = try prepare("SELECT tag FROM history_tags WHERE item_id = ? ORDER BY tag")
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: 1, in: statement)
        var result: [String] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw databaseError() }
            if let tag = columnString(statement, at: 0) { result.append(tag) }
        }
        return result
    }

    private func updateFlag(_ column: String, value: Bool, id: UUID) throws {
        // The column is selected only by the two fixed call sites above.
        let statement = try prepare("UPDATE history_items SET \(column) = ? WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, value ? 1 : 0)
        bind(id.uuidString, to: 2, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }

    private func assetPath(for id: UUID) throws -> String? {
        let statement = try prepare("SELECT asset_path FROM history_items WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: 1, in: statement)
        return sqlite3_step(statement) == SQLITE_ROW ? columnString(statement, at: 0) : nil
    }

    private func countReferences(to path: String) throws -> Int {
        let statement = try prepare("SELECT (SELECT count(*) FROM history_items WHERE asset_path = ?) + (SELECT count(*) FROM archived_duplicate_images WHERE asset_path = ?)")
        defer { sqlite3_finalize(statement) }
        bind(path, to: 1, in: statement)
        bind(path, to: 2, in: statement)
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int(statement, 0)) : 0
    }

    private func validatedAssetURL(_ relativePath: String) throws -> URL {
        let parts = relativePath.split(separator: "/")
        guard parts.count == 3, parts[0] == "Assets", parts[1] == "Images",
              parts[2].hasSuffix(".png"),
              parts[2].dropLast(4).count == 64,
              parts[2].dropLast(4).allSatisfy({ $0.isHexDigit }) else { throw HistoryStoreError.invalidAssetPath }
        return directory.appendingPathComponent(relativePath)
    }

    private static func migrate(_ database: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else { throw databaseError(database) }
        let version = sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int(statement, 0) : -1
        sqlite3_finalize(statement)
        guard version >= 0 && version <= 7 else { throw HistoryStoreError.database("数据库版本不受支持") }

        if version == 0 {
            try execute("BEGIN IMMEDIATE TRANSACTION", on: database)
            do {
                try execute("CREATE TABLE history_items (id TEXT PRIMARY KEY, text TEXT NOT NULL, captured_at REAL NOT NULL)", on: database)
                try execute("CREATE INDEX history_items_time ON history_items (captured_at DESC, id DESC)", on: database)
                try execute("PRAGMA user_version = 1", on: database)
                try execute("COMMIT", on: database)
            } catch {
                try? execute("ROLLBACK", on: database)
                throw error
            }
        }
        if version < 2 {
            try execute("BEGIN IMMEDIATE TRANSACTION", on: database)
            do {
                try execute("ALTER TABLE history_items ADD COLUMN kind TEXT NOT NULL DEFAULT 'text'", on: database)
                try execute("ALTER TABLE history_items ADD COLUMN asset_path TEXT", on: database)
                try execute("ALTER TABLE history_items ADD COLUMN content_hash TEXT", on: database)
                try execute("ALTER TABLE history_items ADD COLUMN search_text TEXT NOT NULL DEFAULT ''", on: database)
                try execute("UPDATE history_items SET search_text = text", on: database)
                try execute("CREATE TABLE file_references (item_id TEXT NOT NULL REFERENCES history_items(id) ON DELETE CASCADE, position INTEGER NOT NULL, url TEXT NOT NULL, name TEXT NOT NULL, file_extension TEXT NOT NULL, type_identifier TEXT, PRIMARY KEY(item_id, position))", on: database)
                try execute("PRAGMA user_version = 2", on: database)
                try execute("COMMIT", on: database)
            } catch {
                try? execute("ROLLBACK", on: database)
                throw error
            }
        }
        if version < 3 {
            try execute("BEGIN IMMEDIATE TRANSACTION", on: database)
            do {
                try execute("CREATE INDEX history_items_image_fingerprint ON history_items (content_hash, captured_at DESC) WHERE kind = 'image'", on: database)
                try execute("PRAGMA user_version = 3", on: database)
                try execute("COMMIT", on: database)
            } catch {
                try? execute("ROLLBACK", on: database)
                throw error
            }
        }
        if version < 4 {
            try execute("BEGIN IMMEDIATE TRANSACTION", on: database)
            do {
                try execute("CREATE TABLE archived_duplicate_images (id TEXT PRIMARY KEY, text TEXT NOT NULL, captured_at REAL NOT NULL, kind TEXT NOT NULL, asset_path TEXT, content_hash TEXT, search_text TEXT NOT NULL, archived_at REAL NOT NULL)", on: database)
                let duplicates = """
                INSERT INTO archived_duplicate_images
                    (id, text, captured_at, kind, asset_path, content_hash, search_text, archived_at)
                SELECT old.id, old.text, old.captured_at, old.kind, old.asset_path,
                       old.content_hash, old.search_text, strftime('%s','now')
                FROM history_items AS old
                WHERE old.kind = 'image' AND old.content_hash IS NOT NULL
                  AND EXISTS (
                    SELECT 1 FROM history_items AS newer
                    WHERE newer.kind = 'image' AND newer.content_hash = old.content_hash
                      AND (newer.captured_at > old.captured_at
                           OR (newer.captured_at = old.captured_at AND newer.id > old.id))
                  )
                """
                try execute(duplicates, on: database)
                try execute("DELETE FROM history_items WHERE id IN (SELECT id FROM archived_duplicate_images)", on: database)
                try execute("CREATE UNIQUE INDEX history_items_image_fingerprint_unique ON history_items (content_hash) WHERE kind = 'image' AND content_hash IS NOT NULL", on: database)
                try execute("PRAGMA user_version = 4", on: database)
                try execute("COMMIT", on: database)
            } catch {
                try? execute("ROLLBACK", on: database)
                throw error
            }
        }
        if version < 5 {
            try execute("BEGIN IMMEDIATE TRANSACTION", on: database)
            do {
                try execute("ALTER TABLE history_items ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0", on: database)
                try execute("ALTER TABLE history_items ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0", on: database)
                try execute("ALTER TABLE history_items ADD COLUMN deleted_at REAL", on: database)
                try execute("ALTER TABLE history_items ADD COLUMN source_name TEXT", on: database)
                try execute("ALTER TABLE history_items ADD COLUMN source_bundle_id TEXT", on: database)
                try execute("CREATE TABLE history_tags (item_id TEXT NOT NULL REFERENCES history_items(id) ON DELETE CASCADE, tag TEXT NOT NULL, PRIMARY KEY(item_id, tag))", on: database)
                try execute("CREATE INDEX history_tags_tag ON history_tags(tag)", on: database)
                try execute("CREATE INDEX history_items_state ON history_items(deleted_at, pinned DESC, captured_at DESC)", on: database)
                try execute("PRAGMA user_version = 5", on: database)
                try execute("COMMIT", on: database)
            } catch {
                try? execute("ROLLBACK", on: database)
                throw error
            }
        }
        if version < 6 {
            try execute("BEGIN IMMEDIATE TRANSACTION", on: database)
            do {
                try execute("ALTER TABLE history_items ADD COLUMN ocr_text TEXT", on: database)
                try execute("ALTER TABLE history_items ADD COLUMN rtf_data BLOB", on: database)
                try execute("CREATE INDEX history_items_ocr ON history_items(ocr_text) WHERE ocr_text IS NOT NULL", on: database)
                try execute("PRAGMA user_version = 6", on: database)
                try execute("COMMIT", on: database)
            } catch {
                try? execute("ROLLBACK", on: database)
                throw error
            }
        }
        if version < 7 {
            try execute("BEGIN IMMEDIATE TRANSACTION", on: database)
            do {
                try execute("ALTER TABLE history_items ADD COLUMN is_snippet INTEGER NOT NULL DEFAULT 0", on: database)
                try execute("ALTER TABLE history_items ADD COLUMN group_name TEXT", on: database)
                try execute("ALTER TABLE history_items ADD COLUMN copy_count INTEGER NOT NULL DEFAULT 0", on: database)
                try execute("CREATE INDEX history_items_snippet ON history_items(is_snippet) WHERE is_snippet = 1", on: database)
                try execute("CREATE INDEX history_items_group ON history_items(group_name) WHERE group_name IS NOT NULL", on: database)
                try execute("PRAGMA user_version = 7", on: database)
                try execute("COMMIT", on: database)
            } catch {
                try? execute("ROLLBACK", on: database)
                throw error
            }
        }
    }

    private static func cleanupLegacyTextDuplicates(_ database: OpaquePointer) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION", on: database)
        do {
            let preservePinnedSQL = """
            UPDATE history_items
            SET pinned = 1
            WHERE id IN (
                SELECT newer.id FROM history_items newer
                JOIN history_items older ON older.text = newer.text
                  AND older.kind IN ('text', 'richText') AND newer.kind IN ('text', 'richText')
                  AND older.id != newer.id
                  AND (newer.captured_at > older.captured_at OR (newer.captured_at = older.captured_at AND newer.id > older.id))
                WHERE older.pinned = 1
            )
            """
            try execute(preservePinnedSQL, on: database)

            let preserveFavoriteSQL = """
            UPDATE history_items
            SET favorite = 1
            WHERE id IN (
                SELECT newer.id FROM history_items newer
                JOIN history_items older ON older.text = newer.text
                  AND older.kind IN ('text', 'richText') AND newer.kind IN ('text', 'richText')
                  AND older.id != newer.id
                  AND (newer.captured_at > older.captured_at OR (newer.captured_at = older.captured_at AND newer.id > older.id))
                WHERE older.favorite = 1
            )
            """
            try execute(preserveFavoriteSQL, on: database)

            let preserveSnippetSQL = """
            UPDATE history_items
            SET is_snippet = 1
            WHERE id IN (
                SELECT newer.id FROM history_items newer
                JOIN history_items older ON older.text = newer.text
                  AND older.kind IN ('text', 'richText') AND newer.kind IN ('text', 'richText')
                  AND older.id != newer.id
                  AND (newer.captured_at > older.captured_at OR (newer.captured_at = older.captured_at AND newer.id > older.id))
                WHERE older.is_snippet = 1
            )
            """
            try execute(preserveSnippetSQL, on: database)

            let mergeTagsSQL = """
            INSERT OR IGNORE INTO history_tags (item_id, tag)
            SELECT newer.id, older_tags.tag
            FROM history_tags older_tags
            JOIN history_items older ON older_tags.item_id = older.id
            JOIN history_items newer ON older.text = newer.text
              AND older.kind IN ('text', 'richText') AND newer.kind IN ('text', 'richText')
              AND older.id != newer.id
              AND (newer.captured_at > older.captured_at OR (newer.captured_at = older.captured_at AND newer.id > older.id))
            """
            try execute(mergeTagsSQL, on: database)

            let deleteTextDupSQL = """
            DELETE FROM history_items
            WHERE id IN (
                SELECT older.id FROM history_items older
                JOIN history_items newer ON older.text = newer.text
                  AND older.kind IN ('text', 'richText') AND newer.kind IN ('text', 'richText')
                  AND older.id != newer.id
                  AND (newer.captured_at > older.captured_at OR (newer.captured_at = older.captured_at AND newer.id > older.id))
            )
            """
            try execute(deleteTextDupSQL, on: database)

            let mergeURLTagsSQL = """
            INSERT OR IGNORE INTO history_tags (item_id, tag)
            SELECT newer.id, older_tags.tag
            FROM history_tags older_tags
            JOIN history_items older ON older_tags.item_id = older.id
            JOIN history_items newer ON older.text = newer.text
              AND older.kind = 'url' AND newer.kind = 'url'
              AND older.id != newer.id
              AND (newer.captured_at > older.captured_at OR (newer.captured_at = older.captured_at AND newer.id > older.id))
            """
            try execute(mergeURLTagsSQL, on: database)

            let deleteURLDupSQL = """
            DELETE FROM history_items
            WHERE id IN (
                SELECT older.id FROM history_items older
                JOIN history_items newer ON older.text = newer.text
                  AND older.kind = 'url' AND newer.kind = 'url'
                  AND older.id != newer.id
                  AND (newer.captured_at > older.captured_at OR (newer.captured_at = older.captured_at AND newer.id > older.id))
            )
            """
            try execute(deleteURLDupSQL, on: database)

            try execute("COMMIT", on: database)
        } catch {
            try? execute("ROLLBACK", on: database)
            throw error
        }
    }

    private static func bindStatic(_ value: String?, to index: Int32, in statement: OpaquePointer) {
        guard let value else { sqlite3_bind_null(statement, index); return }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, index, value, -1, transient)
    }

    private static func healLegacyOCRTexts(_ database: OpaquePointer) throws {
        var selectStmt: OpaquePointer?
        let selectSQL = "SELECT id, ocr_text FROM history_items WHERE ocr_text IS NOT NULL AND length(ocr_text) > 0"
        guard sqlite3_prepare_v2(database, selectSQL, -1, &selectStmt, nil) == SQLITE_OK, let selectStmt else { return }
        defer { sqlite3_finalize(selectStmt) }

        var toUpdate: [(String, String)] = []
        while sqlite3_step(selectStmt) == SQLITE_ROW {
            if let idPtr = sqlite3_column_text(selectStmt, 0),
               let ocrPtr = sqlite3_column_text(selectStmt, 1) {
                let id = String(cString: idPtr)
                let ocr = String(cString: ocrPtr)
                let formatted = OCRTextFormatter.format(ocr)
                if formatted != ocr {
                    toUpdate.append((id, formatted))
                }
            }
        }

        if !toUpdate.isEmpty {
            try execute("BEGIN IMMEDIATE TRANSACTION", on: database)
            do {
                var updateStmt: OpaquePointer?
                let updateSQL = "UPDATE history_items SET ocr_text = ? WHERE id = ?"
                if sqlite3_prepare_v2(database, updateSQL, -1, &updateStmt, nil) == SQLITE_OK, let updateStmt {
                    defer { sqlite3_finalize(updateStmt) }
                    for (id, formatted) in toUpdate {
                        sqlite3_reset(updateStmt)
                        sqlite3_clear_bindings(updateStmt)
                        bindStatic(formatted, to: 1, in: updateStmt)
                        bindStatic(id, to: 2, in: updateStmt)
                        sqlite3_step(updateStmt)
                    }
                }
                try execute("COMMIT", on: database)
            } catch {
                try? execute("ROLLBACK", on: database)
                throw error
            }
        }
    }

    private static func execute(_ sql: String, on database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw databaseError(database) }
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw HistoryStoreError.open("数据库未打开") }
        try Self.execute(sql, on: database)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else { throw HistoryStoreError.open("数据库未打开") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw databaseError() }
        return statement
    }

    private func bind(_ value: String?, to index: Int32, in statement: OpaquePointer) {
        guard let value else { sqlite3_bind_null(statement, index); return }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, index, value, -1, transient)
    }

    private func bind(_ data: Data?, to index: Int32, in statement: OpaquePointer) {
        guard let data else { sqlite3_bind_null(statement, index); return }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        data.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(statement, index, rawBuffer.baseAddress, Int32(data.count), transient)
        }
    }

    private func columnString(_ statement: OpaquePointer, at index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }

    private func columnBlob(_ statement: OpaquePointer, at index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let bytes = sqlite3_column_blob(statement, index) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        return Data(bytes: bytes, count: count)
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func databaseError() -> HistoryStoreError {
        guard let database else { return .open("数据库未打开") }
        return Self.databaseError(database)
    }

    private static func databaseError(_ database: OpaquePointer) -> HistoryStoreError {
        .database(String(cString: sqlite3_errmsg(database)))
    }
}
