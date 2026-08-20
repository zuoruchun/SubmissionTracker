import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

/// 新增/编辑稿件表单（标题、期刊、日期、状态、文件、合作者、标签、备注）。
struct ManuscriptFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// 编辑模式传入既有稿件；nil = 新建
    var manuscript: Manuscript?

    @State private var title = ""
    @State private var venue = ""
    @State private var venueType: VenueType = .journal
    @State private var submissionDate = Date.now
    @State private var status: ManuscriptStatus = .draft
    @State private var hasDeadline = false
    @State private var deadlineDate = Date().addingTimeInterval(30 * 86400)
    @State private var collaboratorsText = ""
    @State private var tagsText = ""
    @State private var notes = ""
    @State private var pickedFile: (bookmark: Data, path: String)?

    /// 编辑模式下进入时的原状态（用于判断是否需要补一条状态记录）
    @State private var originalStatus: ManuscriptStatus?

    private var isEditing: Bool { manuscript != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isEditing ? "编辑稿件" : "新增稿件")
                    .font(AppTheme.serifTitle(22))

                field("标题") {
                    TextField("稿件标题", text: $title)
                        .font(AppTheme.serifBody(14))
                }
                field("期刊 / 会议") {
                    HStack {
                        TextField("目标期刊或会议名称", text: $venue)
                            .font(AppTheme.serifBody(14))
                        Picker("", selection: $venueType) {
                            ForEach(VenueType.allCases) { t in
                                Text(t.displayNameZh).tag(t)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                HStack(alignment: .top, spacing: 16) {
                    field("投稿日期") {
                        DatePicker("", selection: $submissionDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                    field("当前状态") {
                        Picker("", selection: $status) {
                            ForEach(ManuscriptStatus.allCases) { s in
                                Text(s.displayNameZh).tag(s)
                            }
                        }
                        .labelsHidden()
                    }
                    field("下一步截止（可选）") {
                        HStack(spacing: 8) {
                            Toggle("", isOn: $hasDeadline).labelsHidden()
                            DatePicker("", selection: $deadlineDate, displayedComponents: .date)
                                .labelsHidden()
                                .disabled(!hasDeadline)
                        }
                    }
                }
                field("合作者（用逗号分隔）") {
                    TextField("例如：Alice, Bob", text: $collaboratorsText)
                        .font(AppTheme.monoLabel(12))
                }
                field("标签（用逗号分隔）") {
                    TextField("例如：SDE, 数值分析", text: $tagsText)
                        .font(AppTheme.monoLabel(12))
                }
                fileRow
                field("备注（Markdown）") {
                    TextEditor(text: $notes)
                        .font(AppTheme.serifBody(13))
                        .frame(minHeight: 110)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
                }

                HStack {
                    if !title.trimmingCharacters(in: .whitespaces).isEmpty == false {
                        Text("标题不能为空")
                            .font(AppTheme.monoLabel(11))
                            .foregroundStyle(AppTheme.brick)
                    }
                    Spacer()
                    Button("取消") { dismiss() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    Button(isEditing ? "保存" : "新增") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
        }
        .onAppear { loadIfNeeded() }
    }

    // MARK: - 字段容器

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppTheme.monoLabel(12))
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - 文件

    private var fileRow: some View {
        field("关联文件") {
            HStack {
                if let f = pickedFile {
                    Text(URL(fileURLWithPath: f.path).lastPathComponent)
                        .font(AppTheme.monoLabel(12))
                        .lineLimit(1)
                } else if let m = manuscript, !m.filePath.isEmpty {
                    Text(URL(fileURLWithPath: m.filePath).lastPathComponent)
                        .font(AppTheme.monoLabel(12))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                } else {
                    Text("未选择")
                        .font(AppTheme.monoLabel(12))
                        .foregroundStyle(.tertiary)
                }
                Button("选择文件…") { pickFile() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func pickFile() {
        Task {
            guard let picked = await FileService.chooseFile() else { return }
            if let first = picked.first { pickedFile = first }
        }
    }

    // MARK: - 载入 / 保存

    private func loadIfNeeded() {
        guard let m = manuscript else { return }
        title = m.title
        venue = m.venue
        venueType = m.venueType
        submissionDate = m.submissionDate
        status = m.currentStatus
        originalStatus = m.currentStatus
        if let d = m.deadlineDate {
            hasDeadline = true
            deadlineDate = d
        } else {
            hasDeadline = false
        }
        collaboratorsText = m.collaborators.items.joined(separator: ", ")
        tagsText = m.tags.items.joined(separator: ", ")
        notes = m.notes
        if !m.fileBookmark.isEmpty {
            pickedFile = (m.fileBookmark, m.filePath)
        }
    }

    private func save() {
        let collaborators = splitList(collaboratorsText)
        let tags = splitList(tagsText)
        let deadline = hasDeadline ? deadlineDate : nil

        if let m = manuscript {
            // 编辑
            m.title = title
            m.venue = venue
            m.venueType = venueType
            m.submissionDate = submissionDate
            m.collaborators = StringList(collaborators)
            m.tags = StringList(tags)
            m.deadlineDate = deadline
            m.notes = notes
            if let f = pickedFile {
                m.fileBookmark = f.bookmark
                m.filePath = f.path
            }
            if let original = originalStatus, original != status {
                m.appendStatusLog(status, note: "状态更新", context: context)
            }
            if let deadline {
                Task { await NotificationService.scheduleDeadlineReminder(
                    id: m.id, title: m.title, venue: m.venue, deadline: deadline) }
            } else {
                NotificationService.cancelReminder(id: m.id)
            }
            m.touch()
            try? context.save()
        } else {
            // 新建
            let m = Manuscript(
                title: title,
                venue: venue,
                venueType: venueType,
                submissionDate: submissionDate,
                currentStatus: status,
                fileBookmark: pickedFile?.bookmark ?? Data(),
                filePath: pickedFile?.path ?? "",
                notes: notes,
                collaborators: collaborators,
                tags: tags,
                deadlineDate: deadline
            )
            context.insert(m)
            // 初始状态记录
            let log = StatusLogEntry(date: .now, status: status, note: "创建记录")
            if m.statusLogs == nil { m.statusLogs = [] }
            m.statusLogs?.append(log)
            log.manuscript = m
            if let deadline {
                Task { await NotificationService.scheduleDeadlineReminder(
                    id: m.id, title: m.title, venue: m.venue, deadline: deadline) }
            }
            try? context.save()
        }
        dismiss()
    }

    // MARK: - 工具

    private func splitList(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

}
