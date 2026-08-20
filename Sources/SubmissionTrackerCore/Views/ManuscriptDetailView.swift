import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import QuickLook
#if os(macOS)
import AppKit
#endif

/// 右侧详情面板：元信息、文件关联与 QuickLook 预览、附件、
/// 状态时间线、备注、截止日期。
struct ManuscriptDetailView: View {
    @Bindable var manuscript: Manuscript
    @Environment(\.modelContext) private var context
    @State private var showingEditForm = false
    @State private var showingAddStatus = false
    @State private var pendingAttachment: (bookmark: Data, path: String)?
    @State private var showingAttachmentTypePicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                filesAndAttachmentsSection
                timelineSection
                notesSection
            }
            .padding(24)
        }
        .textSelection(.enabled)
        .themedBackground()
        .navigationTitle(manuscript.title)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showingAddStatus = true
                } label: {
                    Label("记录状态", systemImage: "plus.circle")
                }
                .help("追加一条状态变更记录")

                Button {
                    showingEditForm = true
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                .help("编辑稿件信息")

                Menu {
                    Button("导出 CSV…") { exportCSV() }
                    Button("导出 Markdown 报告…") { exportMarkdown() }
                    Button("备份为 JSON…") { exportJSON() }
                    Divider()
                    Button("删除稿件", role: .destructive) { deleteManuscript() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("更多操作")
            }
        }
        .sheet(isPresented: $showingEditForm) {
            ManuscriptFormView(manuscript: manuscript)
        }
        .sheet(isPresented: $showingAddStatus) {
            AddStatusView(manuscript: manuscript)
        }
        .sheet(isPresented: $showingAttachmentTypePicker) {
            AttachmentTypePrompt { type in
                commitAttachment(type)
                showingAttachmentTypePicker = false
            }
        }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(manuscript.title)
                .font(AppTheme.serifTitle(26))
            HStack(spacing: 10) {
                Label(manuscript.venue, systemImage: AppTheme.venueIcon(manuscript.venueType))
                    .font(AppTheme.serifBody(13))
                    .foregroundStyle(.secondary)
                AppTheme.statusBadge(manuscript.currentStatus)
                Text(manuscript.submissionDate, format: .dateTime.year().month().day())
                    .font(AppTheme.monoLabel(12))
                    .foregroundStyle(.tertiary)
            }
            if !manuscript.collaborators.items.isEmpty {
                Text("合作者：\(manuscript.collaborators.items.joined(separator: ", "))")
                    .font(AppTheme.serifBody(12))
                    .foregroundStyle(.secondary)
            }
            if !manuscript.tags.items.isEmpty {
                HStack(spacing: 6) {
                    ForEach(manuscript.tags.items, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(AppTheme.monoLabel(11))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }
                }
            }
            if let deadline = manuscript.deadlineDate {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0
                let remainText = days >= 0 ? "剩 \(days) 天" : "已逾期 \(abs(days)) 天"
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.exclamationmark")
                    Text("下一步截止：\(deadline.formatted(date: .abbreviated, time: .omitted))（\(remainText)）")
                }
                .font(AppTheme.monoLabel(12))
                .foregroundStyle(days < 7 ? AppTheme.brick : AppTheme.ochre)
            }
        }
    }

    // MARK: - 论文文件与附件（统一管理）

    private var filesAndAttachmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("论文文件与附件")
                Spacer()
                Button {
                    addAttachment()
                } label: {
                    Label("添加附件 / 补充材料", systemImage: "plus.circle")
                }
                .font(AppTheme.monoLabel(11))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            let attachments = manuscript.sortedAttachments
            let hasMainFile = !manuscript.filePath.isEmpty
            let hasAttachments = !attachments.isEmpty

            if !hasMainFile && !hasAttachments {
                VStack(alignment: .leading, spacing: 8) {
                    Text("暂未关联任何文件（支持关联论文 TeX/PDF 主手稿、审稿意见、回复信或补充材料）")
                        .font(AppTheme.serifBody(12))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button {
                            chooseMainFile()
                        } label: {
                            Label("关联主手稿 / PDF…", systemImage: "doc.badge.plus")
                        }
                        .font(AppTheme.monoLabel(11))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button {
                            addAttachment()
                        } label: {
                            Label("添加附件…", systemImage: "paperclip")
                        }
                        .font(AppTheme.monoLabel(11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.top, 2)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 8) {
                    // 主手稿文件条目
                    if hasMainFile {
                        HStack(spacing: 8) {
                            Text("主手稿")
                                .font(AppTheme.monoLabel(11))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(AppTheme.navy.opacity(0.12))
                                .foregroundStyle(AppTheme.navy)
                                .clipShape(Capsule())

                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(AppTheme.navy)

                            Text(displayFileName)
                                .font(AppTheme.monoLabel(12))
                                .lineLimit(1)

                            Spacer()

                            if hasResolvableFile {
                                Button("在 Finder 中显示") {
                                    FileService.reveal(bookmark: manuscript.fileBookmark,
                                                       fallbackPath: manuscript.filePath)
                                }
                                .font(AppTheme.monoLabel(10))
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }

                            Button {
                                chooseMainFile()
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("更换主手稿文件")

                            Button {
                                removeMainFile()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("移除关联")
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        HStack {
                            Text("未关联主手稿 / PDF")
                                .font(AppTheme.monoLabel(11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("关联主手稿…") {
                                chooseMainFile()
                            }
                            .font(AppTheme.monoLabel(10))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                    }

                    // 附件列表
                    ForEach(attachments) { att in
                        HStack(spacing: 8) {
                            Text(att.fileType.displayNameZh)
                                .font(AppTheme.monoLabel(11))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color.primary.opacity(0.08))
                                .clipShape(Capsule())

                            Image(systemName: "paperclip")
                                .foregroundStyle(.secondary)

                            Text(URL(fileURLWithPath: att.filePath).lastPathComponent)
                                .font(AppTheme.monoLabel(12))
                                .lineLimit(1)

                            Spacer()

                            Text(att.addedDate, format: .dateTime.year().month().day())
                                .font(AppTheme.monoLabel(10))
                                .foregroundStyle(.tertiary)

                            Button("在 Finder 中显示") {
                                FileService.reveal(bookmark: att.fileBookmark,
                                                   fallbackPath: att.filePath)
                            }
                            .font(AppTheme.monoLabel(10))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)

                            Button {
                                removeAttachment(att)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.primary.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                // QuickLook 预览（若主稿件存在）
                if let url = resolvedFileURL {
                    filePreview(for: url)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var displayFileName: String {
        URL(fileURLWithPath: manuscript.filePath).lastPathComponent
    }

    private var hasResolvableFile: Bool {
        resolvedFileURL != nil || (!manuscript.filePath.isEmpty && FileManager.default.fileExists(atPath: manuscript.filePath))
    }

    private var resolvedFileURL: URL? {
        FileService.previewURL(bookmark: manuscript.fileBookmark, fallbackPath: manuscript.filePath)
    }

    @ViewBuilder
    private func filePreview(for url: URL) -> some View {
        QuickLookPreviewPane(url: url)
    }

    // MARK: - 状态时间线

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("状态时间线")
            let logs = manuscript.sortedStatusLogs
            if logs.isEmpty {
                Text("尚无状态记录")
                    .font(AppTheme.serifBody(12))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(logs.enumerated()), id: \.element.id) { index, log in
                        HStack(alignment: .top, spacing: 12) {
                            // 竖线 + 圆点
                            VStack(spacing: 0) {
                                if index > 0 {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.15))
                                        .frame(width: 1.5)
                                        .frame(height: 10)
                                }
                                Circle()
                                    .fill(AppTheme.statusColor(log.status))
                                    .frame(width: 9, height: 9)
                                if index < logs.count - 1 {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.15))
                                        .frame(width: 1.5)
                                        .frame(maxHeight: .infinity)
                                }
                            }
                            .frame(width: 10)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    AppTheme.statusBadge(log.status)
                                    Text(log.date, format: .dateTime.year().month().day())
                                        .font(AppTheme.monoLabel(11))
                                        .foregroundStyle(.tertiary)
                                }
                                if !log.note.isEmpty {
                                    Text(log.note)
                                        .font(AppTheme.serifBody(13))
                                }
                            }
                            .padding(.bottom, 16)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    // MARK: - 备注

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("备注")
            Text(manuscript.notes.isEmpty ? "（空）" : manuscript.notes)
                .font(AppTheme.serifBody(14))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .font(AppTheme.serifTitle(17))
    }

    // MARK: - 操作

    private func chooseMainFile() {
        Task {
            guard let picked = await FileService.chooseFile(allowsMultipleSelection: false) else { return }
            guard let first = picked.first else { return }
            manuscript.fileBookmark = first.bookmark
            manuscript.filePath = first.path
            manuscript.touch()
            try? context.save()
        }
    }

    private func removeMainFile() {
        manuscript.fileBookmark = Data()
        manuscript.filePath = ""
        manuscript.touch()
        try? context.save()
    }

    private func addAttachment() {
        Task {
            guard let picked = await FileService.chooseFile(allowsMultipleSelection: false) else { return }
            guard let first = picked.first else { return }
            pendingAttachment = first
            showingAttachmentTypePicker = true
        }
    }

    private func commitAttachment(_ type: AttachmentFileType) {
        guard let item = pendingAttachment else { return }
        let att = Attachment(
            fileBookmark: item.bookmark,
            filePath: item.path,
            fileType: type
        )
        if manuscript.attachments == nil { manuscript.attachments = [] }
        manuscript.attachments?.append(att)
        att.manuscript = manuscript
        manuscript.touch()
        try? context.save()
        pendingAttachment = nil
    }

    private func removeAttachment(_ att: Attachment) {
        manuscript.attachments?.removeAll { $0.id == att.id }
        att.manuscript = nil
        context.delete(att)
        manuscript.touch()
        try? context.save()
    }

    private func deleteManuscript() {
        context.delete(manuscript)
        try? context.save()
    }

    // 导出
    private func exportCSV() {
        let text = ExportService.csv(for: [manuscript])
        presentExport(text: text, suggestedName: "投稿记录.csv")
    }
    private func exportMarkdown() {
        let text = ExportService.markdownReport(for: [manuscript])
        presentExport(text: text, suggestedName: "投稿报告.md")
    }
    private func exportJSON() {
        guard let data = ExportService.backup(for: [manuscript]) else { return }
        presentExportData(data: data, suggestedName: "数据备份.json")
    }

    #if os(macOS)
    private func presentExport(text: String, suggestedName: String) {
        presentExportData(data: Data(text.utf8), suggestedName: suggestedName)
    }
    private func presentExportData(data: Data, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        if let ext = suggestedName.split(separator: ".").last.map(String.init) {
            if let type = UTType(filenameExtension: ext) {
                panel.allowedContentTypes = [type]
            }
        }
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }
    #endif
}

// MARK: - 附件类型选择小面板

/// 附件类型确认（用简单 Alert 风格 sheet 即可，MVP 默认"补充材料"）
struct AttachmentTypePrompt: View {
    let onPick: (AttachmentFileType) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("选择附件类型")
                .font(AppTheme.serifTitle(18))
            ForEach(AttachmentFileType.allCases) { type in
                Button(type.displayNameZh) {
                    onPick(type)
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .presentationDetents([.medium])
    }
}

// MARK: - QuickLook 包装

/// 内嵌 QuickLook 预览：由 `.quickLookPreview` 驱动（macOS 11+ / iOS 14+）。
/// 当前 macOS SDK 无 QLPreviewView / QuickLookPreviewItem。
private struct QuickLookPreviewPane: View {
    let url: URL
    @State private var selectedURL: URL?

    var body: some View {
        Color.clear
            .quickLookPreview($selectedURL)
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onAppear { selectedURL = url }
            .onChange(of: url) { selectedURL = url }
    }
}
