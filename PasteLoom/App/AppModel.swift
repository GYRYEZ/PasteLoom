import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject, QuickPasteHistoryProviding {
    @Published private(set) var items: [HistoryItem] = []
    @Published private(set) var isCapturing = false
    @Published private(set) var hasMore = false
    @Published private(set) var autoPasteEnabled = UserDefaults.standard.object(forKey: "autoPasteEnabled") == nil ? true : UserDefaults.standard.bool(forKey: "autoPasteEnabled")
    @Published private(set) var pollInterval = ClipboardService.pollingInterval
    @Published var searchText = ""
    @Published var selectedFilter: HistoryFilter = .all
    @Published var searchMode: HistorySearchMode = .fullText
    @Published var searchScope: HistoryScope = .unrestricted
    @Published var errorMessage: String?

    private let clipboard: ClipboardService
    let repository: any HistoryRepository
    private let search: LocalHistorySearch
    private let thumbnails: ImageThumbnailStore
    private let settings = UserDefaults.standard
    private let pageSize = 40
    private let storageAvailable: Bool
    private var ownsCapture = false
    private var searchGeneration = 0
    private var isLoading = false
    private var memoryPressureSource: (any DispatchSourceMemoryPressure)?

    init() {
        let storedInterval = UserDefaults.standard.double(forKey: "pollInterval")
        let interval = [0.2, 0.3, 0.5, 1.0].contains(storedInterval)
            ? storedInterval : ClipboardService.pollingInterval
        let clipboard = ClipboardService(pasteboard: SystemContentPasteboard(), interval: interval)
        self.clipboard = clipboard
        let databaseURL = try? SQLiteHistoryRepository.defaultURL()
        self.thumbnails = ImageThumbnailStore(root: databaseURL?.deletingLastPathComponent() ?? FileManager.default.temporaryDirectory)
        do {
            let repository = try SQLiteHistoryRepository(url: databaseURL ?? SQLiteHistoryRepository.defaultURL())
            self.repository = repository
            self.search = LocalHistorySearch(repository: repository)
            self.storageAvailable = true
        } catch {
            let unavailable = UnavailableHistoryRepository()
            self.repository = unavailable
            self.search = LocalHistorySearch(repository: unavailable)
            self.storageAvailable = false
            self.errorMessage = "无法打开本地历史数据库：\(error.localizedDescription)"
        }
        clipboard.onCapture = { [weak self] input in
            self?.saveCaptured(input)
        }
        pollInterval = interval

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            self?.trimMemory()
        }
        source.resume()
        self.memoryPressureSource = source

        refresh()
    }

    deinit {
        memoryPressureSource?.cancel()
    }

    func beginCaptureAsOwner() {
        guard storageAvailable, !ownsCapture else { return }
        ownsCapture = true
        if settings.object(forKey: "captureEnabled") as? Bool ?? true {
            clipboard.start()
            isCapturing = true
        }
        Task { await RetentionEngine.shared.checkAndRunPeriodicRetention(repository: self.repository) }
    }

    func setCaptureEnabled(_ enabled: Bool) {
        guard storageAvailable, ownsCapture else {
            errorMessage = "此实例无法获得剪贴板监听权限。"
            return
        }
        settings.set(enabled, forKey: "captureEnabled")
        if enabled { clipboard.start() } else { clipboard.stop() }
        isCapturing = enabled
    }

    func setAutoPasteEnabled(_ enabled: Bool) {
        settings.set(enabled, forKey: "autoPasteEnabled")
        autoPasteEnabled = enabled
    }

    func setPollInterval(_ interval: TimeInterval) {
        guard [0.2, 0.3, 0.5, 1.0].contains(interval) else { return }
        settings.set(interval, forKey: "pollInterval")
        pollInterval = interval
        clipboard.setPollingInterval(interval)
    }

    func copy(_ item: HistoryItem) {
        Task {
            do {
                try await copyForQuickPaste(item)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func quickSearch(_ query: String, limit: Int = 40) async throws -> [HistoryItem] {
        try await search.page(query: query, limit: limit)
    }

    func copyForQuickPaste(_ item: HistoryItem) async throws {
        let content: ClipboardWriteContent
        switch item.kind {
        case .text:
            content = .text(item.text)
        case .richText:
            if let rtf = item.rtfData {
                content = .richText(plain: item.text, rtfData: rtf)
            } else {
                content = .text(item.text)
            }
        case .url:
            content = .url(item.text)
        case .image:
            guard let path = item.imageRelativePath else { throw CopyBackError.imageUnavailable }
            content = .image(try await repository.imageData(relativePath: path))
        case .file, .video:
            guard !item.files.isEmpty, item.files.allSatisfy(\.isAvailable) else {
                throw CopyBackError.fileUnavailable
            }
            content = .files(item.files.map(\.url))
        }
        guard clipboard.copyToPasteboard(content) else { throw CopyBackError.writeFailed }
        try? await repository.incrementCopyCount(for: item.id)
    }

    func performOCR(for item: HistoryItem) {
        Task {
            _ = await performOCRAsync(for: item)
        }
    }

    @discardableResult
    func performOCRAsync(for item: HistoryItem) async -> String? {
        if item.kind != .image {
            let textToCopy: String
            switch item.kind {
            case .text, .richText, .url:
                textToCopy = item.text
            case .file:
                textToCopy = item.files.map(\.url.path).joined(separator: "\n")
            default:
                textToCopy = item.text
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(textToCopy, forType: .string)
            try? await repository.incrementCopyCount(for: item.id)
            return textToCopy
        }

        if let existing = item.ocrText, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let formatted = OCRTextFormatter.format(existing)
            if formatted != existing {
                try? await repository.updateOCRText(formatted, for: item.id)
                await MainActor.run {
                    if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                        self.items[idx].ocrText = formatted
                    }
                }
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(formatted, forType: .string)
            try? await repository.incrementCopyCount(for: item.id)
            return formatted
        }

        guard let data = await originalImageData(for: item) else {
            errorMessage = "找不到该图片的原始数据以执行文字识别。"
            return nil
        }
        do {
            let text = try await VisionOCRService.shared.recognizeText(from: data)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                try await repository.updateOCRText(text, for: item.id)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                try? await repository.incrementCopyCount(for: item.id)
                await MainActor.run {
                    if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                        self.items[idx].ocrText = text
                    }
                }
                return text
            } else {
                errorMessage = "未能从该图片中识别到文字。"
                return nil
            }
        } catch {
            errorMessage = "文字识别失败：\(error.localizedDescription)"
            return nil
        }
    }

    func recognizeOCRText(for item: HistoryItem) async -> String? {
        if item.kind != .image {
            return item.text
        }
        if let existing = item.ocrText, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let formatted = OCRTextFormatter.format(existing)
            if formatted != existing {
                try? await repository.updateOCRText(formatted, for: item.id)
                await MainActor.run {
                    if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                        self.items[idx].ocrText = formatted
                    }
                }
            }
            return formatted
        }
        guard let data = await originalImageData(for: item) else {
            return nil
        }
        do {
            let text = try await VisionOCRService.shared.recognizeText(from: data)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                try? await repository.updateOCRText(text, for: item.id)
                await MainActor.run {
                    if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                        self.items[idx].ocrText = text
                    }
                }
                return text
            }
            return nil
        } catch {
            return nil
        }
    }

    func thumbnail(for item: HistoryItem, maxPixelSize: Int) async -> Data? {
        guard let path = item.imageRelativePath else { return nil }
        return await thumbnails.thumbnail(relativePath: path, maxPixelSize: maxPixelSize)
    }

    func imageMetadata(for item: HistoryItem) async -> ImageAssetInfo? {
        guard let path = item.imageRelativePath else { return nil }
        return await thumbnails.metadata(relativePath: path)
    }

    func originalImageData(for item: HistoryItem) async -> Data? {
        guard let path = item.imageRelativePath else { return nil }
        return await thumbnails.originalData(relativePath: path)
    }

    func clearThumbnailMemoryCache() async {
        await thumbnails.clearCache()
    }

    func flushRepositoryMemory() async {
        await repository.flushMemory()
    }

    func trimMemory() {
        if items.count > pageSize {
            items = Array(items.prefix(pageSize))
            hasMore = true
        }
        ThumbnailImageCache.shared.clear()
        SemanticSearchEngine.shared.releaseEmbeddings()
        Task { [weak self] in
            await self?.clearThumbnailMemoryCache()
            await self?.flushRepositoryMemory()
        }
    }

    func toggleFavorite(_ item: HistoryItem) {
        Task { await updateItem { try await self.repository.setFavorite(!item.isFavorite, for: item.id) } }
    }

    func togglePinned(_ item: HistoryItem) {
        Task { await updateItem { try await self.repository.setPinned(!item.isPinned, for: item.id) } }
    }

    func setTags(_ tags: [String], for item: HistoryItem) {
        Task { await updateItem { try await self.repository.setTags(tags, for: item.id) } }
    }

    func moveToTrash(_ item: HistoryItem) {
        Task { await updateItem { try await self.repository.moveToTrash(id: item.id) } }
    }

    func restore(_ item: HistoryItem) {
        Task { await updateItem { try await self.repository.restore(id: item.id) } }
    }

    func toggleSnippet(_ item: HistoryItem) {
        Task { await updateItem { try await self.repository.setSnippet(!item.isSnippet, for: item.id) } }
    }

    func setGroup(_ groupName: String?, for item: HistoryItem) {
        Task { await updateItem { try await self.repository.setGroup(groupName, for: item.id) } }
    }

    func allGroups() async -> [String] {
        (try? await repository.allGroups()) ?? []
    }

    func mergeSelected(ids: [UUID], separator: String = "\n") async -> HistoryItem? {
        do {
            let merged = try await repository.merge(ids: ids, separator: separator)
            refresh()
            return merged
        } catch {
            errorMessage = "合并失败：\(error.localizedDescription)"
            return nil
        }
    }

    func fetchStatistics() async -> HistoryStatistics? {
        try? await repository.fetchStatistics()
    }

    func resetStatistics() async {
        do {
            try await repository.resetStatistics()
            refresh()
        } catch {
            errorMessage = "重置统计失败：\(error.localizedDescription)"
        }
    }

    func runRetentionNow() async -> RetentionReport? {
        do {
            let report = try await RetentionEngine.shared.runRetentionNow(repository: repository)
            refresh()
            return report
        } catch {
            errorMessage = "自动保留清理执行失败：\(error.localizedDescription)"
            return nil
        }
    }

    enum BatchAction {
        case favorite, pin, trash, restore, snippet, unSnippet, group(String?)
    }

    func performBatch(_ action: BatchAction, ids: Set<UUID>) {
        let selected = items.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }
        Task {
            do {
                for item in selected {
                    switch action {
                    case .favorite: try await repository.setFavorite(true, for: item.id)
                    case .pin: try await repository.setPinned(true, for: item.id)
                    case .trash: try await repository.moveToTrash(id: item.id)
                    case .restore: try await repository.restore(id: item.id)
                    case .snippet: try await repository.setSnippet(true, for: item.id)
                    case .unSnippet: try await repository.setSnippet(false, for: item.id)
                    case .group(let name): try await repository.setGroup(name, for: item.id)
                    }
                }
                refresh()
            } catch {
                errorMessage = "批量更新未全部完成：\(error.localizedDescription)"
                refresh()
            }
        }
    }

    private func updateItem(_ operation: @escaping () async throws -> Void) async {
        do { try await operation(); refresh() }
        catch { errorMessage = "无法更新历史：\(error.localizedDescription)" }
    }

    func refresh() {
        searchGeneration += 1
        let generation = searchGeneration
        let query = searchText
        let filter = selectedFilter
        let mode = searchMode
        let scope = searchScope
        Task {
            do {
                let page = try await search.page(query: query, limit: pageSize + 1, filter: filter, mode: mode, scope: scope)
                guard generation == searchGeneration else { return }
                items = Array(page.prefix(pageSize))
                hasMore = page.count > pageSize
            } catch {
                guard generation == searchGeneration else { return }
                errorMessage = "无法读取历史：\(error.localizedDescription)"
            }
        }
    }

    func loadMore() {
        guard hasMore, !isLoading else { return }
        isLoading = true
        let generation = searchGeneration
        let query = searchText
        let filter = selectedFilter
        let mode = searchMode
        let scope = searchScope
        let offset = items.count
        Task {
            defer { isLoading = false }
            do {
                let page = try await search.page(query: query, limit: pageSize + 1, offset: offset,
                                                 filter: filter, mode: mode, scope: scope)
                guard generation == searchGeneration else { return }
                items += page.prefix(pageSize)
                hasMore = page.count > pageSize
            } catch {
                guard generation == searchGeneration else { return }
                errorMessage = "无法继续读取历史：\(error.localizedDescription)"
            }
        }
    }

    private func saveCaptured(_ input: ClipboardInput) {
        let exclusions = CaptureTypeExclusions(
            text: settings.bool(forKey: "excludeTextCapture"),
            url: settings.bool(forKey: "excludeURLCapture"),
            image: settings.bool(forKey: "excludeImageCapture"),
            file: settings.bool(forKey: "excludeFileCapture")
        )
        guard !exclusions.excludes(input) else { return }
        let runningApp = NSWorkspace.shared.frontmostApplication
        let source = CaptureSource.resolve(displayName: runningApp?.localizedName,
                                           bundleIdentifier: runningApp?.bundleIdentifier)
        guard !CaptureFilterService.shared.shouldExclude(app: source) else { return }

        switch input {
        case .text(let text):
            guard !CaptureFilterService.shared.shouldExclude(text: text) else { return }
        case .richText(let plain, _):
            guard !CaptureFilterService.shared.shouldExclude(text: plain) else { return }
        default:
            break
        }

        var textForRules = ""
        var kindForRules: HistoryKind = .text
        switch input {
        case .text(let t): textForRules = t; kindForRules = .text
        case .richText(let t, _): textForRules = t; kindForRules = .richText
        case .url(let u): textForRules = u; kindForRules = .url
        case .files(let fs): textForRules = fs.map(\.name).joined(separator: " "); kindForRules = .file
        case .image: kindForRules = .image
        case .video(let v): textForRules = v.name; kindForRules = .video
        }

        let ruleOutcome = RuleEngine.shared.evaluate(text: textForRules, source: source, kind: kindForRules)
        if ruleOutcome.shouldDiscard {
            ExecutionLogService.shared.record(title: "规则丢弃", status: "已跳过", detail: "命中规则: \(ruleOutcome.matchedRuleNames.joined(separator: ", "))")
            return
        }

        Task {
            do {
                var processedInput = input
                if !ruleOutcome.scriptNamesToRun.isEmpty {
                    var scriptInput = textForRules
                    let allScripts = ScriptSandbox.shared.loadScripts()
                    for scriptName in ruleOutcome.scriptNamesToRun {
                        if let targetScript = allScripts.first(where: { $0.name == scriptName }) {
                            let result = await ScriptSandbox.shared.execute(code: targetScript.code, input: scriptInput)
                            if result.isSuccess {
                                scriptInput = result.output
                                ExecutionLogService.shared.record(title: "脚本执行: \(scriptName)", status: "成功", durationMs: result.durationMs, detail: "输入 \(textForRules.prefix(30))... -> 输出 \(result.output.prefix(30))...")
                            } else {
                                ExecutionLogService.shared.record(title: "脚本执行: \(scriptName)", status: "失败", durationMs: result.durationMs, detail: result.error ?? "执行异常")
                            }
                        }
                    }
                    if case .text = input {
                        processedInput = .text(scriptInput)
                    } else if case .richText(_, let rtf) = input {
                        processedInput = .richText(plain: scriptInput, rtfData: rtf)
                    }
                }

                let content: CapturedContent
                var imageForOCR: Data? = nil
                switch processedInput {
                case .text(let value):
                    content = .text(value)
                case .richText(let plain, let rtf):
                    content = .richText(plain: plain, rtfData: rtf)
                case .url(let value):
                    content = .url(settings.bool(forKey: "cleanURLs") ? URLCleaner.clean(value) : value)
                case .files(let values):
                    content = .files(values)
                case .video(let reference):
                    let meta = await VideoMetadataExtractor.extract(from: reference.url)
                    content = .video(reference, duration: meta.duration, thumbnail: meta.thumbnail)
                case .image(let data):
                    guard let normalized = await Task(priority: .utility, operation: {
                        ImageNormalizer.normalize(data)
                    }).value else {
                        errorMessage = "图片无法读取或尺寸过大，未加入历史。"
                        return
                    }
                    content = .image(normalized)
                    imageForOCR = normalized.pngData
                }
                let insertedID = try await repository.insert(content: content, at: Date(), source: source)

                // Apply rule actions directly to the newly inserted item
                if !ruleOutcome.tagsToAdd.isEmpty {
                    try? await repository.addTags(Array(ruleOutcome.tagsToAdd), for: insertedID)
                }
                if let grp = ruleOutcome.groupToSet {
                    try? await repository.setGroup(grp, for: insertedID)
                }
                if ruleOutcome.markFavorite {
                    try? await repository.setFavorite(true, for: insertedID)
                }
                if ruleOutcome.markPinned {
                    try? await repository.setPinned(true, for: insertedID)
                }
                if ruleOutcome.markSnippet {
                    try? await repository.setSnippet(true, for: insertedID)
                }
                if !ruleOutcome.matchedRuleNames.isEmpty {
                    ExecutionLogService.shared.record(title: "规则匹配入库", status: "成功", detail: "命中: \(ruleOutcome.matchedRuleNames.joined(separator: ", "))")
                }

                refresh()

                if let imageForOCR, settings.object(forKey: "autoOCR") as? Bool ?? true {
                    Task(priority: .utility) { [weak self] in
                        let recognizedText = try? await VisionOCRService.shared.recognizeText(from: imageForOCR)
                        guard let text = recognizedText,
                              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              let self else { return }
                        try? await self.repository.updateOCRText(text, for: insertedID)
                        await MainActor.run { [weak self] in
                            self?.refresh()
                        }
                    }
                }
            } catch {
                errorMessage = "无法保存剪贴板内容：\(error.localizedDescription)"
            }
        }
    }
}

private enum CopyBackError: LocalizedError {
    case imageUnavailable
    case fileUnavailable
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .imageUnavailable: "图片资源不可用，无法复制。"
        case .fileUnavailable: "原文件已移动或不存在，无法复制。"
        case .writeFailed: "无法将内容写入剪贴板。"
        }
    }
}

private actor UnavailableHistoryRepository: HistoryRepository {
    func insert(content: CapturedContent, at date: Date, source: CaptureSource?) throws -> UUID { throw HistoryStoreError.open("数据库不可用") }
    func search(text: String, limit: Int, offset: Int, filter: HistoryFilter) throws -> [HistoryItem] { throw HistoryStoreError.open("数据库不可用") }
    func search(text: String, limit: Int, offset: Int, filter: HistoryFilter, mode: HistorySearchMode) throws -> [HistoryItem] { throw HistoryStoreError.open("数据库不可用") }
    func search(text: String, limit: Int, offset: Int, filter: HistoryFilter, mode: HistorySearchMode,
                scope: HistoryScope) throws -> [HistoryItem] { throw HistoryStoreError.open("数据库不可用") }
    func imageData(relativePath: String) throws -> Data { throw HistoryStoreError.open("数据库不可用") }
    func setFavorite(_ favorite: Bool, for id: UUID) throws { throw HistoryStoreError.open("数据库不可用") }
    func setPinned(_ pinned: Bool, for id: UUID) throws { throw HistoryStoreError.open("数据库不可用") }
    func setTags(_ tags: [String], for id: UUID) throws { throw HistoryStoreError.open("数据库不可用") }
    func addTags(_ tags: [String], for id: UUID) throws { throw HistoryStoreError.open("数据库不可用") }
    func setSnippet(_ isSnippet: Bool, for id: UUID) throws { throw HistoryStoreError.open("数据库不可用") }
    func setGroup(_ groupName: String?, for id: UUID) throws { throw HistoryStoreError.open("数据库不可用") }
    func allGroups() throws -> [String] { throw HistoryStoreError.open("数据库不可用") }
    func incrementCopyCount(for id: UUID) throws { throw HistoryStoreError.open("数据库不可用") }
    func moveToTrash(id: UUID) throws { throw HistoryStoreError.open("数据库不可用") }
    func restore(id: UUID) throws { throw HistoryStoreError.open("数据库不可用") }
    func delete(id: UUID) throws { throw HistoryStoreError.open("数据库不可用") }
    func updateOCRText(_ ocrText: String, for id: UUID) throws { throw HistoryStoreError.open("数据库不可用") }
    func merge(ids: [UUID], separator: String) throws -> HistoryItem? { throw HistoryStoreError.open("数据库不可用") }
    func runRetention(retentionDays: Int, trashRetentionDays: Int) throws -> Int { throw HistoryStoreError.open("数据库不可用") }
    func fetchStatistics() throws -> HistoryStatistics { throw HistoryStoreError.open("数据库不可用") }
    func resetStatistics() throws { throw HistoryStoreError.open("数据库不可用") }
}
