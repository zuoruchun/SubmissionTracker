import SwiftUI
import SwiftData

/// 追加一条状态变更记录的小面板。
struct AddStatusView: View {
    @Bindable var manuscript: Manuscript
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var newStatus: ManuscriptStatus
    @State private var note: String = ""

    init(manuscript: Manuscript) {
        self.manuscript = manuscript
        self._newStatus = State(initialValue: manuscript.currentStatus)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("记录状态变更")
                .font(AppTheme.serifTitle(20))

            VStack(alignment: .leading, spacing: 8) {
                Text("新状态")
                    .font(AppTheme.monoLabel(12))
                    .foregroundStyle(.secondary)
                Picker("状态", selection: $newStatus) {
                    ForEach(ManuscriptStatus.allCases) { status in
                        Text("\(status.displayNameZh)（\(status.displayNameEn)）").tag(status)
                    }
                }
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("备注（可选）")
                    .font(AppTheme.monoLabel(12))
                    .foregroundStyle(.secondary)
                TextEditor(text: $note)
                    .font(AppTheme.serifBody(14))
                    .frame(minHeight: 90)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .presentationDetents([.medium])
    }

    private func save() {
        manuscript.appendStatusLog(newStatus, note: note, context: context)
        dismiss()
    }
}
