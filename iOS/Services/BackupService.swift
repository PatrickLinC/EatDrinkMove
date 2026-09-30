import Foundation

// MARK: - 資料備份

/// 把這支 iPhone 上的資料打包成一個備份檔，換手機或刪掉 App 後可以還原：
/// - Application Support 整個資料夾：飲食、喝水、運動、體重紀錄（含照片）、路線、世界迷霧
/// - 設定與遊戲進度（UserDefaults）：精靈、元氣幣、營地、每週任務、目標與偏好
/// 不包含：鑰匙圈裡的 AI 金鑰（安全起見不匯出）、「健康」App 的資料（本來就在「健康」裡）
enum BackupService {
    struct Archive: Codable {
        var version = 1
        var created: Date
        var appVersion: String
        /// UserDefaults 的內容（二進位 plist）
        var defaults: Data
        /// Application Support 裡的檔案：相對路徑 → 內容
        var files: [String: Data]
    }

    enum BackupError: LocalizedError {
        case newerVersion

        var errorDescription: String? { "這個備份是新版 App 做的，請先更新 App 再還原。" }
    }

    static let lastBackupKey = "lastBackupDate"

    /// 還原要等下次打開 App、資料庫還沒開之前才搬進去
    private static var pendingURL: URL { URL.libraryDirectory.appending(path: "RestorePending") }

    // MARK: 匯出

    /// 先把還在記憶體裡的資料存好，再打包（檔案讀寫在背景做）
    @MainActor
    static func makeBackup() async throws -> URL {
        try? AppDatabase.context.save()
        WorldFogStore.shared.saveNow()
        // 先記下備份時間，還原後也看得到「上次備份」
        let previous = UserDefaults.standard.object(forKey: lastBackupKey)
        UserDefaults.standard.set(Date.now, forKey: lastBackupKey)
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        let defaults = try PropertyListSerialization.data(fromPropertyList: domain, format: .binary, options: 0)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        do {
            return try await writeArchive(defaults: defaults, version: version)
        } catch {
            UserDefaults.standard.set(previous, forKey: lastBackupKey)
            throw error
        }
    }

    private static func writeArchive(defaults: Data, version: String) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let archive = Archive(created: .now, appVersion: version, defaults: defaults, files: try readSupportFiles())
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmm"
            let url = FileManager.default.temporaryDirectory
                .appending(path: "\(AppBrand.name)備份-\(formatter.string(from: .now)).plist")
            try encoder.encode(archive).write(to: url, options: .atomic)
            return url
        }.value
    }

    private static func readSupportFiles() throws -> [String: Data] {
        let support = URL.applicationSupportDirectory.resolvingSymlinksInPath()
        let prefix = support.path(percentEncoded: false).hasSuffix("/")
            ? support.path(percentEncoded: false) : support.path(percentEncoded: false) + "/"
        var files: [String: Data] = [:]
        guard let enumerator = FileManager.default.enumerator(at: support, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return files
        }
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let path = url.resolvingSymlinksInPath().path(percentEncoded: false)
            guard path.hasPrefix(prefix) else { continue }
            files[String(path.dropFirst(prefix.count))] = try Data(contentsOf: url)
        }
        return files
    }

    // MARK: 還原

    /// 讀備份檔、放到暫存區，回傳備份的日期；下次打開 App 才真的換上去
    static func stageRestore(from url: URL) async throws -> Date {
        try await Task.detached(priority: .userInitiated) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let archive = try PropertyListDecoder().decode(Archive.self, from: Data(contentsOf: url))
            guard archive.version <= 1 else { throw BackupError.newerVersion }
            let manager = FileManager.default
            try? manager.removeItem(at: pendingURL)
            let files = pendingURL.appending(path: "files")
            try manager.createDirectory(at: files, withIntermediateDirectories: true)
            for (path, content) in archive.files {
                let target = files.appending(path: path)
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: target)
            }
            // defaults.plist 最後寫，有它才代表暫存區完整
            try archive.defaults.write(to: pendingURL.appending(path: "defaults.plist"))
            return archive.created
        }.value
    }

    static var hasPendingRestore: Bool {
        FileManager.default.fileExists(atPath: pendingURL.appending(path: "defaults.plist").path(percentEncoded: false))
    }

    /// App 一啟動、資料庫和各個存檔打開之前呼叫：把暫存區的備份換上去
    static func applyPendingRestore() {
        guard hasPendingRestore else { return }
        let manager = FileManager.default
        let support = URL.applicationSupportDirectory
        try? manager.createDirectory(at: support, withIntermediateDirectories: true)
        for item in (try? manager.contentsOfDirectory(at: support, includingPropertiesForKeys: nil)) ?? [] {
            try? manager.removeItem(at: item)
        }
        let files = pendingURL.appending(path: "files")
        for item in (try? manager.contentsOfDirectory(at: files, includingPropertiesForKeys: nil)) ?? [] {
            try? manager.moveItem(at: item, to: support.appending(path: item.lastPathComponent))
        }
        if let data = try? Data(contentsOf: pendingURL.appending(path: "defaults.plist")),
           let domain = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.setPersistentDomain(domain, forName: id)
        }
        try? manager.removeItem(at: pendingURL)
    }

    static func cancelPendingRestore() {
        try? FileManager.default.removeItem(at: pendingURL)
    }
}
