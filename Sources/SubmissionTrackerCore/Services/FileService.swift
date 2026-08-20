import Foundation
import AppKit
import CryptoKit
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

/// 负责本地 App Managed 附件副本的管理、SHA-256 校验、安全覆盖与回滚、
/// 以及 security-scoped bookmark 解析与 Finder 交互。
public enum FileService {

    // MARK: - App Managed 目录体系

    /// Application Support 根目录（自动兼容沙盒与独立命令行编译环境）
    public static var appSupportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("SubmissionTracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 附件专用托管根目录: `Application Support/SubmissionTracker/Attachments/`
    public static var attachmentsDir: URL {
        let dir = appSupportDir.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 内部安全回收站目录: `Application Support/SubmissionTracker/.Trash/`
    public static var trashDir: URL {
        let dir = appSupportDir.appendingPathComponent(".Trash", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 将相对路径还原为当前设备上的绝对 URL
    public static func managedFileURL(for relativePath: String) -> URL {
        let trimmed = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if trimmed.hasPrefix("Attachments/") {
            let sub = String(trimmed.dropFirst("Attachments/".count))
            return attachmentsDir.appendingPathComponent(sub)
        }
        return attachmentsDir.appendingPathComponent(trimmed)
    }

    // MARK: - 托管文件导入信息

    public struct ManagedFileInfo: Sendable {
        public var relativePath: String
        public var originalFileName: String
        public var displayName: String
        public var fileSize: Int64
        public var sha256Hash: String
        public var mimeType: String
    }

    // MARK: - SHA-256 计算

    public static func computeSHA256(for fileURL: URL) -> (sha256: String, size: Int64)? {
        guard let stream = InputStream(url: fileURL) else { return nil }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        let bufferSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var totalSize: Int64 = 0

        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read > 0 {
                hasher.update(data: Data(buffer[0..<read]))
                totalSize += Int64(read)
            } else if read < 0 {
                return nil
            } else {
                break
            }
        }

        let digest = hasher.finalize()
        let hashString = digest.map { String(format: "%02x", $0) }.joined()
        return (hashString, totalSize)
    }

    // MARK: - 安全导入本地管理副本 (目标 A & C)

    /// 从外部源文件制作一份 App 托管副本至 Application Support，原文件保持只读且绝不改写。
    static func importManagedCopy(
        from sourceURL: URL,
        manuscriptID: UUID,
        statusLogID: UUID?,
        fileType: AttachmentFileType,
        customDisplayName: String? = nil
    ) throws -> ManagedFileInfo {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw NSError(domain: "FileService", code: 404, userInfo: [NSLocalizedDescriptionKey: "外部源文件不存在或无法读取"])
        }

        let origName = sourceURL.lastPathComponent
        let ext = sourceURL.pathExtension.isEmpty ? "pdf" : sourceURL.pathExtension

        // 确定槽位目录: Attachments/<manuscriptUUID>/<statusLogUUID-or-general>/
        let slotDirName = statusLogID?.uuidString ?? "general"
        let targetDir = attachmentsDir
            .appendingPathComponent(manuscriptID.uuidString, isDirectory: true)
            .appendingPathComponent(slotDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let slotFileName = "\(fileType.rawValue).\(ext)"
        let finalDestinationURL = targetDir.appendingPathComponent(slotFileName)
        let relativePath = "Attachments/\(manuscriptID.uuidString)/\(slotDirName)/\(slotFileName)"

        // 1. 复制到同目标目录下的临时文件
        let tmpFileName = ".tmp_\(UUID().uuidString)_\(slotFileName)"
        let tmpURL = targetDir.appendingPathComponent(tmpFileName)

        if FileManager.default.fileExists(atPath: tmpURL.path) {
            try? FileManager.default.removeItem(at: tmpURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: tmpURL)

        // 2. 校验 SHA-256 与文件大小
        guard let hashInfo = computeSHA256(for: tmpURL) else {
            try? FileManager.default.removeItem(at: tmpURL)
            throw NSError(domain: "FileService", code: 500, userInfo: [NSLocalizedDescriptionKey: "计算文件 SHA-256 校验和失败"])
        }

        // 3. 安全覆盖检测：若目标槽位已存在旧文件，将其移入 .Trash/ 暂存
        if FileManager.default.fileExists(atPath: finalDestinationURL.path) {
            let trashFileName = "\(Int(Date().timeIntervalSince1970))_\(manuscriptID.uuidString)_\(slotDirName)_\(slotFileName)"
            let trashURL = trashDir.appendingPathComponent(trashFileName)
            try? FileManager.default.moveItem(at: finalDestinationURL, to: trashURL)
        }

        // 4. 原子移动/替换为最终文件
        if FileManager.default.fileExists(atPath: finalDestinationURL.path) {
            _ = try FileManager.default.replaceItemAt(finalDestinationURL, withItemAt: tmpURL)
        } else {
            try FileManager.default.moveItem(at: tmpURL, to: finalDestinationURL)
        }

        let dispName = customDisplayName ?? (origName.isEmpty ? slotFileName : origName)
        let mime = ext.lowercased() == "pdf" ? "application/pdf" : "application/octet-stream"

        return ManagedFileInfo(
            relativePath: relativePath,
            originalFileName: origName,
            displayName: dispName,
            fileSize: hashInfo.size,
            sha256Hash: hashInfo.sha256,
            mimeType: mime
        )
    }

    // MARK: - 移除托管副本

    public static func deleteManagedCopy(for relativePath: String) {
        guard !relativePath.isEmpty else { return }
        let url = managedFileURL(for: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let trashName = "\(Int(Date().timeIntervalSince1970))_\(url.lastPathComponent)"
        let trashTarget = trashDir.appendingPathComponent(trashName)
        try? FileManager.default.moveItem(at: url, to: trashTarget)
    }

    // MARK: - 解析可访问的预览 URL (支持 Managed 路径与 Bookmark 懒兼容)

    static func resolveURL(for attachment: Attachment) -> URL? {
        if !attachment.relativePath.isEmpty {
            let managed = managedFileURL(for: attachment.relativePath)
            if FileManager.default.fileExists(atPath: managed.path) {
                return managed
            }
        }
        if let url = previewURL(bookmark: attachment.fileBookmark, fallbackPath: attachment.filePath) {
            return url
        }
        return nil
    }

    static func resolveURL(for manuscript: Manuscript) -> URL? {
        return previewURL(bookmark: manuscript.fileBookmark, fallbackPath: manuscript.filePath)
    }

    static func fileExists(for attachment: Attachment) -> Bool {
        guard let url = resolveURL(for: attachment) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Selection

    /// 弹出文件选择面板，返回 (bookmarkData, 展示用路径, 原 URL)。
    @discardableResult
    @MainActor
    static func chooseFile(
        allowedContentTypes: [UTType] = [.item, .content, .data, .pdf, .plainText, .rtf, .text, .json],
        allowsMultipleSelection: Bool = false
    ) async -> [(bookmark: Data, path: String, url: URL)]? {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.allowedContentTypes = allowedContentTypes
        panel.message = "选择要导入并关联的文件（PDF/TeX/图片等）"
        guard panel.runModal() == .OK else { return nil }
        return panel.urls.compactMap { url in
            makeBookmark(for: url).map { ($0, url.path, url) }
        }
        #else
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: false)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = DocumentPickerDelegate.shared
        guard let root = currentKeyWindowScene?.keyWindow?.rootViewController ?? currentKeyWindowScene?.windows.first?.rootViewController else { return nil }
        root.present(picker, animated: true)
        return await DocumentPickerDelegate.shared.waitForResult()
        #endif
    }

    #if os(iOS)
    private static var currentKeyWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
    #endif

    // MARK: - Bookmarks (兼容层)

    static func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil)
    }

    static func resolvedURL(fromBookmark data: Data) -> URL? {
        guard !data.isEmpty else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if url.startAccessingSecurityScopedResource() {
            url.stopAccessingSecurityScopedResource()
        }
        return url
    }

    static func contents(forBookmark data: Data) -> Data? {
        guard let url = resolvedURL(fromBookmark: data) else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }

    static func previewURL(bookmark: Data, fallbackPath: String) -> URL? {
        if let url = resolvedURL(fromBookmark: bookmark) { return url }
        if !fallbackPath.isEmpty, FileManager.default.fileExists(atPath: fallbackPath) {
            return URL(fileURLWithPath: fallbackPath)
        }
        return nil
    }

    // MARK: - Finder / Files / Open External

    static func reveal(url: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }

    static func openExternally(url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    static func reveal(bookmark: Data, fallbackPath: String) {
        #if os(macOS)
        if let url = resolvedURL(fromBookmark: bookmark) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        if !fallbackPath.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: fallbackPath)])
        }
        #endif
    }
}

// MARK: - iOS document picker delegate

#if os(iOS)
final class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    static let shared = DocumentPickerDelegate()
    private var continuation: CheckedContinuation<[(bookmark: Data, path: String)], Never>?

    func presentPicker(from viewController: UIViewController) async -> [(bookmark: Data, path: String)]? {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .plainText, .text], asCopy: false)
        picker.delegate = self
        viewController.present(picker, animated: true)
        return await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }

    func waitForResult() async -> [(bookmark: Data, path: String)]? {
        await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }

    private func finish(_ results: [(bookmark: Data, path: String)]?) {
        if let cont = continuation {
            continuation = nil
            cont.resume(returning: results)
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let results = urls.compactMap { url -> (bookmark: Data, path: String)? in
            guard let b = FileService.makeBookmark(for: url) else { return nil }
            return (b, url.path)
        }
        controller.dismiss(animated: true)
        finish(results)
    }

    func documentPickerDidCancel(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true)
        finish(nil)
    }
}
#endif
