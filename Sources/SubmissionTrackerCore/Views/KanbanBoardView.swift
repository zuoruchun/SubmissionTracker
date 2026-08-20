import SwiftUI
import SwiftData

/// 看板视图：按状态分列。
/// 支持拖拽卡片切换状态，拖拽时自动追加一条状态记录。
struct KanbanBoardView: View {
    @Query private var manuscripts: [Manuscript]
    @Environment(\.modelContext) private var context

    init() {
        _manuscripts = Query(sort: \Manuscript.updatedAt, order: .reverse)
    }

    /// 看板列：按状态 order 排列
    private var columns: [ManuscriptStatus] {
        ManuscriptStatus.allCases.sorted { $0.order < $1.order }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(columns) { status in
                    KanbanColumn(
                        status: status,
                        items: manuscripts.filter { $0.currentStatus == status },
                        lookup: { id in lookup(id) },
                        onMove: { move($0, to: status) }
                    )
                    .frame(width: 270)
                }
            }
            .padding(16)
        }
        .themedBackground()
    }

    /// 通过 id 找回稿件实体
    private func lookup(_ id: UUID) -> Manuscript? {
        var descriptor = FetchDescriptor<Manuscript>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// 拖拽落点：切换状态并自动追加状态记录
    private func move(_ m: Manuscript, to status: ManuscriptStatus) {
        guard m.currentStatus != status else { return }
        m.appendStatusLog(status, note: "看板拖拽变更状态", context: context)
    }
}

/// 看板单列
struct KanbanColumn: View {
    let status: ManuscriptStatus
    let items: [Manuscript]
    let lookup: (UUID) -> Manuscript?
    let onMove: (Manuscript) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: AppTheme.statusIcon(status))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.statusColor(status))
                Text(status.displayNameZh)
                    .font(AppTheme.serifTitle(15))
                Text("\(items.count)")
                    .font(AppTheme.monoLabel(11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
            }
            .padding(.bottom, 2)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(items) { m in
                        KanbanCard(manuscript: m)
                            .draggable(m.transfer) {
                                KanbanDragPreview(manuscript: m)
                            }
                    }
                    if items.isEmpty {
                        Text("（空）")
                            .font(AppTheme.serifBody(12))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .themedCard()
        .frame(maxHeight: .infinity, alignment: .top)
        .dropDestination(for: ManuscriptTransfer.self) { transfers, _ in
            guard let first = transfers.first,
                  let m = lookup(first.id) else { return false }
            onMove(m)
            return true
        }
    }
}

/// 看板卡片
struct KanbanCard: View {
    let manuscript: Manuscript

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(manuscript.title)
                .font(AppTheme.serifBody(13))
                .lineLimit(2)
            HStack {
                Image(systemName: AppTheme.venueIcon(manuscript.venueType))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(manuscript.venue)
                    .font(AppTheme.serifBody(11))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(manuscript.submissionDate, format: .dateTime.year().month().day())
                    .font(AppTheme.monoLabel(10))
                    .foregroundStyle(.tertiary)
                Spacer()
                if let d = manuscript.deadlineDate {
                    Text("截止 \(d.formatted(.dateTime.month().day()))")
                        .font(AppTheme.monoLabel(10))
                        .foregroundStyle(AppTheme.ochre)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(.background).opacity(0.6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.08)))
    }
}

/// 拖拽预览
struct KanbanDragPreview: View {
    let manuscript: Manuscript
    var body: some View {
        Text(manuscript.title)
            .font(AppTheme.serifBody(12))
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.paperDark))
            .frame(width: 200, alignment: .leading)
    }
}

/// 用于 Transferable 的值类型（只带 id，落点时按 id 找回实体）
struct ManuscriptTransfer: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

extension Manuscript {
    var transfer: ManuscriptTransfer { ManuscriptTransfer(id: id) }
}
