import AppKit
import Foundation
import SQLite3
import XCTest
@testable import PasteLoom

final class SQLiteHistoryRepositoryTests: XCTestCase {
    func testLargeHistoryPagingKeepsOrderAndUniqueSelectionIds() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteHistoryRepository(url: url)
        for index in 0..<220 {
            try await repository.insert(content: .text("entry \(index)"),
                                        at: Date(timeIntervalSince1970: Double(index + 1)))
        }
        let first = try await repository.search(text: "", limit: 100, offset: 0)
        let second = try await repository.search(text: "", limit: 100, offset: 100)
        let third = try await repository.search(text: "", limit: 100, offset: 200)
        XCTAssertEqual([first.count, second.count, third.count], [100, 100, 20])
        let all = first + second + third
        XCTAssertEqual(Set(all.map(\.id)).count, 220)
        XCTAssertEqual(all.first?.text, "entry 219")
        XCTAssertEqual(all.last?.text, "entry 0")
    }

    func testPinFavoriteAndTrashCoexistAcrossReopen() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteHistoryRepository(url: url)
        try await repository.insert(content: .text("older pinned"), at: Date(timeIntervalSince1970: 1))
        try await repository.insert(content: .text("newer"), at: Date(timeIntervalSince1970: 2))
        let found = try await repository.search(text: "older", limit: 10, offset: 0)
        let older = try XCTUnwrap(found.first)
        try await repository.setPinned(true, for: older.id)
        try await repository.setFavorite(true, for: older.id)

        let reopened = try SQLiteHistoryRepository(url: url)
        let ordered = try await reopened.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(ordered.first?.id, older.id)
        XCTAssertTrue(ordered[0].isPinned)
        XCTAssertTrue(ordered[0].isFavorite)
        try await reopened.moveToTrash(id: older.id)
        let visibleAfterDelete = try await reopened.search(text: "", limit: 10, offset: 0)
        XCTAssertFalse(visibleAfterDelete.contains { $0.id == older.id })
        try await reopened.restore(id: older.id)
        let restored = try SQLiteHistoryRepository(url: url)
        let again = try await restored.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(again.first?.id, older.id)
        XCTAssertTrue(again[0].isPinned && again[0].isFavorite)
        try await restored.setPinned(false, for: older.id)
        let unpinned = try SQLiteHistoryRepository(url: url)
        let final = try await unpinned.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(final.first?.text, "newer")
        XCTAssertTrue(final.last?.isFavorite == true)
    }

    func testMultipleTagAnyAllAndFullTextCombination() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteHistoryRepository(url: url)
        for (index, title) in ["alpha A", "alpha B", "alpha AB", "other AB"].enumerated() {
            try await repository.insert(content: .text(title), at: Date(timeIntervalSince1970: Double(index + 1)))
        }
        let items = try await repository.search(text: "", limit: 10, offset: 0)
        for item in items {
            let tags = item.text.hasSuffix("AB") ? ["A", "B"] : item.text.hasSuffix("A") ? ["A"] : ["B"]
            try await repository.setTags(tags, for: item.id)
        }
        let reopened = try SQLiteHistoryRepository(url: url)
        var scope = HistoryScope.unrestricted
        scope.tags = ["A", "B"]
        let any = try await reopened.search(text: "", limit: 10, offset: 0,
                                            filter: .all, mode: .fullText, scope: scope)
        XCTAssertEqual(any.count, 4)
        scope.tagMatch = .all
        let all = try await reopened.search(text: "", limit: 10, offset: 0,
                                            filter: .all, mode: .fullText, scope: scope)
        XCTAssertEqual(Set(all.map(\.text)), ["alpha AB", "other AB"])
        let combined = try await reopened.search(text: "alpha", limit: 10, offset: 0,
                                                 filter: .all, mode: .fullText, scope: scope)
        XCTAssertEqual(combined.map(\.text), ["alpha AB"])
        scope.tags = []
        let cleared = try await reopened.search(text: "alpha", limit: 10, offset: 0,
                                                filter: .all, mode: .fullText, scope: scope)
        XCTAssertEqual(cleared.count, 3)
    }

    func testFavoritePinOrderingAndRemovalPersistAcrossReopen() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteHistoryRepository(url: url)
        try await repository.insert(content: .text("older"), at: Date(timeIntervalSince1970: 1))
        try await repository.insert(content: .text("newer"), at: Date(timeIntervalSince1970: 2))
        let original = try await repository.search(text: "", limit: 10, offset: 0)
        let older = try XCTUnwrap(original.first(where: { $0.text == "older" }))
        try await repository.setFavorite(true, for: older.id)
        try await repository.setPinned(true, for: older.id)
        let reopened = try SQLiteHistoryRepository(url: url)
        let favorites = try await reopened.search(text: "", limit: 10, offset: 0, filter: .favorites)
        XCTAssertEqual(favorites.map(\.id), [older.id])
        let pinnedFirst = try await reopened.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(pinnedFirst.first?.id, older.id)
        try await reopened.setFavorite(false, for: older.id)
        try await reopened.setPinned(false, for: older.id)
        let again = try SQLiteHistoryRepository(url: url)
        let noFavorites = try await again.search(text: "", limit: 10, offset: 0, filter: .favorites)
        let unpinnedOrder = try await again.search(text: "", limit: 10, offset: 0)
        XCTAssertTrue(noFavorites.isEmpty)
        XCTAssertEqual(unpinnedOrder.first?.text, "newer")
    }

    func testTagsCanBeCreatedAssignedSearchedAndRemoved() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteHistoryRepository(url: url)
        try await repository.insert(content: .text("card"), at: Date(timeIntervalSince1970: 1))
        let original = try await repository.search(text: "", limit: 10, offset: 0)
        let item = try XCTUnwrap(original.first)
        try await repository.setTags(["work", "ideas", "work"], for: item.id)
        let reopened = try SQLiteHistoryRepository(url: url)
        let tagged = try await reopened.search(text: "", limit: 10, offset: 0)
        let ideas = try await reopened.search(text: "ideas", limit: 10, offset: 0,
                                              filter: .all, mode: .tags)
        XCTAssertEqual(tagged.first?.tags, ["ideas", "work"])
        XCTAssertEqual(ideas.map(\.id), [item.id])
        try await reopened.setTags(["work"], for: item.id)
        let removedIdea = try await reopened.search(text: "ideas", limit: 10, offset: 0,
                                                    filter: .all, mode: .tags)
        XCTAssertTrue(removedIdea.isEmpty)
        try await reopened.setTags([], for: item.id)
        let noTags = try await reopened.search(text: "", limit: 10, offset: 0,
                                               filter: .all, mode: .tags)
        XCTAssertTrue(noTags.isEmpty)
    }

    func testFullTextIncludesFileNameURLAndSourceMetadata() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteHistoryRepository(url: url)
        try await repository.insert(content: .url("https://example.com/path"),
                                    at: Date(timeIntervalSince1970: 1),
                                    source: CaptureSource(name: "Safari", bundleIdentifier: "com.apple.Safari"))
        let file = FileReference(url: directory.appendingPathComponent("report.pdf"),
                                 name: "report.pdf", fileExtension: "pdf", typeIdentifier: nil)
        try await repository.insert(content: .files([file]), at: Date(timeIntervalSince1970: 2))
        let sourceMatches = try await repository.search(text: "Safari", limit: 10, offset: 0)
        let urlMatches = try await repository.search(text: "example.com", limit: 10, offset: 0)
        let fileMatches = try await repository.search(text: "report.pdf", limit: 10, offset: 0)
        XCTAssertEqual(sourceMatches.count, 1)
        XCTAssertEqual(urlMatches.count, 1)
        XCTAssertEqual(fileMatches.count, 1)
    }

    func testImageMetadataReadsPersistedAssetWithoutLoadingFullImageIntoView() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteHistoryRepository(url: url)
        let image = try XCTUnwrap(ImageNormalizer.normalize(TestImage.makePNG()))
        try await repository.insert(content: .image(image), at: Date())
        let items = try await repository.search(text: "", limit: 10, offset: 0)
        let path = try XCTUnwrap(items.first?.imageRelativePath)
        let metadata = await ImageThumbnailStore(root: directory).metadata(relativePath: path)
        XCTAssertEqual(metadata?.pixelWidth, image.pixelWidth)
        XCTAssertEqual(metadata?.pixelHeight, image.pixelHeight)
        XCTAssertEqual(metadata?.byteCount, Int64(image.pngData.count))
    }

    func testV5ReopenKeepsHistoryWithoutSchemaChange() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteHistoryRepository(url: url)
        try await repository.insert(content: .text("existing history"), at: Date())
        XCTAssertEqual(sqliteScalar(url: url, sql: "PRAGMA user_version"), "7")
        let reopened = try SQLiteHistoryRepository(url: url)
        XCTAssertEqual(sqliteScalar(url: url, sql: "PRAGMA user_version"), "7")
        let retained = try await reopened.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(sqliteScalar(url: url, sql: "PRAGMA quick_check"), "ok")
    }
    func testCombinedTypeSourceAndDateFilters() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteHistoryRepository(url: url)
        try await repository.insert(content: .text("shared keyword"), at: Date(timeIntervalSince1970: 10),
                                    source: CaptureSource(name: "TextEdit", bundleIdentifier: "com.apple.TextEdit"))
        try await repository.insert(content: .url("https://example.com/keyword"), at: Date(timeIntervalSince1970: 20),
                                    source: CaptureSource(name: "Safari", bundleIdentifier: "com.apple.Safari"))
        try await repository.insert(content: .url("https://example.com/keyword2"), at: Date(timeIntervalSince1970: 30),
                                    source: CaptureSource(name: "Chrome", bundleIdentifier: "com.google.Chrome"))
        let scope = HistoryScope(kind: .url, sourceName: "Safari", since: Date(timeIntervalSince1970: 15))
        let result = try await repository.search(text: "keyword", limit: 10, offset: 0,
                                                 filter: .all, mode: .fullText, scope: scope)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.sourceName, "Safari")
        let escapedSource = HistoryScope(kind: nil, sourceName: "%", since: nil)
        let noWildcard = try await repository.search(text: "", limit: 10, offset: 0,
                                                     filter: .all, mode: .fullText, scope: escapedSource)
        XCTAssertTrue(noWildcard.isEmpty)
    }

    func testV1MigrationPreservesTextAndIntegrity() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle, "CREATE TABLE history_items (id TEXT PRIMARY KEY, text TEXT NOT NULL, captured_at REAL NOT NULL); CREATE INDEX history_items_time ON history_items (captured_at DESC, id DESC); INSERT INTO history_items VALUES ('00000000-0000-0000-0000-000000000001', 'Round 1 original', 1); PRAGMA user_version = 1;", nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)
        handle = nil

        let repository = try SQLiteHistoryRepository(url: url)
        let items = try await repository.search(text: "original", limit: 10, offset: 0)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.kind, .text)
        XCTAssertEqual(items.first?.text, "Round 1 original")
        let verification = sqliteScalar(url: url, sql: "PRAGMA user_version")
        XCTAssertEqual(verification, "7")
        let integrity = sqliteScalar(url: url, sql: "PRAGMA integrity_check")
        XCTAssertEqual(integrity, "ok")
    }

    func testURLAndMultiFilePersistAcrossReopenAndSearch() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try SQLiteHistoryRepository(url: url)
        try await first.insert(content: .url("https://example.com/pasteloom-next-round2"), at: Date(timeIntervalSince1970: 1))
        let files = [
            FileReference(url: directory.appendingPathComponent("first.txt"), name: "first.txt", fileExtension: "txt", typeIdentifier: "public.plain-text"),
            FileReference(url: directory.appendingPathComponent("missing.pdf"), name: "missing.pdf", fileExtension: "pdf", typeIdentifier: nil)
        ]
        try await first.insert(content: .files(files), at: Date(timeIntervalSince1970: 2))
        let reopened = try SQLiteHistoryRepository(url: url)
        let urlResult = try await reopened.search(text: "example.com", limit: 10, offset: 0)
        XCTAssertEqual(urlResult.first?.kind, .url)
        XCTAssertEqual(urlResult.first?.text, "https://example.com/pasteloom-next-round2")
        let fileResult = try await reopened.search(text: "pdf", limit: 10, offset: 0)
        XCTAssertEqual(fileResult.count, 1)
        XCTAssertEqual(fileResult.first?.kind, .file)
        XCTAssertEqual(fileResult.first?.files, files)
        XCTAssertEqual(fileResult.first?.files.count, 2)
        XCTAssertFalse(files[1].isAvailable)
    }

    func testV2MigrationPreservesExistingImageAndTextRows() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        let setup = """
        CREATE TABLE history_items (id TEXT PRIMARY KEY, text TEXT NOT NULL, captured_at REAL NOT NULL,
            kind TEXT NOT NULL DEFAULT 'text', asset_path TEXT, content_hash TEXT, search_text TEXT NOT NULL DEFAULT '');
        CREATE INDEX history_items_time ON history_items (captured_at DESC, id DESC);
        CREATE TABLE file_references (item_id TEXT NOT NULL REFERENCES history_items(id) ON DELETE CASCADE,
            position INTEGER NOT NULL, url TEXT NOT NULL, name TEXT NOT NULL, file_extension TEXT NOT NULL,
            type_identifier TEXT, PRIMARY KEY(item_id, position));
        INSERT INTO history_items VALUES ('00000000-0000-0000-0000-000000000001', 'old text', 1, 'text', NULL, NULL, 'old text');
        INSERT INTO history_items VALUES ('00000000-0000-0000-0000-000000000002', '', 2, 'image', 'Assets/Images/old.png', 'oldhash', '');
        PRAGMA user_version = 2;
        """
        XCTAssertEqual(sqlite3_exec(handle, setup, nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)
        let repository = try SQLiteHistoryRepository(url: url)
        let items = try await repository.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.kind), [.image, .text])
        XCTAssertEqual(sqliteScalar(url: url, sql: "PRAGMA user_version"), "7")
        XCTAssertEqual(sqliteScalar(url: url, sql: "PRAGMA quick_check"), "ok")
    }

    func testImageHashDeduplicatesRepresentationAndPromotesExistingItem() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let png = TestImage.makePNG()
        let tiff = NSBitmapImageRep(data: png)!.tiffRepresentation!
        guard let firstImage = ImageNormalizer.normalize(png),
              let secondImage = ImageNormalizer.normalize(tiff) else { return XCTFail("Image normalization failed") }
        XCTAssertEqual(firstImage.pixelHash, secondImage.pixelHash)

        let repository = try SQLiteHistoryRepository(url: url)
        try await repository.insert(content: .image(firstImage), at: Date(timeIntervalSince1970: 1))
        try await repository.insert(content: .image(secondImage), at: Date(timeIntervalSince1970: 2))
        let reopened = try SQLiteHistoryRepository(url: url)
        let items = try await reopened.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.map(\.kind), [.image])
        XCTAssertEqual(items[0].capturedAt, Date(timeIntervalSince1970: 2))
        let path = try XCTUnwrap(items[0].imageRelativePath)
        let storedData = try await reopened.imageData(relativePath: path)
        XCTAssertEqual(storedData, firstImage.pngData)
        let assets = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Assets/Images").path)
        XCTAssertEqual(assets.count, 1)

        try await reopened.delete(id: items[0].id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(path).path))
    }

    func testDifferentImagesInRapidSequenceRemainDistinct() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteHistoryRepository(url: url)
        let first = try XCTUnwrap(ImageNormalizer.normalize(TestImage.makePNG(color: .red)))
        let second = try XCTUnwrap(ImageNormalizer.normalize(TestImage.makePNG(color: .blue)))
        XCTAssertNotEqual(first.pixelHash, second.pixelHash)
        try await repository.insert(content: .image(first), at: Date(timeIntervalSince1970: 1))
        try await repository.insert(content: .image(second), at: Date(timeIntervalSince1970: 1.1))
        let items = try await repository.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(Set(items.compactMap(\.contentHash)).count, 2)
    }

    func testSameImageCopiedLaterMovesExistingRecordWithoutGrowth() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteHistoryRepository(url: url)
        let image = try XCTUnwrap(ImageNormalizer.normalize(TestImage.makePNG()))
        try await repository.insert(content: .image(image), at: Date(timeIntervalSince1970: 1))
        try await repository.insert(content: .text("between"), at: Date(timeIntervalSince1970: 2))
        try await repository.insert(content: .image(image), at: Date(timeIntervalSince1970: 600))
        let items = try await repository.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.kind, .image)
        XCTAssertEqual(items.first?.capturedAt, Date(timeIntervalSince1970: 600))
    }

    func testConcurrentRepositoriesUpsertOneImage() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try SQLiteHistoryRepository(url: url)
        let second = try SQLiteHistoryRepository(url: url)
        let image = try XCTUnwrap(ImageNormalizer.normalize(TestImage.makePNG()))
        async let one = first.insert(content: .image(image), at: Date(timeIntervalSince1970: 1))
        async let two = second.insert(content: .image(image), at: Date(timeIntervalSince1970: 2))
        try await one
        try await two
        let items = try await first.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.capturedAt, Date(timeIntervalSince1970: 2))
        XCTAssertEqual(sqliteScalar(url: url, sql: "PRAGMA quick_check"), "ok")
    }

    func testV3MigrationArchivesPriorImageDuplicatesAndAddsUniqueConstraint() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        let setup = """
        CREATE TABLE history_items (id TEXT PRIMARY KEY, text TEXT NOT NULL, captured_at REAL NOT NULL,
            kind TEXT NOT NULL DEFAULT 'text', asset_path TEXT, content_hash TEXT, search_text TEXT NOT NULL DEFAULT '');
        CREATE INDEX history_items_time ON history_items (captured_at DESC, id DESC);
        CREATE INDEX history_items_image_fingerprint ON history_items (content_hash, captured_at DESC) WHERE kind = 'image';
        CREATE TABLE file_references (item_id TEXT NOT NULL REFERENCES history_items(id) ON DELETE CASCADE,
            position INTEGER NOT NULL, url TEXT NOT NULL, name TEXT NOT NULL, file_extension TEXT NOT NULL,
            type_identifier TEXT, PRIMARY KEY(item_id, position));
        INSERT INTO history_items VALUES ('00000000-0000-0000-0000-000000000001', '', 1, 'image', 'Assets/Images/a.png', 'same', '');
        INSERT INTO history_items VALUES ('00000000-0000-0000-0000-000000000002', '', 2, 'image', 'Assets/Images/a.png', 'same', '');
        INSERT INTO history_items VALUES ('00000000-0000-0000-0000-000000000003', 'keep text', 3, 'text', NULL, NULL, 'keep text');
        PRAGMA user_version = 3;
        """
        XCTAssertEqual(sqlite3_exec(handle, setup, nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)
        let repository = try SQLiteHistoryRepository(url: url)
        let items = try await repository.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.filter { $0.kind == .image }.count, 1)
        XCTAssertEqual(sqliteScalar(url: url, sql: "SELECT count(*) FROM archived_duplicate_images"), "1")
        XCTAssertEqual(sqliteScalar(url: url, sql: "PRAGMA user_version"), "7")
        XCTAssertEqual(sqliteScalar(url: url, sql: "PRAGMA quick_check"), "ok")
        var verificationHandle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &verificationHandle), SQLITE_OK)
        let duplicateInsert = "INSERT INTO history_items (id, text, captured_at, kind, asset_path, content_hash, search_text) VALUES ('00000000-0000-0000-0000-000000000004', '', 4, 'image', 'Assets/Images/a.png', 'same', '')"
        XCTAssertEqual(sqlite3_exec(verificationHandle, duplicateInsert, nil, nil, nil), SQLITE_CONSTRAINT)
        sqlite3_close(verificationHandle)
    }

    func testFavoritePinTagsTrashAndSourceSurviveReload() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteHistoryRepository(url: url)
        try await repository.insert(content: .text("design note"), at: Date(timeIntervalSince1970: 1),
                                    source: CaptureSource(name: "TextEdit", bundleIdentifier: "com.apple.TextEdit"))
        let initialItems = try await repository.search(text: "", limit: 10, offset: 0)
        let original = try XCTUnwrap(initialItems.first)
        try await repository.setFavorite(true, for: original.id)
        try await repository.setPinned(true, for: original.id)
        try await repository.setTags(["work", "design"], for: original.id)
        let reopened = try SQLiteHistoryRepository(url: url)
        let favoriteItems = try await reopened.search(text: "work", limit: 10, offset: 0, filter: .favorites)
        let favorite = try XCTUnwrap(favoriteItems.first)
        XCTAssertTrue(favorite.isFavorite)
        XCTAssertTrue(favorite.isPinned)
        XCTAssertEqual(favorite.tags, ["design", "work"])
        XCTAssertEqual(favorite.sourceName, "TextEdit")
        XCTAssertEqual(favorite.sourceBundleIdentifier, "com.apple.TextEdit")
        let tagOnly = try await reopened.search(text: "work", limit: 10, offset: 0,
                                                filter: .all, mode: .tags)
        XCTAssertEqual(tagOnly.map(\.id), [original.id])
        let textNotTag = try await reopened.search(text: "note", limit: 10, offset: 0,
                                                   filter: .all, mode: .tags)
        XCTAssertTrue(textNotTag.isEmpty)
        try await reopened.moveToTrash(id: original.id)
        let activeItems = try await reopened.search(text: "", limit: 10, offset: 0)
        XCTAssertTrue(activeItems.isEmpty)
        let trashItems = try await reopened.search(text: "", limit: 10, offset: 0, filter: .trash)
        XCTAssertEqual(trashItems.count, 1)
        try await reopened.restore(id: original.id)
        let restoredItems = try await reopened.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(restoredItems.count, 1)
        XCTAssertEqual(sqliteScalar(url: url, sql: "PRAGMA quick_check"), "ok")
    }

    func testSameTextCopiedLaterMovesExistingRecordToTopWithoutGrowth() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteHistoryRepository(url: url)
        try await repository.insert(content: .text("first item"), at: Date(timeIntervalSince1970: 1))
        try await repository.insert(content: .text("second item"), at: Date(timeIntervalSince1970: 2))
        try await repository.insert(content: .text("first item"), at: Date(timeIntervalSince1970: 3))
        let items = try await repository.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].text, "first item")
        XCTAssertEqual(items[0].capturedAt, Date(timeIntervalSince1970: 3))
        XCTAssertEqual(items[1].text, "second item")
    }

    func testSameURLCopiedLaterMovesExistingRecordToTopWithoutGrowth() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteHistoryRepository(url: url)
        try await repository.insert(content: .url("https://apple.com"), at: Date(timeIntervalSince1970: 1))
        try await repository.insert(content: .url("https://swift.org"), at: Date(timeIntervalSince1970: 2))
        try await repository.insert(content: .url("https://apple.com"), at: Date(timeIntervalSince1970: 3))
        let items = try await repository.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].text, "https://apple.com")
        XCTAssertEqual(items[0].capturedAt, Date(timeIntervalSince1970: 3))
        XCTAssertEqual(items[1].text, "https://swift.org")
    }

    func testRichTextAndPlainTextDeduplicateAndPromote() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteHistoryRepository(url: url)
        let rtfSample = "rtf payload".data(using: .utf8)!
        try await repository.insert(content: .text("sample shared text"), at: Date(timeIntervalSince1970: 1))
        try await repository.insert(content: .richText(plain: "sample shared text", rtfData: rtfSample), at: Date(timeIntervalSince1970: 2))
        let items = try await repository.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].kind, .richText)
        XCTAssertEqual(items[0].rtfData, rtfSample)
        XCTAssertEqual(items[0].capturedAt, Date(timeIntervalSince1970: 2))
    }

    func testTextDeduplicationPreservesTagsFavoritesPinsAndRestoresFromTrash() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteHistoryRepository(url: url)
        let originalID = try await repository.insert(content: .text("custom tracked note"), at: Date(timeIntervalSince1970: 1))
        try await repository.setFavorite(true, for: originalID)
        try await repository.setPinned(true, for: originalID)
        try await repository.setTags(["work", "pinned-tag"], for: originalID)
        try await repository.moveToTrash(id: originalID)

        let activeBefore = try await repository.search(text: "", limit: 10, offset: 0)
        XCTAssertTrue(activeBefore.isEmpty)

        let reinsertedID = try await repository.insert(content: .text("custom tracked note"), at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(reinsertedID, originalID)

        let activeAfter = try await repository.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(activeAfter.count, 1)
        let item = try XCTUnwrap(activeAfter.first)
        XCTAssertEqual(item.id, originalID)
        XCTAssertTrue(item.isFavorite)
        XCTAssertTrue(item.isPinned)
        XCTAssertEqual(item.tags, ["pinned-tag", "work"])
        XCTAssertEqual(item.capturedAt, Date(timeIntervalSince1970: 10))

        try await repository.addTags(["bonus"], for: originalID)
        let updated = try await repository.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(updated.first?.tags, ["bonus", "pinned-tag", "work"])
    }

    func testStartupCleansLegacyTextDuplicatesAndMergesMetadata() async throws {
        let (directory, url) = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstRepo = try SQLiteHistoryRepository(url: url)
        _ = try await firstRepo.insert(content: .text("dummy"), at: Date(timeIntervalSince1970: 1))

        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        let id1 = UUID().uuidString
        let id2 = UUID().uuidString
        let id3 = UUID().uuidString
        let rawSQL = """
        INSERT INTO history_items (id, text, captured_at, kind, search_text, favorite, pinned)
        VALUES ('\(id1)', 'SF0216069375564', 10, 'text', 'SF0216069375564', 0, 1);
        INSERT INTO history_items (id, text, captured_at, kind, search_text, favorite, pinned)
        VALUES ('\(id2)', 'SF0216069375564', 20, 'text', 'SF0216069375564', 1, 0);
        INSERT INTO history_items (id, text, captured_at, kind, search_text, favorite, pinned)
        VALUES ('\(id3)', 'SF0216069375564', 30, 'text', 'SF0216069375564', 0, 0);
        INSERT INTO history_tags (item_id, tag) VALUES ('\(id1)', 'from_id1');
        INSERT INTO history_tags (item_id, tag) VALUES ('\(id2)', 'from_id2');
        """
        XCTAssertEqual(sqlite3_exec(handle, rawSQL, nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)

        let cleanedRepo = try SQLiteHistoryRepository(url: url)
        let matches = try await cleanedRepo.search(text: "SF0216069375564", limit: 10, offset: 0)
        XCTAssertEqual(matches.count, 1)
        let surviving = try XCTUnwrap(matches.first)
        XCTAssertEqual(surviving.id.uuidString, id3)
        XCTAssertTrue(surviving.isPinned)
        XCTAssertTrue(surviving.isFavorite)
        XCTAssertEqual(surviving.tags, ["from_id1", "from_id2"])
        XCTAssertEqual(surviving.capturedAt, Date(timeIntervalSince1970: 30))
    }

    private func temporaryDatabase() -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (directory, directory.appendingPathComponent("history.sqlite3"))
    }

    private func sqliteScalar(url: URL, sql: String) -> String? {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else { return nil }
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let pointer = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: pointer)
    }
}
