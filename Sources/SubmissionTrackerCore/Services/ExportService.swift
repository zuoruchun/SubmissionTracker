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

    // MARK: - JSON 备份

    /// 备份用的可序列化快照（不含文件 bookmark 之外的私有句柄）。
    struct Backup: Codable {
        var version: Int = 1
        var exportedAt: Date
        var manuscripts: [ManuscriptSnapshot]

        struct ManuscriptSnapshot: Codable {
            var id: UUID
            var title: String
            var venue: String
            var venueTypeRaw: String
            var submissionDate: Date
            var currentStatusRaw: String
            var filePath: String
            var notes: String
            var collaborators: [String]
            var tags: [String]
            var deadlineDate: Date?
            var createdAt: Date
            var updatedAt: Date
            var statusLogs: [LogSnapshot]

            struct LogSnapshot: Codable {
                var id: UUID
                var date: Date
                var statusRaw: String
                var note: String
            }
        }
    }

    static func backup(for manuscripts: [Manuscript]) -> Data? {
        let snapshot = Backup(
            exportedAt: .now,
            manuscripts: manuscripts.map { m in
                Backup.ManuscriptSnapshot(
                    id: m.id,
                    title: m.title,
                    venue: m.venue,
                    venueTypeRaw: m.venueTypeRaw,
                    submissionDate: m.submissionDate,
                    currentStatusRaw: m.currentStatusRaw,
                    filePath: m.filePath,
                    notes: m.notes,
                    collaborators: m.collaborators.items,
                    tags: m.tags.items,
                    deadlineDate: m.deadlineDate,
                    createdAt: m.createdAt,
                    updatedAt: m.updatedAt,
                    statusLogs: m.sortedStatusLogs.map {
                        Backup.ManuscriptSnapshot.LogSnapshot(
                            id: $0.id,
                            date: $0.date,
                            statusRaw: $0.statusRaw,
                            note: $0.note
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

    /// 从备份 JSON 恢复（追加写入；id 相同的稿件跳过，避免重复）。
    @discardableResult
    public static func restore(from data: Data, into context: ModelContext) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Backup.self, from: data)

        // 已存在的稿件 id
        var existingIDs = Set<UUID>()
        let existing = try context.fetch(FetchDescriptor<Manuscript>())
        existingIDs = Set(existing.map { $0.id })

        var restored = 0
        for snap in backup.manuscripts where !existingIDs.contains(snap.id) {
            let m = Manuscript(
                title: snap.title,
                venue: snap.venue,
                venueType: VenueType(rawValue: snap.venueTypeRaw) ?? .other,
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
            m.statusLogs = snap.statusLogs.map { logSnap in
                let e = StatusLogEntry(date: logSnap.date, status: ManuscriptStatus(rawValue: logSnap.statusRaw) ?? .draft, note: logSnap.note)
                e.id = logSnap.id
                e.manuscript = m
                return e
            }
            context.insert(m)
            restored += 1
        }
        try context.save()
        return restored
    }
}
