import Foundation
import SwiftData

/// 导出/备份服务：
/// - CSV：表格化的稿件清单
/// - Markdown：年度投稿总结风格报告
/// - JSON：全量数据备份（CloudKit 之外的保险），可再导入恢复。
public enum ExportService {

    // MARK: - CSV

    static func csv(for manuscripts: [Manuscript]) -> String {
        var lines: [String] = []
        lines.append(["标题", "期刊/会议", "类型", "投稿日期", "当前状态", "截止日期", "合作者", "标签"].joined(separator: ","))
        let fmt = ISO8601DateFormatter()
        for m in manuscripts.sorted(by: { $0.submissionDate > $1.submissionDate }) {
            let row = [
                m.title,
                m.venue,
                m.venueType.rawValue,
                fmt.string(from: m.submissionDate),
                m.currentStatus.rawValue,
                m.deadlineDate.map { fmt.string(from: $0) } ?? "",
                m.collaborators.items.joined(separator: "; "),
                m.tags.items.joined(separator: "; "),
            ].map { field in
                if field.contains(",") || field.contains("\"") || field.contains("\n") {
                    return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                }
                return field
            }
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Markdown 报告

    static func markdownReport(for manuscripts: [Manuscript]) -> String {
        var out: [String] = []
        out.append("# 论文投稿追踪报告")
        out.append("")
        out.append("_生成日期：\(Date.now.formatted(date: .long, time: .omitted))_")
        out.append("")

        // 统计概览
        let grouped = Dictionary(grouping: manuscripts, by: { $0.currentStatus })
        out.append("## 总览")
        out.append("")
        out.append("共 \(manuscripts.count) 篇稿件。")
        out.append("")
        for status in ManuscriptStatus.allCases {
            let n = grouped[status]?.count ?? 0
            if n > 0 {
                out.append("- \(status.displayNameZh)：\(n)")
            }
        }
        out.append("")

        // 按年份分组
        let byYear = Dictionary(grouping: manuscripts) {
            Calendar.current.component(.year, from: $0.submissionDate)
        }
        for (year, items) in byYear.sorted(by: { $0.key > $1.key }) {
            out.append("## \(year) 年")
            out.append("")
            for m in items.sorted(by: { $0.submissionDate > $1.submissionDate }) {
                out.append("### \(m.title)")
                out.append("- 目标：\(m.venue)（\(m.venueType.displayNameZh)）")
                out.append("- 投稿日期：\(m.submissionDate.formatted(date: .abbreviated, time: .omitted))")
                out.append("- 当前状态：\(m.currentStatus.displayNameZh)")
                if let deadline = m.deadlineDate {
                    out.append("- 下一步截止：\(deadline.formatted(date: .abbreviated, time: .omitted))")
                }
                if !m.collaborators.items.isEmpty {
                    out.append("- 合作者：\(m.collaborators.items.joined(separator: ", "))")
                }
                if !m.tags.items.isEmpty {
                    out.append("- 标签：\(m.tags.items.joined(separator: ", "))")
                }
                if !m.sortedStatusLogs.isEmpty {
                    out.append("")
                    out.append("状态时间线：")
                    for log in m.sortedStatusLogs {
                        out.append("- \(log.date.formatted(date: .abbreviated, time: .omitted)) — \(log.status.displayNameZh)\(log.note.isEmpty ? "" : "（\(log.note)）")")
                    }
                }
                out.append("")
            }
        }
        return out.joined(separator: "\n")
    }

    // MARK: - JSON 备份 (v2)

    /// 备份用的可序列化快照（包含稿件、状态节点及附件相对路径与哈希清单）。
    struct Backup: Codable {
        public var version: Int = 2
        public var exportedAt: Date
        public var manuscripts: [ManuscriptSnapshot]

        public struct ManuscriptSnapshot: Codable {
            public var id: UUID
            public var title: String
            public var venue: String
            public var venueTypeRaw: String
            public var manuscriptNumber: String?
            public var submissionSystemURL: String?
            public var authorGuideURL: String?
            public var submissionDate: Date
            public var currentStatusRaw: String
            public var filePath: String
            public var notes: String
            public var collaborators: [String]
            public var tags: [String]
            public var deadlineDate: Date?
            public var createdAt: Date
            public var updatedAt: Date
            public var statusLogs: [LogSnapshot]
            public var attachments: [AttachmentSnapshot]?

            public struct LogSnapshot: Codable {
                public var id: UUID
                public var date: Date
                public var statusRaw: String
                public var stageRaw: String?
                public var note: String
            }

            public struct AttachmentSnapshot: Codable {
                public var id: UUID
                public var statusLogId: UUID?
                public var relativePath: String
                public var originalFileName: String
                public var displayName: String
                public var fileTypeRaw: String
                public var fileSize: Int64
                public var sha256Hash: String
                public var mimeType: String
                public var addedDate: Date
                public var updatedAt: Date
            }
        }
    }

    static func backup(for manuscripts: [Manuscript]) -> Data? {
        let snapshot = Backup(
            version: 2,
            exportedAt: .now,
            manuscripts: manuscripts.map { m in
                Backup.ManuscriptSnapshot(
                    id: m.id,
                    title: m.title,
                    venue: m.venue,
                    venueTypeRaw: m.venueTypeRaw,
                    manuscriptNumber: m.manuscriptNumber,
                    submissionSystemURL: m.submissionSystemURL,
                    authorGuideURL: m.authorGuideURL,
                    submissionDate: m.submissionDate,
                    currentStatusRaw: m.currentStatusRaw,
                    filePath: m.filePath,
                    notes: m.notes,
                    collaborators: m.collaborators.items,
                    tags: m.tags.items,
                    deadlineDate: m.deadlineDate,
                    createdAt: m.createdAt,
                    updatedAt: m.updatedAt,
                    statusLogs: m.sortedStatusLogs.map { log in
                        Backup.ManuscriptSnapshot.LogSnapshot(
                            id: log.id,
                            date: log.date,
                            statusRaw: log.statusRaw,
                            stageRaw: log.stageRaw,
                            note: log.note
                        )
                    },
                    attachments: m.sortedAttachments.map { att in
                        Backup.ManuscriptSnapshot.AttachmentSnapshot(
                            id: att.id,
                            statusLogId: att.statusLog?.id,
                            relativePath: att.relativePath,
                            originalFileName: att.originalFileName,
                            displayName: att.displayName,
                            fileTypeRaw: att.fileTypeRaw,
                            fileSize: att.fileSize,
                            sha256Hash: att.sha256Hash,
                            mimeType: att.mimeType,
                            addedDate: att.addedDate,
                            updatedAt: att.updatedAt
                        )
                    }
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(snapshot)
    }

    /// 从备份 JSON 恢复（支持 v1 与 v2，按 UUID 与 updatedAt 安全 upsert）。
    @discardableResult
    public static func restore(from data: Data, into context: ModelContext) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Backup.self, from: data)

        let existing = try context.fetch(FetchDescriptor<Manuscript>())
        var existingMap = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        var restoredOrUpdated = 0
        for snap in backup.manuscripts {
            if let m = existingMap[snap.id] {
                // 已存在同 UUID 稿件：比较 updatedAt 做安全更新
                if snap.updatedAt > m.updatedAt {
                    m.title = snap.title
                    m.venue = snap.venue
                    m.venueTypeRaw = snap.venueTypeRaw
                    m.manuscriptNumber = snap.manuscriptNumber ?? ""
                    m.submissionSystemURL = snap.submissionSystemURL ?? ""
                    m.authorGuideURL = snap.authorGuideURL ?? ""
                    m.submissionDate = snap.submissionDate
                    m.currentStatusRaw = snap.currentStatusRaw
                    m.notes = snap.notes
                    m.collaborators = StringList(snap.collaborators)
                    m.tags = StringList(snap.tags)
                    m.deadlineDate = snap.deadlineDate
                    m.updatedAt = snap.updatedAt
                }

                // 补全缺失的状态日志
                var logMap = Dictionary(uniqueKeysWithValues: (m.statusLogs ?? []).map { ($0.id, $0) })
                for logSnap in snap.statusLogs where logMap[logSnap.id] == nil {
                    let entry = StatusLogEntry(
                        date: logSnap.date,
                        status: ManuscriptStatus(rawValue: logSnap.statusRaw) ?? .draft,
                        stage: logSnap.stageRaw ?? "",
                        note: logSnap.note,
                        id: logSnap.id
                    )
                    entry.manuscript = m
                    if m.statusLogs == nil { m.statusLogs = [] }
                    m.statusLogs?.append(entry)
                    logMap[entry.id] = entry
                }

                // 补全缺失的附件记录
                var attMap = Dictionary(uniqueKeysWithValues: (m.attachments ?? []).map { ($0.id, $0) })
                for attSnap in (snap.attachments ?? []) where attMap[attSnap.id] == nil {
                    let att = Attachment(
                        relativePath: attSnap.relativePath,
                        originalFileName: attSnap.originalFileName,
                        displayName: attSnap.displayName,
                        fileSize: attSnap.fileSize,
                        sha256Hash: attSnap.sha256Hash,
                        mimeType: attSnap.mimeType,
                        syncState: .synced,
                        fileType: AttachmentFileType(rawValue: attSnap.fileTypeRaw) ?? .supplementary,
                        addedDate: attSnap.addedDate,
                        id: attSnap.id
                    )
                    att.manuscript = m
                    if let sId = attSnap.statusLogId {
                        att.statusLog = logMap[sId]
                    }
                    if m.attachments == nil { m.attachments = [] }
                    m.attachments?.append(att)
                    attMap[att.id] = att
                }

                restoredOrUpdated += 1
            } else {
                // 全新稿件
                let m = Manuscript(
                    title: snap.title,
                    venue: snap.venue,
                    venueType: VenueType(rawValue: snap.venueTypeRaw) ?? .other,
                    manuscriptNumber: snap.manuscriptNumber ?? "",
                    submissionSystemURL: snap.submissionSystemURL ?? "",
                    authorGuideURL: snap.authorGuideURL ?? "",
                    submissionDate: snap.submissionDate,
                    currentStatus: ManuscriptStatus(rawValue: snap.currentStatusRaw) ?? .draft,
                    fileBookmark: Data(),
                    filePath: snap.filePath,
                    notes: snap.notes,
                    collaborators: snap.collaborators,
                    tags: snap.tags,
                    deadlineDate: snap.deadlineDate
                )
                m.id = snap.id
                m.createdAt = snap.createdAt
                m.updatedAt = snap.updatedAt

                var logMap: [UUID: StatusLogEntry] = [:]
                m.statusLogs = snap.statusLogs.map { logSnap in
                    let e = StatusLogEntry(
                        date: logSnap.date,
                        status: ManuscriptStatus(rawValue: logSnap.statusRaw) ?? .draft,
                        stage: logSnap.stageRaw ?? "",
                        note: logSnap.note,
                        id: logSnap.id
                    )
                    e.manuscript = m
                    logMap[e.id] = e
                    return e
                }

                m.attachments = (snap.attachments ?? []).map { attSnap in
                    let a = Attachment(
                        relativePath: attSnap.relativePath,
                        originalFileName: attSnap.originalFileName,
                        displayName: attSnap.displayName,
                        fileSize: attSnap.fileSize,
                        sha256Hash: attSnap.sha256Hash,
                        mimeType: attSnap.mimeType,
                        syncState: .synced,
                        fileType: AttachmentFileType(rawValue: attSnap.fileTypeRaw) ?? .supplementary,
                        addedDate: attSnap.addedDate,
                        id: attSnap.id
                    )
                    a.manuscript = m
                    if let sId = attSnap.statusLogId {
                        a.statusLog = logMap[sId]
                    }
                    return a
                }

                context.insert(m)
                existingMap[m.id] = m
                restoredOrUpdated += 1
            }
        }
        try context.save()
        return restoredOrUpdated
    }
}
