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

    /// 标记为被修改（刷新 updatedAt）
    func touch() {
        updatedAt = .now
    }

    /// 追加一条状态变更记录；若新状态与 currentStatus 不同，则同步更新当前状态。
    func appendStatusLog(_ newStatus: ManuscriptStatus, note: String = "", context: ModelContext) {
        let entry = StatusLogEntry(date: .now, status: newStatus, note: note)
        if currentStatusRaw != newStatus.rawValue {
            currentStatusRaw = newStatus.rawValue
        }
        if statusLogs == nil { statusLogs = [] }
        statusLogs?.append(entry)
        entry.manuscript = self
        touch()
        try? context.save()
    }
}

// MARK: - StatusLogEntry

@Model
final class StatusLogEntry {
    var id: UUID
    var date: Date
    var statusRaw: String
    var note: String
    var manuscript: Manuscript?

    init(date: Date = .now, status: ManuscriptStatus, note: String = "") {
        self.id = UUID()
        self.date = date
        self.statusRaw = status.rawValue
        self.note = note
    }

    var status: ManuscriptStatus {
        get { ManuscriptStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }
}

// MARK: - Attachment

@Model
final class Attachment {
    @Attribute(.externalStorage) var fileBookmark: Data
    var id: UUID
    var filePath: String
    var fileTypeRaw: String
    var addedDate: Date
    var manuscript: Manuscript?

    init(
        fileBookmark: Data,
        filePath: String,
        fileType: AttachmentFileType,
        addedDate: Date = .now,
        id: UUID = UUID()
    ) {
        self.id = id
        self.fileBookmark = fileBookmark
        self.filePath = filePath
        self.fileTypeRaw = fileType.rawValue
        self.addedDate = addedDate
    }

    var fileType: AttachmentFileType {
        get { AttachmentFileType(rawValue: fileTypeRaw) ?? .supplementary }
        set { fileTypeRaw = newValue.rawValue }
    }
}
