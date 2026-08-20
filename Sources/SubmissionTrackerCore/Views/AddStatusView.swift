import SwiftUI
import SwiftData

/// 追加一条状态变更记录的小面板。
struct AddStatusView: View {
    @Bindable var manuscript: Manuscript
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var eventDate: Date = .now
    @State private var newStatus: ManuscriptStatus
    @State private var stage: String = ""
    @State private var note: String = ""

    // 可选随状态上传附件
    @State private var pendingFile: (url: URL, type: AttachmentFileType, name: String)?

    init(manuscript: Manuscript) {
        self.manuscript = manuscript
        self._newStatus = State(initialValue: manuscript.currentStatus)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("记录状态变更")
                    .font(AppTheme.serifTitle(20))

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("事件发生日期")
                            .font(AppTheme.monoLabel(12))
                            .foregroundStyle(.secondary)
                        DatePicker("", selection: $eventDate, displayedComponents: .date)
                            .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("新状态")
                            .font(AppTheme.monoLabel(12))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $newStatus) {
                            ForEach(ManuscriptStatus.allCases) { status in
                                Text("\(status.displayNameZh)（\(status.displayNameEn)）").tag(status)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("修改/投稿阶段轮次（可选）")
                        .font(AppTheme.monoLabel(12))
                        .foregroundStyle(.secondary)
                    HStack {
                        ForEach(RevisionStage.allCases) { stg in
                            Button(stg.rawValue) {
                                stage = stg.rawValue
                            }
                            .buttonStyle(.plain)
                            .font(AppTheme.monoLabel(11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(stage == stg.rawValue ? AppTheme.navy.opacity(0.15) : Color.primary.opacity(0.05))
                            .foregroundStyle(stage == stg.rawValue ? AppTheme.navy : .secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        TextField("或自定义轮次", text: $stage)
                            .textFieldStyle(.roundedBorder)
                            .font(AppTheme.monoLabel(12))
                    }
                }

                // 关联本轮附件（可选）
                VStack(alignment: .leading, spacing: 6) {
                    Text("本轮附件（手稿 / 审稿意见 / 回复信）")
                        .font(AppTheme.monoLabel(12))
                        .foregroundStyle(.secondary)

                    if let pf = pendingFile {
                        HStack(spacing: 8) {
                            Text(pf.type.displayNameZh)
                                .font(AppTheme.monoLabel(10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.navy.opacity(0.12))
                                .foregroundStyle(AppTheme.navy)
                                .clipShape(Capsule())

                            Text(pf.name)
                                .font(AppTheme.monoLabel(12))
                                .lineLimit(1)

                            Spacer()

                            Button {
                                pendingFile = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Button {
                            pickAttachmentFile()
                        } label: {
                            Label("选择要绑定的 PDF / 附件…", systemImage: "paperclip")
                        }
                        .font(AppTheme.monoLabel(11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("备注（可选）")
                        .font(AppTheme.monoLabel(12))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $note)
                        .font(AppTheme.serifBody(13))
                        .frame(minHeight: 80)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
                }

                HStack {
                    Spacer()
                    Button("取消") { dismiss() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    Button("保存记录") { save() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 480, minHeight: 400)
    }

    private func pickAttachmentFile() {
        Task {
            guard let picked = await FileService.chooseFile(allowsMultipleSelection: false) else { return }
            guard let first = picked.first else { return }
            // 自动推断类型
            let type: AttachmentFileType
            let lower = first.url.lastPathComponent.lowercased()
            if lower.contains("review") || lower.contains("decision") || lower.contains("comment") || lower.contains("意见") {
                type = .reviewComments
            } else if lower.contains("response") || lower.contains("reply") || lower.contains("回复") {
                type = .responseLetter
            } else {
                type = .manuscript
            }
            pendingFile = (first.url, type, first.url.lastPathComponent)
        }
    }

    private func save() {
        let entry = manuscript.appendStatusLog(
            newStatus,
            date: eventDate,
            stage: stage,
            note: note,
            context: context
        )

        // 若有附件，安全制作 App 本地托管副本
        if let pf = pendingFile {
            if let info = try? FileService.importManagedCopy(
                from: pf.url,
                manuscriptID: manuscript.id,
                statusLogID: entry.id,
                fileType: pf.type,
                customDisplayName: "\(stage.isEmpty ? "" : "[\(stage)] ")\(pf.name)"
            ) {
                let att = Attachment(
                    relativePath: info.relativePath,
                    originalFileName: info.originalFileName,
                    displayName: info.displayName,
                    fileSize: info.fileSize,
                    sha256Hash: info.sha256Hash,
                    mimeType: info.mimeType,
                    syncState: .local,
                    fileType: pf.type,
                    addedDate: eventDate
                )
                att.manuscript = manuscript
                att.statusLog = entry
                if manuscript.attachments == nil { manuscript.attachments = [] }
                manuscript.attachments?.append(att)
                if entry.attachments == nil { entry.attachments = [] }
                entry.attachments?.append(att)
                try? context.save()
            }
        }

        WebDAVSyncService.shared.autoSyncIfNeeded(context: context)
        dismiss()
    }
}
