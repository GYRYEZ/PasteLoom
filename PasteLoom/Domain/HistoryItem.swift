import Foundation

enum HistoryKind: String, Sendable, CaseIterable {
    case text
    case url
    case image
    case file
    case richText
    case video
}

struct FileReference: Equatable, Sendable {
    let url: URL
    let name: String
    let fileExtension: String
    let typeIdentifier: String?

    var isAvailable: Bool { FileManager.default.fileExists(atPath: url.path) }
}

struct ImageContent: Sendable {
    let pngData: Data
    let pixelHash: String
    let pixelWidth: Int
    let pixelHeight: Int
}

enum CapturedContent: Sendable {
    case text(String)
    case url(String)
    case image(ImageContent)
    case files([FileReference])
    case richText(plain: String, rtfData: Data)
    case video(FileReference, duration: Double?, thumbnail: ImageContent? = nil)
}

struct CaptureSource: Sendable {
    let name: String
    let bundleIdentifier: String?

    static func resolve(displayName: String?, bundleIdentifier: String?,
                        ownBundleIdentifier: String? = nil) -> CaptureSource? {
        let own = ownBundleIdentifier ?? Bundle.main.bundleIdentifier ?? "com.gyryez.pasteloom"
        guard bundleIdentifier != own,
              bundleIdentifier != "com.gyryez.pasteloom",
              bundleIdentifier != "com.gyryez.pasteloom.next" else { return nil }
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return nil }
        return CaptureSource(name: name, bundleIdentifier: bundleIdentifier)
    }
}

enum HistoryFilter: Sendable, Equatable {
    case all
    case favorites
    case trash
}

enum HistorySearchMode: String, Sendable, Equatable, CaseIterable {
    case fullText = "fullText"
    case semantic = "semantic"
    case tags = "tags"
}

enum TagMatchMode: String, Sendable, Equatable {
    case any
    case all

    static func load(from defaults: UserDefaults) -> TagMatchMode {
        TagMatchMode(rawValue: defaults.string(forKey: "tagMatchMode") ?? "") ?? .any
    }
}

struct HistoryScope: Sendable, Equatable {
    var kind: HistoryKind?
    var sourceName: String = ""
    var since: Date?
    var tags: [String] = []
    var tagMatch: TagMatchMode = .any
    var groupName: String? = nil
    var isSnippet: Bool? = nil

    var hasFilters: Bool {
        kind != nil || !sourceName.isEmpty || since != nil || !tags.isEmpty || groupName != nil || isSnippet != nil
    }

    static let unrestricted = HistoryScope()
}

struct HistoryStatistics: Sendable, Equatable {
    var totalItems: Int
    var totalCopies: Int
    var textCount: Int
    var imageCount: Int
    var urlCount: Int
    var fileCount: Int
    var richTextCount: Int
    var videoCount: Int
    var snippetCount: Int
    var topCopied: [HistoryItem]
}

struct HistoryItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: HistoryKind
    let text: String
    let capturedAt: Date
    let imageRelativePath: String?
    let contentHash: String?
    let files: [FileReference]
    let isFavorite: Bool
    let isPinned: Bool
    let isDeleted: Bool
    let tags: [String]
    let sourceName: String?
    let sourceBundleIdentifier: String?
    var ocrText: String?
    let rtfData: Data?
    let isSnippet: Bool
    let groupName: String?
    let copyCount: Int

    init(id: UUID, kind: HistoryKind, text: String, capturedAt: Date,
         imageRelativePath: String?, contentHash: String?, files: [FileReference],
         isFavorite: Bool = false, isPinned: Bool = false, isDeleted: Bool = false,
         tags: [String] = [], sourceName: String? = nil, sourceBundleIdentifier: String? = nil,
         ocrText: String? = nil, rtfData: Data? = nil,
         isSnippet: Bool = false, groupName: String? = nil, copyCount: Int = 0) {
        self.id = id
        self.kind = kind
        self.text = text
        self.capturedAt = capturedAt
        self.imageRelativePath = imageRelativePath
        self.contentHash = contentHash
        self.files = files
        self.isFavorite = isFavorite
        self.isPinned = isPinned
        self.isDeleted = isDeleted
        self.tags = tags
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.ocrText = ocrText
        self.rtfData = rtfData
        self.isSnippet = isSnippet
        self.groupName = groupName
        self.copyCount = copyCount
    }
}

protocol HistoryRepository: Sendable {
    @discardableResult
    func insert(content: CapturedContent, at date: Date, source: CaptureSource?) async throws -> UUID
    func search(text: String, limit: Int, offset: Int) async throws -> [HistoryItem]
    func search(text: String, limit: Int, offset: Int, filter: HistoryFilter) async throws -> [HistoryItem]
    func search(text: String, limit: Int, offset: Int, filter: HistoryFilter,
                mode: HistorySearchMode) async throws -> [HistoryItem]
    func search(text: String, limit: Int, offset: Int, filter: HistoryFilter,
                mode: HistorySearchMode, scope: HistoryScope) async throws -> [HistoryItem]
    func imageData(relativePath: String) async throws -> Data
    func setFavorite(_ favorite: Bool, for id: UUID) async throws
    func setPinned(_ pinned: Bool, for id: UUID) async throws
    func setTags(_ tags: [String], for id: UUID) async throws
    func addTags(_ tags: [String], for id: UUID) async throws
    func setSnippet(_ isSnippet: Bool, for id: UUID) async throws
    func setGroup(_ groupName: String?, for id: UUID) async throws
    func allGroups() async throws -> [String]
    func incrementCopyCount(for id: UUID) async throws
    func moveToTrash(id: UUID) async throws
    func restore(id: UUID) async throws
    func delete(id: UUID) async throws
    func updateOCRText(_ ocrText: String, for id: UUID) async throws
    func merge(ids: [UUID], separator: String) async throws -> HistoryItem?
    func runRetention(retentionDays: Int, trashRetentionDays: Int) async throws -> Int
    func fetchStatistics() async throws -> HistoryStatistics
    func resetStatistics() async throws
    func flushMemory() async
}

extension HistoryRepository {
    func flushMemory() async {}
    @discardableResult
    func insert(content: CapturedContent, at date: Date) async throws -> UUID {
        try await insert(content: content, at: date, source: nil)
    }
    func search(text: String, limit: Int, offset: Int) async throws -> [HistoryItem] {
        try await search(text: text, limit: limit, offset: offset, filter: .all)
    }
    func search(text: String, limit: Int, offset: Int, filter: HistoryFilter) async throws -> [HistoryItem] {
        try await search(text: text, limit: limit, offset: offset, filter: filter, mode: .fullText)
    }
    func search(text: String, limit: Int, offset: Int, filter: HistoryFilter,
                mode: HistorySearchMode) async throws -> [HistoryItem] {
        try await search(text: text, limit: limit, offset: offset, filter: filter, mode: mode, scope: .unrestricted)
    }
}
