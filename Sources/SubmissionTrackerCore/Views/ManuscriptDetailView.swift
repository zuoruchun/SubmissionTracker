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

    // 唯一论文 PDF 上传入口：先选择合规的时间线节点，再选择 PDF。
    @State private var showingPDFTargetPicker = false

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
                if manuscript.currentStatus == .accept || manuscript.currentStatus == .published {
                    celebrationBanner
                }
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
        .sheet(isPresented: $showingPDFTargetPicker) {
            PDFTimelineTargetPicker(logs: eligiblePDFLogs) { log in
                showingPDFTargetPicker = false
                startPDFImport(for: log)
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

    // MARK: - 录用祝贺横幅 (专属确定性随机文案)

    private var celebrationBanner: some View {
        let msg = CelebrationMessages.message(for: manuscript)
        return HStack(alignment: .center, spacing: 14) {
            Text(msg.emoji)
                .font(.system(size: 32))

            VStack(alignment: .leading, spacing: 4) {
                Text(msg.title)
                    .font(AppTheme.serifTitle(16))
                    .foregroundStyle(AppTheme.moss)

                Text(msg.body)
                    .font(AppTheme.serifBody(13))
                    .foregroundStyle(.primary.opacity(0.88))
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppTheme.moss.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.moss.opacity(0.25), lineWidth: 1)
        )
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

            // 快捷外链（投稿系统、已发表论文在线地址）
            if !manuscript.submissionSystemURL.isEmpty || !manuscript.authorGuideURL.isEmpty {
                HStack(spacing: 12) {
                    if let url = URL(string: manuscript.submissionSystemURL), !manuscript.submissionSystemURL.isEmpty {
                        Link(destination: url) {
                            Label("打开投稿系统 ↗", systemImage: "arrow.up.right.square")
                                .font(AppTheme.monoLabel(11))
                        }
                    }
                    if let url = URL(string: manuscript.authorGuideURL), !manuscript.authorGuideURL.isEmpty {
                        let labelText = (manuscript.currentStatus == .accept || manuscript.currentStatus == .published) ? "已发表论文在线地址 ↗" : "期刊/在线链接 ↗"
                        Link(destination: url) {
                            Label(labelText, systemImage: "link")
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

    // MARK: - 状态时间线 (融合展示论文版本与附件)

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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

                Button {
                    showingPDFTargetPicker = true
                } label: {
                    Label("上传论文 PDF", systemImage: "doc.badge.plus")
                }
                .font(AppTheme.monoLabel(11))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(eligiblePDFLogs.isEmpty)
                .help(eligiblePDFLogs.isEmpty ? "请先记录首次投稿、修回稿已提交、已接收或已出版状态" : "选择时间线节点并上传论文 PDF")
            }

            let logs = manuscript.sortedStatusLogs
            if logs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("尚无状态记录（请先记录首次投稿、审稿决定或修回状态）")
                        .font(AppTheme.serifBody(12))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 8))
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

                            VStack(alignment: .leading, spacing: 6) {
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

                                    // 节点绑定的论文文件 / 附件 Chips（直接在状态徽章与日期后展示，点击直接在 App 内看 PDF）
                                    let logAtts = log.sortedAttachments
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
                                                Image(systemName: "eye")
                                                    .font(.system(size: 9))
                                                    .opacity(0.7)
                                            }
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2.5)
                                            .background(AppTheme.navy.opacity(0.12))
                                            .foregroundStyle(AppTheme.navy)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                        }
                                        .buttonStyle(.plain)
                                        .help("点击在 App 内查看论文 PDF: \(att.originalFileName)")
                                        .contextMenu {
                                            Button("在 Finder 中显示") {
                                                if let url = FileService.resolveURL(for: att), FileManager.default.fileExists(atPath: url.path) {
                                                    FileService.reveal(url: url)
                                                }
                                            }
                                            Button("用外部应用打开") {
                                                if let url = FileService.resolveURL(for: att) {
                                                    FileService.openExternally(url: url)
                                                }
                                            }
                                            Divider()
                                            Button("移除该文件", role: .destructive) {
                                                attachmentToDelete = att
                                                showingDeleteAttachmentAlert = true
                                            }
                                        }
                                    }

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

    // MARK: - 唯一论文 PDF 上传与附件处理

    private var eligiblePDFLogs: [StatusLogEntry] {
        manuscript.sortedStatusLogs.filter { $0.status.allowsManuscriptPDF }
    }

    private func startPDFImport(for log: StatusLogEntry) {
        Task {
            guard let picked = await FileService.chooseFile(allowedContentTypes: [.pdf], allowsMultipleSelection: false) else { return }
            guard let first = picked.first else { return }
            processAttachmentImport(file: first, type: .manuscript, log: log)
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
            fileAlertMessage = "未在本地找到附件实体文件。请通过状态时间线标题旁的“上传论文 PDF”重新导入。"
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

// MARK: - PDF 目标时间线节点选择

/// 只展示论文版本会变化的节点，避免在审稿意见或外审状态误传 PDF。
private struct PDFTimelineTargetPicker: View {
    let logs: [StatusLogEntry]
    let onPick: (StatusLogEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("选择论文版本节点")
                .font(AppTheme.serifTitle(20))
            Text("仅首次投稿、修回稿已提交、已接收和已出版节点可上传论文 PDF。")
                .font(AppTheme.serifBody(12))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(logs) { log in
                        Button {
                            onPick(log)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                AppTheme.statusBadge(log.status)

                                if !log.stage.isEmpty {
                                    Text(log.stage)
                                        .font(AppTheme.monoLabel(11))
                                        .foregroundStyle(.secondary)
                                }

                                Text(log.date, format: .dateTime.year().month().day())
                                    .font(AppTheme.monoLabel(11))
                                    .foregroundStyle(.tertiary)

                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 480, height: 360)
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

// MARK: - 录用祝贺文案库与确定性伪随机选择器

struct CelebrationMessage {
    let emoji: String
    let title: String
    let body: String
}

enum CelebrationMessages {
    static let list: [CelebrationMessage] = [
        CelebrationMessage(
            emoji: "🥳",
            title: "大功告成，成功录用！🎊✨",
            body: "Paper Accepted! 所有的反复推敲与深夜修改都有了最好的回音，为你喝彩！💐🍾"
        ),
        CelebrationMessage(
            emoji: "🎉",
            title: "恭喜！论文已被正式接收！🏆",
            body: "从初稿到修回，严谨的数学推导与扎实的研究终获学界同行高度认可！"
        ),
        CelebrationMessage(
            emoji: "🎆",
            title: "苦尽甘来，顺利通关！✨",
            body: "攻克审稿意见，精益求精。祝贺研究成果顺利接收，科研旅途再添高光时刻！"
        ),
        CelebrationMessage(
            emoji: "🍾",
            title: "开香槟！录用通知已抵达！🥂",
            body: "字斟句酌的推演，披星戴月的付出，在这一刻凝聚成最耀眼的成果！"
        ),
        CelebrationMessage(
            emoji: "🌟",
            title: "学术再攀高峰，成功接收！🎯",
            body: "祝贺论文被优秀期刊录用！愿你的学术之路星光璀璨，成果不断！"
        ),
        CelebrationMessage(
            emoji: "💐",
            title: "圆满收官，正式录用！👏",
            body: "每一处公式细节与逻辑打磨都在发光。祝贺录用，期待论文早日正式见刊！"
        ),
        CelebrationMessage(
            emoji: "🔥",
            title: "实至名归，顺利录用！🚀",
            body: "高水平的研究成果值得被全世界学者看见！向扎实严谨的学者致敬！"
        ),
        CelebrationMessage(
            emoji: "🎓",
            title: "科研捷报！论文通过同行评审！📜",
            body: "严谨推导，深邃洞察。经过严苛评审后顺利接收，为你的学术履历再添浓墨重彩的一笔！"
        ),
        CelebrationMessage(
            emoji: "✨",
            title: "星光不问赶路人，论文已接收！🌈",
            body: "无数个专注推演的日夜终于迎来最圆满的答卷。祝贺你，优秀的学者！"
        ),
        CelebrationMessage(
            emoji: "🎊",
            title: "喜提录用！完美的科研成果！💎",
            body: "严谨求实，终成佳作。审稿专家的肯定是对你学术造诣的最佳奖赏！"
        ),
        CelebrationMessage(
            emoji: "🎈",
            title: "通关留念！论文正式接收！🏅",
            body: "从 Response Letter 到最终定稿，每一步都走得无比坚定扎实。为你感到骄傲！"
        ),
        CelebrationMessage(
            emoji: "🏆",
            title: "学术丰碑再立，恭喜录用！🌿",
            body: "用智慧与汗水凝结的学术论文终获圆满。科研漫漫，愿你乘风破浪再创辉煌！"
        ),
        CelebrationMessage(
            emoji: "🍻",
            title: "千锤百炼，终获录用！⚡️",
            body: "经历了细致入微的评审与完善，文章愈发精醇严谨。祝贺顺利接收！"
        ),
        CelebrationMessage(
            emoji: "🪐",
            title: "探索未知，成果落成！💫",
            body: "数学的世界浩瀚深邃，你的探索为这一领域增添了坚实的新基石。恭喜发表！"
        ),
        CelebrationMessage(
            emoji: "🌸",
            title: "花开有期，论文顺利接收！🕊",
            body: "笃行致远，不负热爱。每一篇用心浇灌的学术成果，都会在最美的时刻绽放！"
        ),
        CelebrationMessage(
            emoji: "🥂",
            title: "捷报频传，正式录用！🎉",
            body: "扎实的理论证明与精妙的算法构想，恭喜论文被录用并即将与全球读者见面！"
        )
    ]

    /// 基于稿件稳定属性（ID 与创建时间）计算确定性索引，保证每篇论文分配到不同文案，且每次打开保持一致
    static func message(for manuscript: Manuscript) -> CelebrationMessage {
        var hasher = Hasher()
        hasher.combine(manuscript.id)
        hasher.combine(manuscript.createdAt.timeIntervalSince1970)
        let hash = abs(hasher.finalize())
        return list[hash % list.count]
    }
}
