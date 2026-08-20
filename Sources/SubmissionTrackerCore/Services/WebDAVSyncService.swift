import Foundation
import SwiftUI
import SwiftData

/// 坚果云 / WebDAV 云同步服务
/// 支持标准 WebDAV 协议（Basic Auth，MKCOL 创建目录，PUT 上传备份，GET 下载恢复）
@MainActor
public final class WebDAVSyncService: ObservableObject {
    public static let shared = WebDAVSyncService()

    // MARK: - 存储 Keys
    private let kServerURL = "webdav_server_url"
    private let kUsername = "webdav_username"
    private let kPassword = "webdav_password"
    private let kRemoteDir = "webdav_remote_dir"
    private let kRemoteFile = "webdav_remote_file"
    private let kAutoSync = "webdav_auto_sync"
    private let kLastSyncDate = "webdav_last_sync_date"
    private let kLastSyncStatus = "webdav_last_sync_status"

    // MARK: - 响应式配置项
    @Published public var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: kServerURL) }
    }
    @Published public var username: String {
        didSet { UserDefaults.standard.set(username, forKey: kUsername) }
    }
    @Published public var password: String {
        didSet { UserDefaults.standard.set(password, forKey: kPassword) }
    }
    @Published public var remoteDirectory: String {
        didSet { UserDefaults.standard.set(remoteDirectory, forKey: kRemoteDir) }
    }
    @Published public var remoteFileName: String {
        didSet { UserDefaults.standard.set(remoteFileName, forKey: kRemoteFile) }
    }
    @Published public var autoSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(autoSyncEnabled, forKey: kAutoSync) }
    }
    @Published public var lastSyncDate: Date? {
        didSet { UserDefaults.standard.set(lastSyncDate, forKey: kLastSyncDate) }
    }
    @Published public var lastSyncStatus: String {
        didSet { UserDefaults.standard.set(lastSyncStatus, forKey: kLastSyncStatus) }
    }
    @Published public var isSyncing: Bool = false

    private init() {
        self.serverURL = UserDefaults.standard.string(forKey: kServerURL) ?? "https://dav.jianguoyun.com/dav/"
        self.username = UserDefaults.standard.string(forKey: kUsername) ?? ""
        self.password = UserDefaults.standard.string(forKey: kPassword) ?? ""
        self.remoteDirectory = UserDefaults.standard.string(forKey: kRemoteDir) ?? "SubmissionTracker"
        self.remoteFileName = UserDefaults.standard.string(forKey: kRemoteFile) ?? "backup.json"
        self.autoSyncEnabled = UserDefaults.standard.bool(forKey: kAutoSync)
        self.lastSyncDate = UserDefaults.standard.object(forKey: kLastSyncDate) as? Date
        self.lastSyncStatus = UserDefaults.standard.string(forKey: kLastSyncStatus) ?? "未同步"
    }

    // MARK: - 辅助计算

    private var cleanServerURL: URL? {
        var str = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !str.hasSuffix("/") { str += "/" }
        return URL(string: str)
    }

    private var fileURL: URL? {
        guard let base = cleanServerURL else { return nil }
        var dir = remoteDirectory.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if dir.isEmpty { dir = "SubmissionTracker" }
        var file = remoteFileName.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if file.isEmpty { file = "backup.json" }
        return base.appendingPathComponent(dir).appendingPathComponent(file)
    }

    private var directoryURL: URL? {
        guard let base = cleanServerURL else { return nil }
        var dir = remoteDirectory.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if dir.isEmpty { dir = "SubmissionTracker" }
        return base.appendingPathComponent(dir)
    }

    private var basicAuthHeader: String? {
        guard !username.isEmpty, !password.isEmpty else { return nil }
        let credentials = "\(username):\(password)"
        guard let data = credentials.data(using: .utf8) else { return nil }
        return "Basic \(data.base64EncodedString())"
    }

    // MARK: - 测试连接

    public func testConnection() async -> Result<String, Error> {
        guard let url = cleanServerURL else {
            return .failure(WebDAVError.invalidURL)
        }
        guard let auth = basicAuthHeader else {
            return .failure(WebDAVError.missingCredentials)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 207 || http.statusCode == 200 || http.statusCode == 301 || http.statusCode == 302 {
                    self.lastSyncStatus = "连接成功"
                    return .success("坚果云/WebDAV 连接正常！")
                } else if http.statusCode == 401 {
                    self.lastSyncStatus = "认证失败 (401)"
                    return .failure(WebDAVError.unauthorized)
                } else {
                    let msg = "服务器返回状态码: \(http.statusCode)"
                    self.lastSyncStatus = msg
                    return .failure(WebDAVError.serverError(msg))
                }
            }
            return .failure(WebDAVError.unknown)
        } catch {
            self.lastSyncStatus = "连接错误: \(error.localizedDescription)"
            return .failure(error)
        }
    }

    // MARK: - 确保远程目录存在 (MKCOL)

    private func ensureRemoteDirectory() async throws {
        guard let dirURL = directoryURL, let auth = basicAuthHeader else { return }
        var req = URLRequest(url: dirURL)
        req.httpMethod = "MKCOL"
        req.setValue(auth, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10

        let (_, res) = try await URLSession.shared.data(for: req)
        if let http = res as? HTTPURLResponse {
            // 201 Created 或者 405 Method Not Allowed (目录已存在)
            if http.statusCode == 201 || http.statusCode == 405 || http.statusCode == 200 {
                return
            }
        }
    }

    // MARK: - 上传备份至云端 (PUT)

    public func uploadBackup(from context: ModelContext) async -> Result<Date, Error> {
        guard let targetURL = fileURL else {
            return .failure(WebDAVError.invalidURL)
        }
        guard let auth = basicAuthHeader else {
            return .failure(WebDAVError.missingCredentials)
        }

        self.isSyncing = true
        defer { self.isSyncing = false }

        do {
            // 1. 获取所有稿件数据并序列化为 JSON
            let descriptor = FetchDescriptor<Manuscript>()
            let manuscripts = try context.fetch(descriptor)
            guard let jsonData = ExportService.backup(for: manuscripts) else {
                return .failure(WebDAVError.serializationFailed)
            }

            // 2. 确保远程目录存在
            try? await ensureRemoteDirectory()

            // 3. 上传文件
            var req = URLRequest(url: targetURL)
            req.httpMethod = "PUT"
            req.setValue(auth, forHTTPHeaderField: "Authorization")
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = jsonData
            req.timeoutInterval = 30

            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse {
                if (200...299).contains(http.statusCode) {
                    let now = Date()
                    self.lastSyncDate = now
                    self.lastSyncStatus = "已备份 (\(manuscripts.count) 篇稿件)"
                    return .success(now)
                } else if http.statusCode == 401 {
                    self.lastSyncStatus = "认证失败 (401)"
                    return .failure(WebDAVError.unauthorized)
                } else {
                    let msg = "上传失败状态码: \(http.statusCode)"
                    self.lastSyncStatus = msg
                    return .failure(WebDAVError.serverError(msg))
                }
            }
            return .failure(WebDAVError.unknown)
        } catch {
            self.lastSyncStatus = "上传失败: \(error.localizedDescription)"
            return .failure(error)
        }
    }

    // MARK: - 从云端拉取并恢复 (GET)

    public func downloadAndRestore(into context: ModelContext) async -> Result<Int, Error> {
        guard let targetURL = fileURL else {
            return .failure(WebDAVError.invalidURL)
        }
        guard let auth = basicAuthHeader else {
            return .failure(WebDAVError.missingCredentials)
        }

        self.isSyncing = true
        defer { self.isSyncing = false }

        do {
            var req = URLRequest(url: targetURL)
            req.httpMethod = "GET"
            req.setValue(auth, forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 404 {
                    self.lastSyncStatus = "云端未找到备份文件"
                    return .failure(WebDAVError.fileNotFound)
                } else if http.statusCode == 401 {
                    self.lastSyncStatus = "认证失败 (401)"
                    return .failure(WebDAVError.unauthorized)
                } else if !(200...299).contains(http.statusCode) {
                    let msg = "下载失败状态码: \(http.statusCode)"
                    self.lastSyncStatus = msg
                    return .failure(WebDAVError.serverError(msg))
                }
            }

            // 恢复入数据库
            let count = try ExportService.restore(from: data, into: context)
            let now = Date()
            self.lastSyncDate = now
            self.lastSyncStatus = "恢复成功 (\(count) 篇稿件)"
            return .success(count)
        } catch {
            self.lastSyncStatus = "恢复失败: \(error.localizedDescription)"
            return .failure(error)
        }
    }

    // MARK: - 触发自动同步（若已开启）

    public func autoSyncIfNeeded(context: ModelContext) {
        guard autoSyncEnabled, !username.isEmpty, !password.isEmpty else { return }
        Task {
            _ = await uploadBackup(from: context)
        }
    }
}

// MARK: - 错误定义

public enum WebDAVError: LocalizedError {
    case invalidURL
    case missingCredentials
    case unauthorized
    case fileNotFound
    case serializationFailed
    case serverError(String)
    case unknown

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 WebDAV 服务器 URL。"
        case .missingCredentials: return "请先填写账号与应用授权密码。"
        case .unauthorized: return "账号或应用密码错误（401 Unauthorized）。"
        case .fileNotFound: return "坚果云上尚未找到备份文件。"
        case .serializationFailed: return "数据序列化失败。"
        case .serverError(let msg): return "服务器错误: \(msg)"
        case .unknown: return "发生未知网络错误。"
        }
    }
}
