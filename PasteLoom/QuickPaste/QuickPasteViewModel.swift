import Foundation

@MainActor
protocol QuickPasteHistoryProviding: AnyObject {
    func quickSearch(_ query: String, limit: Int) async throws -> [HistoryItem]
    func copyForQuickPaste(_ item: HistoryItem) async throws
    func copyMultipleForQuickPaste(_ items: [HistoryItem]) async throws
    func thumbnail(for item: HistoryItem, maxPixelSize: Int) async -> Data?
    func imageMetadata(for item: HistoryItem) async -> ImageAssetInfo?
}

extension QuickPasteHistoryProviding {
    func imageMetadata(for item: HistoryItem) async -> ImageAssetInfo? { nil }

    func copyMultipleForQuickPaste(_ items: [HistoryItem]) async throws {
        if items.count == 1, let first = items.first {
            try await copyForQuickPaste(first)
        } else if !items.isEmpty {
            let combined = items.map { item in
                switch item.kind {
                case .text, .url, .richText: return item.text
                case .file: return item.files.map(\.url.path).joined(separator: "\n")
                case .image: return "[图片]"
                case .video: return item.files.first?.url.path ?? "[视频]"
                }
            }.joined(separator: "\n")
            let temporaryItem = HistoryItem(id: UUID(), kind: .text, text: combined, capturedAt: Date(),
                                            imageRelativePath: nil, contentHash: nil, files: [])
            try await copyForQuickPaste(temporaryItem)
        }
    }
}

@MainActor
final class QuickPasteViewModel: ObservableObject {
    @Published private(set) var query = ""
    @Published private(set) var results: [HistoryItem] = []
    @Published private(set) var selectedIndex = 0
    @Published private(set) var selectedIDs: [UUID] = []
    @Published private(set) var autoPasteEnabled = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var presentationID = UUID()
    @Published private(set) var keyboardNavigatedID: UUID?
    @Published var statusMessage: String?

    private let history: any QuickPasteHistoryProviding
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0

    init(history: any QuickPasteHistoryProviding) {
        self.history = history
    }

    var selectedItem: HistoryItem? {
        guard results.indices.contains(selectedIndex) else { return nil }
        return results[selectedIndex]
    }

    var itemsToPaste: [HistoryItem] {
        if selectedIDs.isEmpty {
            if let selectedItem { return [selectedItem] }
            return []
        }
        return selectedIDs.compactMap { id in results.first(where: { $0.id == id }) }
    }

    func isSelected(_ item: HistoryItem) -> Bool {
        selectedIDs.contains(item.id)
    }

    func toggleSelectCurrent() {
        guard let item = selectedItem else { return }
        toggleSelection(for: item)
    }

    func toggleSelection(for item: HistoryItem) {
        if let index = selectedIDs.firstIndex(of: item.id) {
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(item.id)
        }
    }

    func clearMultiSelection() {
        selectedIDs.removeAll()
    }

    func open() {
        reset()
        presentationID = UUID()
        updateQuery("")
    }

    func updateMode(autoPasteEnabled: Bool, accessibilityGranted: Bool) {
        self.autoPasteEnabled = autoPasteEnabled
        self.accessibilityGranted = accessibilityGranted
    }

    func updateQuery(_ value: String) {
        query = value
        selectedIndex = 0
        selectedIDs.removeAll()
        results = []
        searchGeneration += 1
        let generation = searchGeneration
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await history.quickSearch(value, limit: 40)
                guard !Task.isCancelled, generation == searchGeneration else { return }
                results = page
                clampSelection()
            } catch {
                guard !Task.isCancelled, generation == searchGeneration else { return }
                results = []
                selectedIndex = 0
                statusMessage = "搜索失败：\(error.localizedDescription)"
            }
        }
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { selectedIndex = 0; return }
        selectedIndex = min(max(selectedIndex + delta, 0), results.count - 1)
        keyboardNavigatedID = selectedItem?.id
    }

    func select(_ item: HistoryItem) {
        guard let index = results.firstIndex(where: { $0.id == item.id }) else { return }
        selectedIndex = index
    }

    func selectIndex(_ index: Int) {
        guard results.indices.contains(index) else { return }
        selectedIndex = index
    }

    func imageMetadata(for item: HistoryItem) async -> ImageAssetInfo? {
        await history.imageMetadata(for: item)
    }

    func reset() {
        searchTask?.cancel()
        searchTask = nil
        searchGeneration += 1
        query = ""
        results = []
        selectedIDs.removeAll()
        selectedIndex = 0
        keyboardNavigatedID = nil
        statusMessage = nil
    }

    func thumbnail(for item: HistoryItem, maxPixelSize: Int) async -> Data? {
        await history.thumbnail(for: item, maxPixelSize: maxPixelSize)
    }

    private func clampSelection() {
        selectedIndex = results.isEmpty ? 0 : min(selectedIndex, results.count - 1)
    }
}
