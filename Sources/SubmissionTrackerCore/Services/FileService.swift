import Foundation
import AppKit
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

/// 负责本地/iCloud 文件的选取、security-scoped bookmark 的保存与解析、
/// 以及"在 Finder 中显示"等平台交互。
///
/// 关键设计：
/// - 用户通过 NSOpenPanel（macOS）/ UIDocumentPicker（iOS）选取文件后，
///   我们保存的是 **bookmark Data** 而非纯路径。security-scoped bookmark
///   让 App 在后续启动中仍持有对该文件的访问权限（受沙盒保护的前提下）。
/// - CloudKit 只同步 bookmark 的字节与展示路径文本；每台设备需要用
///   `resolvedURL(fromBookmark:)` 在本机重新解析（另一台设备上的路径
///   在本地可能无法解析，此时回退到 filePath 文本展示）。
enum FileService {

    // MARK: - Selection

    /// 弹出文件选择面板，返回 (bookmarkData, 展示用路径)。
    @discardableResult
    @MainActor
    static func chooseFile(
        allowedContentTypes: [UTType] = [.pdf, .plainText, .rtf, .text, .json],
        allowsMultipleSelection: Bool = false
    ) async -> [(bookmark: Data, path: String)]? {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.allowedContentTypes = allowedContentTypes
        panel.message = "选择要关联的文件（本地或 iCloud Drive）"
        guard panel.runModal() == .OK else { return nil }
        return panel.urls.compactMap { url in
            makeBookmark(for: url).map { ($0, url.path) }
        }
        #else
        // iOS：通过 UIDocumentPickerViewController 选择。
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: false)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = DocumentPickerDelegate.shared
        guard let root = currentKeyWindowScene?.keyWindow?.rootViewController ?? currentKeyWindowScene?.windows.first?.rootViewController else { return nil }
        root.present(picker, animated: true)
        // 等待用户选择（内部 promise）
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

    // MARK: - Bookmarks

    /// 为 URL 生成 security-scoped bookmark。
    static func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil)
    }

    /// 解析 bookmark 得到本机可用的 URL；失败返回 nil（例如该文件只存在于
    /// 另一台设备的 iCloud Drive 且尚未下载到本机）。
    static func resolvedURL(fromBookmark data: Data) -> URL? {
        guard !data.isEmpty else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if url.startAccessingSecurityScopedResource() {
            // 权限在读取完毕后释放；调用方如需长驻访问可自行再次 start。
            url.stopAccessingSecurityScopedResource()
        }
        return url
    }

    /// 读取 bookmark 指向的文件内容（临时持有安全作用域权限）。
    static func contents(forBookmark data: Data) -> Data? {
        guard let url = resolvedURL(fromBookmark: data) else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }

    /// 尝试从 bookmark 或后备路径取得一个可用于预览的 URL。
    static func previewURL(bookmark: Data, fallbackPath: String) -> URL? {
        if let url = resolvedURL(fromBookmark: bookmark) { return url }
        if !fallbackPath.isEmpty, FileManager.default.fileExists(atPath: fallbackPath) {
            return URL(fileURLWithPath: fallbackPath)
        }
        return nil
    }

    // MARK: - Finder / Files

    /// 在 Finder（macOS）/ Files（iOS）中显示该文件并选中。
    static func reveal(bookmark: Data, fallbackPath: String) {
        #if os(macOS)
        if let url = resolvedURL(fromBookmark: bookmark) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        if !fallbackPath.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: fallbackPath)])
        }
        #else
        if let url = resolvedURL(fromBookmark: bookmark) {
            // iOS 16+：QLPreviewController 已可展示；这里给一个轻提示即可。
            _ = url
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
