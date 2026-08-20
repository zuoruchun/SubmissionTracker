import Foundation
import SwiftData

// MARK: - CloudKit-safe string collections
//
// CloudKit 不支持 SwiftData 对 [String] 的原生编码（会退化成不透明的
// Codable 属性，且旧版本 iOS 上可能不可同步）。这里用两个显式命名、
// 可 Codable 的结构体包装字符串数组，CloudKit 会将其作为复合属性存储，
// 在 macOS 14 / iOS 17 上可正常同步。

struct StringList: Codable, Hashable, Sendable {
    var items: [String]

    init(_ items: [String] = []) {
        self.items = items
    }
}

extension StringList: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: String...) {
        self.items = elements
    }
}

// MARK: - Manuscript

@Model
final class Manuscript {
    @Attribute(.externalStorage) var fileBookmark: Data
    var id: UUID
    var title: String
    var venue: String
    var manuscriptNumber: String = ""
    var submissionSystemURL: String = ""
    var authorGuideURL: String = ""
    /// 存储枚举 rawValue（CloudKit 要求）；通过计算属性暴露枚举。
    var venueTypeRaw: String
    var submissionDate: Date
    var currentStatusRaw: String
    var filePath: String
    /// MVP：备注以 Markdown 源文本存储，后续可升级为分块富文本。
    var notes: String
    var collaborators: StringList
    var tags: StringList
    var deadlineDate: Date?
    var createdAt: Date
    var updatedAt: Date

    // 关系：一篇稿件 -> 多条状态记录 / 多个附件。
    // CloudKit 要求 to-many 用可选集合。
    var statusLogs: [StatusLogEntry]?
    var attachments: [Attachment]?

    init(
        title: String,
        venue: String,
        venueType: VenueType = .journal,
        manuscriptNumber: String = "",
        submissionSystemURL: String = "",
        authorGuideURL: String = "",
        submissionDate: Date = .now,
        currentStatus: ManuscriptStatus = .draft,
        fileBookmark: Data = Data(),
        filePath: String = "",
        notes: String = "",
        collaborators: [String] = [],
        tags: [String] = [],
        deadlineDate: Date? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.venue = venue
        self.manuscriptNumber = manuscriptNumber
        self.submissionSystemURL = submissionSystemURL
        self.authorGuideURL = authorGuideURL
        self.venueTypeRaw = venueType.rawValue
        self.submissionDate = submissionDate
        self.currentStatusRaw = currentStatus.rawValue
        self.fileBookmark = fileBookmark
        self.filePath = filePath
        self.notes = notes
        self.collaborators = StringList(collaborators)
        self.tags = StringList(tags)
        self.deadlineDate = deadlineDate
        self.createdAt = .now
        self.updatedAt = .now
    }

    // 枚举视图
    var venueType: VenueType {
        get { VenueType(rawValue: venueTypeRaw) ?? .other }
        set { venueTypeRaw = newValue.rawValue }
    }

    var currentStatus: ManuscriptStatus {
        get { ManuscriptStatus(rawValue: currentStatusRaw) ?? .draft }
        set {
            currentStatusRaw = newValue.rawValue
            touch()
        }
    }

    /// 状态日志按时间倒序（最新在上）
    var sortedStatusLogs: [StatusLogEntry] {
        (statusLogs ?? []).sorted { $0.date > $1.date }
    }

    /// 附件按添加时间倒序
    var sortedAttachments: [Attachment] {
        (attachments ?? []).sorted { $0.addedDate > $1.addedDate }
    }

    /// 未归属于任何状态节点的独立附件
    var unassignedAttachments: [Attachment] {
        sortedAttachments.filter { $0.statusLog == nil }
    }

    /// 标记为被修改（刷新 updatedAt）
    func touch() {
        updatedAt = .now
    }

    /// 追加一条状态变更记录；若新状态与 currentStatus 不同，则同步更新当前状态。
    @discardableResult
    func appendStatusLog(
        _ newStatus: ManuscriptStatus,
        date: Date = .now,
        stage: String = "",
        note: String = "",
        context: ModelContext
    ) -> StatusLogEntry {
        let entry = StatusLogEntry(date: date, status: newStatus, stage: stage, note: note)
        if currentStatusRaw != newStatus.rawValue {
            currentStatusRaw = newStatus.rawValue
        }
        if statusLogs == nil { statusLogs = [] }
        statusLogs?.append(entry)
        entry.manuscript = self
        touch()
        try? context.save()
        return entry
    }
}

// MARK: - StatusLogEntry

@Model
final class StatusLogEntry {
    var id: UUID
    var date: Date
    var statusRaw: String
    var stageRaw: String = ""
    var note: String
    var manuscript: Manuscript?
    var attachments: [Attachment]?

    init(
        date: Date = .now,
        status: ManuscriptStatus,
        stage: String = "",
        note: String = "",
        id: UUID = UUID()
    ) {
        self.id = id
        self.date = date
        self.statusRaw = status.rawValue
        self.stageRaw = stage
        self.note = note
    }

    var status: ManuscriptStatus {
        get { ManuscriptStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var stage: String {
        get { stageRaw }
        set { stageRaw = newValue }
    }

    var sortedAttachments: [Attachment] {
        (attachments ?? []).sorted { $0.addedDate > $1.addedDate }
    }
}

// MARK: - Attachment

@Model
final class Attachment {
    @Attribute(.externalStorage) var fileBookmark: Data
    var id: UUID
    var filePath: String
    var relativePath: String = ""
    var originalFileName: String = ""
    var displayName: String = ""
    var fileSize: Int64 = 0
    var sha256Hash: String = ""
    var mimeType: String = "application/pdf"
    var syncStateRaw: String = "local"
    var lastSyncedHash: String = ""
    var fileTypeRaw: String
    var addedDate: Date
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var manuscript: Manuscript?
    var statusLog: StatusLogEntry?

    init(
        fileBookmark: Data = Data(),
        filePath: String = "",
        relativePath: String = "",
        originalFileName: String = "",
        displayName: String = "",
        fileSize: Int64 = 0,
        sha256Hash: String = "",
        mimeType: String = "application/pdf",
        syncState: SyncState = .local,
        fileType: AttachmentFileType,
        addedDate: Date = .now,
        id: UUID = UUID()
    ) {
        self.id = id
        self.fileBookmark = fileBookmark
        self.filePath = filePath
        self.relativePath = relativePath
        self.originalFileName = originalFileName
        self.displayName = displayName
        self.fileSize = fileSize
        self.sha256Hash = sha256Hash
        self.mimeType = mimeType
        self.syncStateRaw = syncState.rawValue
        self.fileTypeRaw = fileType.rawValue
        self.addedDate = addedDate
        self.createdAt = addedDate
        self.updatedAt = addedDate
    }

    var fileType: AttachmentFileType {
        get { AttachmentFileType(rawValue: fileTypeRaw) ?? .supplementary }
        set { fileTypeRaw = newValue.rawValue }
    }

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .local }
        set { syncStateRaw = newValue.rawValue }
    }

    func touch() {
        updatedAt = .now
    }
}
