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

    init(manuscript: Manuscript) {
        self.manuscript = manuscript
        self._newStatus = State(initialValue: manuscript.currentStatus)
        self._stage = State(initialValue: Self.defaultStage(for: manuscript.currentStatus))
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

                if usesRevisionRound {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("投稿 / 修回轮次")
                            .font(AppTheme.monoLabel(12))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach(availableStages) { revisionStage in
                                Button(revisionStage.rawValue) {
                                    stage = revisionStage.rawValue
                                }
                                .buttonStyle(.plain)
                                .font(AppTheme.monoLabel(11))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(stage == revisionStage.rawValue ? AppTheme.navy.opacity(0.15) : Color.primary.opacity(0.05))
                                .foregroundStyle(stage == revisionStage.rawValue ? AppTheme.navy : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
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
        .onChange(of: newStatus) { _, status in
            stage = Self.defaultStage(for: status)
        }
    }

    private func save() {
        _ = manuscript.appendStatusLog(
            newStatus,
            date: eventDate,
            stage: stage,
            note: note,
            context: context
        )

        WebDAVSyncService.shared.autoSyncIfNeeded(context: context)
        dismiss()
    }

    private var usesRevisionRound: Bool {
        switch newStatus {
        case .submitted, .majorRevision, .minorRevision, .revisionSubmitted:
            return true
        case .draft, .editorialReview, .underReview, .accept, .published, .reject, .withdrawn:
            return false
        }
    }

    private var availableStages: [RevisionStage] {
        newStatus == .submitted ? [.r0] : [.r1, .r2, .r3, .r4, .r5]
    }

    private static func defaultStage(for status: ManuscriptStatus) -> String {
        switch status {
        case .submitted:
            return RevisionStage.r0.rawValue
        case .majorRevision, .minorRevision, .revisionSubmitted:
            return RevisionStage.r1.rawValue
        case .draft, .editorialReview, .underReview, .accept, .published, .reject, .withdrawn:
            return ""
        }
    }
}
