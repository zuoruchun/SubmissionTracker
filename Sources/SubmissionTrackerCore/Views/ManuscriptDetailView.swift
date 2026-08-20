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
    var onBackToTimeline: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @State private var showingEditForm = false
    @State private var showingAddStatus = false

    // 附件选择与目标节点绑定
    @State private var targetStatusLog: StatusLogEntry? = nil
    @State private var pendingFile: (bookmark: Data, path: String, url: URL)?
    @State private var showingAttachmentTypePicker = false

    // PDF / 附件预览
    @State private var previewPayload: FilePreviewPayload?
    @State private var fileAlertMessage: String?
    @State private var showingFileAlert = false

    // 覆盖确认
    @State private var overwriteAlertCandidate: (file: (bookmark: Data, path: String, url: URL), type: AttachmentFileType, log: StatusLogEntry?, existingAtt: Attachment)?
    @State private var showingOverwriteAlert = false

    // 删除确认
    @State private var attachmentToDelete: Attachment?
    @State private var showingDeleteAttachmentAlert = false

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
            if let onBack = onBackToTimeline {
                ToolbarItem(placement: .navigation) {
                    Button {
                        onBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .help("返回全局动态")
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
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
                if let file = pendingFile {
                    processAttachmentImport(file: file, type: type, log: targetStatusLog)
                }
                showingAttachmentTypePicker = false
            }
        }
        .sheet(item: $previewPayload) { payload in
            PDFViewerSheet(payload: payload)
        }
        .alert("提示", isPresented: $showingFileAlert) {
            Button("好", role: .cancel) { fileAlertMessage = nil }
        } message: {
            Text(fileAlertMessage ?? "")
        }
        .alert("确认覆盖已有附件？", isPresented: $showingOverwriteAlert) {
            Button("取消", role: .cancel) { overwriteAlertCandidate = nil }
            Button("确认覆盖", role: .destructive) {
                if let cand = overwriteAlertCandidate {
                    commitAttachmentImport(file: cand.file, type: cand.type, log: cand.log, existingToReplace: cand.existingAtt)
                }
                overwriteAlertCandidate = nil
            }
        } message: {
            if let cand = overwriteAlertCandidate {
                Text("该节点已存在【\(cand.type.displayNameZh)】：\(cand.existingAtt.originalFileName)。\n确认后旧版本将安全备份至 App 回收站，并更新为新文件：\(cand.file.url.lastPathComponent)。")
            }
        }
        .alert("确认移除该附件？", isPresented: $showingDeleteAttachmentAlert) {
            Button("取消", role: .cancel) { attachmentToDelete = nil }
            Button("确认移除", role: .destructive) {
                if let att = attachmentToDelete {
                    removeAttachment(att)
                }
                attachmentToDelete = nil
            }
        } message: {
            Text("将从 App 托管目录中移除该附件（移入安全回收站），外部原文件不会被删除。")
        }
    }

    // MARK: - 头部

    private var daysSinceLastStatus: Int {
        guard let latest = manuscript.sortedStatusLogs.first else {
            return Calendar.current.dateComponents([.day], from: manuscript.submissionDate, to: Date()).day ?? 0
        }
        return Calendar.current.dateComponents([.day], from: latest.date, to: Date()).day ?? 0
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(manuscript.title)
                .font(AppTheme.serifTitle(26))

            HStack(spacing: 10) {
                Label(manuscript.venue, systemImage: AppTheme.venueIcon(manuscript.venueType))
                    .font(AppTheme.serifBody(13))
                    .foregroundStyle(.secondary)

                AppTheme.statusBadge(manuscript.currentStatus)

                if !manuscript.manuscriptNumber.isEmpty {
                    Text("#\(manuscript.manuscriptNumber)")
                        .font(AppTheme.monoLabel(11))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Text("距上次状态变化 \(daysSinceLastStatus) 天")
                    .font(AppTheme.monoLabel(11))
                    .foregroundStyle(.secondary)

                Text(manuscript.submissionDate, format: .dateTime.year().month().day())
                    .font(AppTheme.monoLabel(11))
                    .foregroundStyle(.tertiary)
            }

            // 快捷外链（投稿系统、作者指南）
            if !manuscript.submissionSystemURL.isEmpty || !manuscript.authorGuideURL.isEmpty {
                HStack(spacing: 12) {
                    if let url = URL(string: manuscript.submissionSystemURL), !manuscript.submissionSystemURL.isEmpty {
                        Link(destination: url) {
                            Label("打开投稿系统 ↗", systemImage: "arrow.up.right.square")
                                .font(AppTheme.monoLabel(11))
                        }
                    }
                    if let url = URL(string: manuscript.authorGuideURL), !manuscript.authorGuideURL.isEmpty {
                        Link(destination: url) {
                            Label("作者指南 ↗", systemImage: "book")
                                .font(AppTheme.monoLabel(11))
                        }
                    }
                }
                .padding(.top, 2)
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
                    startAddAttachment(targetLog: nil)
                } label: {
                    Label("添加附件 / 补充材料", systemImage: "plus.circle")
                }
                .font(AppTheme.monoLabel(11))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            let attachments = manuscript.sortedAttachments

            if attachments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("暂未关联任何本地托管附件（支持导入 TeX/PDF 主手稿、审稿意见、回复信或补充材料）")
                        .font(AppTheme.serifBody(12))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button {
                            startAddAttachment(targetLog: nil)
                        } label: {
                            Label("导入并绑定附件…", systemImage: "doc.badge.plus")
                        }
                        .font(AppTheme.monoLabel(11))
                        .buttonStyle(.borderedProminent)
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
                    ForEach(attachments) { att in
                        HStack(spacing: 8) {
                            Text(att.fileType.displayNameZh)
                                .font(AppTheme.monoLabel(11))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(AppTheme.navy.opacity(0.1))
                                .foregroundStyle(AppTheme.navy)
                                .clipShape(Capsule())

                            if let stage = att.statusLog?.stage, !stage.isEmpty {
                                Text(stage)
                                    .font(AppTheme.monoLabel(10))
                                    .foregroundStyle(.secondary)
                            }

                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(AppTheme.navy)

                            let name = att.displayName.isEmpty ? (att.originalFileName.isEmpty ? att.fileType.displayNameZh : att.originalFileName) : att.displayName
                            Text(name)
                                .font(AppTheme.monoLabel(12))
                                .lineLimit(1)

                            Spacer()

                            Text(att.addedDate, format: .dateTime.year().month().day())
                                .font(AppTheme.monoLabel(10))
                                .foregroundStyle(.tertiary)

                            // PDFKit 快速查看
                            Button("查看") {
                                openPDFViewer(for: att)
                            }
                            .font(AppTheme.monoLabel(10))
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)

                            Button("Finder") {
                                if let url = FileService.resolveURL(for: att), FileManager.default.fileExists(atPath: url.path) {
                                    FileService.reveal(url: url)
                                } else {
                                    fileAlertMessage = "本地暂未找到文件路径。"
                                    showingFileAlert = true
                                }
                            }
                            .font(AppTheme.monoLabel(10))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)

                            Button {
                                attachmentToDelete = att
                                showingDeleteAttachmentAlert = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("移除附件")
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    // MARK: - 状态时间线

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("状态时间线")
                Spacer()
                Button {
                    showingAddStatus = true
                } label: {
                    Label("追加状态记录", systemImage: "plus.circle")
                }
                .font(AppTheme.monoLabel(11))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

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

                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 8) {
                                    AppTheme.statusBadge(log.status)

                                    if !log.stage.isEmpty {
                                        Text(log.stage)
                                            .font(AppTheme.monoLabel(11))
                                            .padding(.horizontal, 6).padding(.vertical, 1)
                                            .background(Color.primary.opacity(0.08))
                                            .clipShape(Capsule())
                                    }

                                    Text(log.date, format: .dateTime.year().month().day())
                                        .font(AppTheme.monoLabel(11))
                                        .foregroundStyle(.tertiary)

                                    Spacer()

                                    // 给具体节点添加附件的入口
                                    Button {
                                        startAddAttachment(targetLog: log)
                                    } label: {
                                        Label("绑定附件", systemImage: "paperclip.badge.ellipsis")
                                    }
                                    .font(AppTheme.monoLabel(10))
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }

                                if !log.note.isEmpty {
                                    Text(log.note)
                                        .font(AppTheme.serifBody(13))
                                }

                                // 节点绑定的附件 Chips (带 PDFKit 预览)
                                let logAtts = log.sortedAttachments
                                if !logAtts.isEmpty {
                                    HStack(spacing: 6) {
                                        ForEach(logAtts) { att in
                                            Button {
                                                openPDFViewer(for: att)
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "doc.text.fill")
                                                        .font(.system(size: 10))
                                                    let name = att.displayName.isEmpty ? (att.originalFileName.isEmpty ? att.fileType.displayNameZh : att.originalFileName) : att.displayName
                                                    Text(name)
                                                        .font(AppTheme.monoLabel(10))
                                                }
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3)
                                                .background(AppTheme.navy.opacity(0.1))
                                                .foregroundStyle(AppTheme.navy)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                            }
                                            .buttonStyle(.plain)
                                            .help("点击在 App 内查看 PDF: \(att.originalFileName)")
                                        }
                                    }
                                    .padding(.top, 2)
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

    // MARK: - 操作与附件处理 (目标 A & C)

    private func startAddAttachment(targetLog: StatusLogEntry?) {
        self.targetStatusLog = targetLog
        Task {
            guard let picked = await FileService.chooseFile(allowsMultipleSelection: false) else { return }
            guard let first = picked.first else { return }
            self.pendingFile = first
            self.showingAttachmentTypePicker = true
        }
    }

    private func processAttachmentImport(
        file: (bookmark: Data, path: String, url: URL),
        type: AttachmentFileType,
        log: StatusLogEntry?
    ) {
        // 槽位冲突检测: (manuscript, log, type)
        let existingAtt = (manuscript.attachments ?? []).first { att in
            att.statusLog?.id == log?.id && att.fileType == type
        }

        if let existing = existingAtt {
            // 已存在同槽位文件，弹出确认覆盖
            overwriteAlertCandidate = (file: file, type: type, log: log, existingAtt: existing)
            showingOverwriteAlert = true
        } else {
            commitAttachmentImport(file: file, type: type, log: log, existingToReplace: nil)
        }
    }

    private func commitAttachmentImport(
        file: (bookmark: Data, path: String, url: URL),
        type: AttachmentFileType,
        log: StatusLogEntry?,
        existingToReplace: Attachment?
    ) {
        let stagePrefix = log?.stage.isEmpty == false ? "[\(log!.stage)] " : ""
        let dispName = "\(stagePrefix)\(file.url.lastPathComponent)"

        do {
            let info = try FileService.importManagedCopy(
                from: file.url,
                manuscriptID: manuscript.id,
                statusLogID: log?.id,
                fileType: type,
                customDisplayName: dispName
            )

            if let existing = existingToReplace {
                // 覆盖现有记录
                existing.relativePath = info.relativePath
                existing.originalFileName = info.originalFileName
                existing.displayName = info.displayName
                existing.fileSize = info.fileSize
                existing.sha256Hash = info.sha256Hash
                existing.mimeType = info.mimeType
                existing.syncState = .local
                existing.touch()
            } else {
                // 新建记录
                let att = Attachment(
                    relativePath: info.relativePath,
                    originalFileName: info.originalFileName,
                    displayName: info.displayName,
                    fileSize: info.fileSize,
                    sha256Hash: info.sha256Hash,
                    mimeType: info.mimeType,
                    syncState: .local,
                    fileType: type,
                    addedDate: log?.date ?? .now
                )
                att.manuscript = manuscript
                att.statusLog = log
                if manuscript.attachments == nil { manuscript.attachments = [] }
                manuscript.attachments?.append(att)
                if let l = log {
                    if l.attachments == nil { l.attachments = [] }
                    l.attachments?.append(att)
                }
            }

            manuscript.touch()
            try? context.save()
            WebDAVSyncService.shared.autoSyncIfNeeded(context: context)
        } catch {
            print("Import attachment failed: \(error)")
        }

        pendingFile = nil
        targetStatusLog = nil
    }

    private func removeAttachment(_ att: Attachment) {
        FileService.deleteManagedCopy(for: att.relativePath)
        manuscript.attachments?.removeAll { $0.id == att.id }
        if let l = att.statusLog {
            l.attachments?.removeAll { $0.id == att.id }
        }
        att.manuscript = nil
        att.statusLog = nil
        context.delete(att)
        manuscript.touch()
        try? context.save()
        WebDAVSyncService.shared.autoSyncIfNeeded(context: context)
    }

    private func openPDFViewer(for att: Attachment) {
        if let url = FileService.resolveURL(for: att), FileManager.default.fileExists(atPath: url.path) {
            let dispName = att.displayName.isEmpty ? (att.originalFileName.isEmpty ? att.fileType.displayNameZh : att.originalFileName) : att.displayName
            previewPayload = FilePreviewPayload(
                url: url,
                title: manuscript.title,
                subtitle: "\(att.fileType.displayNameZh) · \(dispName)"
            )
        } else {
            fileAlertMessage = "未在本地找到附件实体文件。如果该文件曾关联在外部磁盘，请在节点右侧点击“绑定附件”重新导入。"
            showingFileAlert = true
        }
    }

    private func deleteManuscript() {
        // 清理托管的所有文件
        for att in (manuscript.attachments ?? []) {
            FileService.deleteManagedCopy(for: att.relativePath)
        }
        context.delete(manuscript)
        try? context.save()
        WebDAVSyncService.shared.autoSyncIfNeeded(context: context)
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
