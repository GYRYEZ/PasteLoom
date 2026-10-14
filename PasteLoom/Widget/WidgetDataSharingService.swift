import Foundation

struct WidgetHistoryItem: Codable, Identifiable, Sendable {
    let id: UUID
    let kind: String
    let text: String
    let isFavorite: Bool
    let isPinned: Bool
    let isSnippet: Bool
    let tags: [String]
    let groupName: String?
}

struct WidgetPayload: Codable, Sendable {
    let updatedAt: Date
    let recentItems: [WidgetHistoryItem]
    let pinnedSnippets: [WidgetHistoryItem]
}

final class WidgetDataSharingService: Sendable {
    static let shared = WidgetDataSharingService()

    private init() {}

    var sharingFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("com.gyryez.pasteloom", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("widget_data.json")
    }

    func exportForWidget(repository: any HistoryRepository) async throws {
        let recents = try await repository.search(text: "", limit: 12, offset: 0, filter: .all)
        let allItems = try await repository.search(text: "", limit: 100, offset: 0, filter: .all)
        let snippets = allItems.filter { $0.isSnippet || $0.isPinned }

        let recentWidgetItems = recents.map { item in
            WidgetHistoryItem(
                id: item.id,
                kind: item.kind.rawValue,
                text: String(item.text.prefix(200)),
                isFavorite: item.isFavorite,
                isPinned: item.isPinned,
                isSnippet: item.isSnippet,
                tags: item.tags,
                groupName: item.groupName
            )
        }

        let snippetWidgetItems = snippets.prefix(12).map { item in
            WidgetHistoryItem(
                id: item.id,
                kind: item.kind.rawValue,
                text: String(item.text.prefix(200)),
                isFavorite: item.isFavorite,
                isPinned: item.isPinned,
                isSnippet: item.isSnippet,
                tags: item.tags,
                groupName: item.groupName
            )
        }

        let payload = WidgetPayload(
            updatedAt: Date(),
            recentItems: recentWidgetItems,
            pinnedSnippets: Array(snippetWidgetItems)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: sharingFileURL, options: .atomic)
    }

    func loadCurrentWidgetData() -> WidgetPayload? {
        guard let data = try? Data(contentsOf: sharingFileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetPayload.self, from: data)
    }
}
