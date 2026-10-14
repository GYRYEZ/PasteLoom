import Foundation

struct LocalHistorySearch {
    let repository: any HistoryRepository

    func page(query: String, limit: Int = 100, offset: Int = 0,
              filter: HistoryFilter = .all,
              mode: HistorySearchMode = .fullText,
              scope: HistoryScope = .unrestricted) async throws -> [HistoryItem] {
        try await repository.search(text: query, limit: limit, offset: offset, filter: filter, mode: mode, scope: scope)
    }
}
