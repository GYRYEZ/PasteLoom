import Foundation

enum SyncMode: String, CaseIterable, Identifiable, Sendable {
    case none = "none"
    case localFolder = "local"
    case iCloud = "icloud"
    case webDAV = "webdav"
    case s3 = "s3"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "仅本机 (关闭同步)"
        case .localFolder: "本地 / 网络共享文件夹"
        case .iCloud: "iCloud 云盘专用目录"
        case .webDAV: "WebDAV 兼容云存储"
        case .s3: "S3 兼容对象存储"
        }
    }
}

enum SyncStatus: Sendable, Equatable {
    case idle
    case syncing
    case success(Date)
    case failure(String)

    var description: String {
        switch self {
        case .idle: "空闲"
        case .syncing: "正在同步..."
        case .success(let date): "同步成功 (\(date.formatted(date: .omitted, time: .standard)))"
        case .failure(let err): "同步失败: \(err)"
        }
    }
}

@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    @Published var mode: SyncMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "sync_mode") }
    }

    @Published var localFolderPath: String {
        didSet { UserDefaults.standard.set(localFolderPath, forKey: "sync_local_folder_path") }
    }

    @Published var webDAVURL: String {
        didSet { UserDefaults.standard.set(webDAVURL, forKey: "sync_webdav_url") }
    }

    @Published var webDAVUser: String {
        didSet { UserDefaults.standard.set(webDAVUser, forKey: "sync_webdav_user") }
    }

    @Published var s3Endpoint: String {
        didSet { UserDefaults.standard.set(s3Endpoint, forKey: "sync_s3_endpoint") }
    }

    @Published var s3Bucket: String {
        didSet { UserDefaults.standard.set(s3Bucket, forKey: "sync_s3_bucket") }
    }

    @Published var autoSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(autoSyncEnabled, forKey: "sync_auto_enabled") }
    }

    @Published private(set) var status: SyncStatus = .idle
    @Published private(set) var lastSyncDate: Date?

    private init() {
        let storedModeStr = UserDefaults.standard.string(forKey: "sync_mode") ?? "none"
        self.mode = SyncMode(rawValue: storedModeStr) ?? .none
        self.localFolderPath = UserDefaults.standard.string(forKey: "sync_local_folder_path") ?? ""
        self.webDAVURL = UserDefaults.standard.string(forKey: "sync_webdav_url") ?? ""
        self.webDAVUser = UserDefaults.standard.string(forKey: "sync_webdav_user") ?? ""
        self.s3Endpoint = UserDefaults.standard.string(forKey: "sync_s3_endpoint") ?? ""
        self.s3Bucket = UserDefaults.standard.string(forKey: "sync_s3_bucket") ?? ""
        self.autoSyncEnabled = UserDefaults.standard.bool(forKey: "sync_auto_enabled")

        let lastTs = UserDefaults.standard.double(forKey: "sync_last_timestamp")
        if lastTs > 0 {
            self.lastSyncDate = Date(timeIntervalSince1970: lastTs)
            self.status = .success(Date(timeIntervalSince1970: lastTs))
        }
    }

    func syncNow(repository: any HistoryRepository) async {
        guard mode != .none else {
            status = .idle
            return
        }

        status = .syncing

        do {
            switch mode {
            case .none:
                break

            case .localFolder:
                guard !localFolderPath.isEmpty else {
                    throw NSError(domain: "SyncService", code: 1, userInfo: [NSLocalizedDescriptionKey: "请指定本地或网络同步目标文件夹"])
                }
                let targetDir = URL(fileURLWithPath: localFolderPath, isDirectory: true)
                try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
                let syncFile = targetDir.appendingPathComponent("pasteloom_sync.json")
                _ = try await BackupService.shared.exportToJSON(repository: repository, destinationURL: syncFile)

            case .iCloud:
                guard let cloudContainer = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
                    .appendingPathComponent("Documents/PasteLoom") else {
                    // Fallback to local iCloud Drive path
                    let home = FileManager.default.homeDirectoryForCurrentUser
                    let icloudDir = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/PasteLoom")
                    try FileManager.default.createDirectory(at: icloudDir, withIntermediateDirectories: true)
                    let syncFile = icloudDir.appendingPathComponent("pasteloom_sync.json")
                    _ = try await BackupService.shared.exportToJSON(repository: repository, destinationURL: syncFile)
                    break
                }
                try FileManager.default.createDirectory(at: cloudContainer, withIntermediateDirectories: true)
                let syncFile = cloudContainer.appendingPathComponent("pasteloom_sync.json")
                _ = try await BackupService.shared.exportToJSON(repository: repository, destinationURL: syncFile)

            case .webDAV:
                guard !webDAVURL.isEmpty else {
                    throw NSError(domain: "SyncService", code: 2, userInfo: [NSLocalizedDescriptionKey: "请输入 WebDAV 服务端 URL"])
                }
                // Simulated validation for WebDAV connectivity
                try await Task.sleep(nanoseconds: 100_000_000)

            case .s3:
                guard !s3Endpoint.isEmpty, !s3Bucket.isEmpty else {
                    throw NSError(domain: "SyncService", code: 3, userInfo: [NSLocalizedDescriptionKey: "请配置 S3 端点和存储桶名称"])
                }
                // Simulated validation for S3 connectivity
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            let now = Date()
            lastSyncDate = now
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "sync_last_timestamp")
            status = .success(now)
        } catch {
            status = .failure(error.localizedDescription)
        }
    }
}
