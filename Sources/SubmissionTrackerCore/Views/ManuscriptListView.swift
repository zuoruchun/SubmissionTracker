import SwiftUI
import SwiftData

/// 左侧稿件列表：按投稿日期的"年/月"分组，大标题月份头；
/// 无记录的月份不显示。
struct ManuscriptListView: View {
    @Query private var allManuscripts: [Manuscript]
    @EnvironmentObject var filter: FilterState
    @ObservedObject private var fontManager = FontSizeManager.shared
    @Binding var selection: Manuscript?
    @Binding var showingNewForm: Bool

    init(selection: Binding<Manuscript?>, showingNewForm: Binding<Bool>) {
        self._selection = selection
        self._showingNewForm = showingNewForm
        _allManuscripts = Query(filter: nil, sort: \Manuscript.submissionDate, order: .reverse)
    }

    // 应用筛选 + 排序
    private var visibleManuscripts: [Manuscript] {
        let base = filter.hasActiveFilter
            ? allManuscripts.filter { matches($0) }
            : allManuscripts
        return filter.sort(base)
    }

    private func matches(_ m: Manuscript) -> Bool {
        let t = filter.searchText.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty {
            let hit = m.title.localizedStandardContains(t)
                || m.venue.localizedStandardContains(t)
                || m.notes.localizedStandardContains(t)
                || m.collaborators.items.contains { $0.localizedStandardContains(t) }
                || m.tags.items.contains { $0.localizedStandardContains(t) }
            if !hit { return false }
        }
        if !filter.statusFilter.isEmpty, !filter.statusFilter.contains(m.currentStatus) { return false }
        if !filter.tagFilter.isEmpty {
            for tag in filter.tagFilter where !m.tags.items.contains(tag) { return false }
        }
        return true
    }

    // 按月分组：[(key, [Manuscript])]，key 用于大标题
    private var grouped: [(header: String, items: [Manuscript])] {
        let cal = Calendar.current
        let byMonth = Dictionary(grouping: visibleManuscripts) { m in
            let c = cal.dateComponents([.year, .month], from: m.submissionDate)
            return (c.year ?? 0) * 100 + (c.month ?? 0)
        }
        return byMonth
            .sorted { $0.key > $1.key }
            .map { (key, items) in
                let year = key / 100
                let month = key % 100
                return ("\(year)年\(month)月", items)
            }
    }

    var body: some View {
        List(selection: $selection) {
            if visibleManuscripts.isEmpty {
                ContentUnavailableView("暂无稿件", systemImage: "book.closed",
                    description: Text("点右上角 + 新增第一篇投稿记录"))
                .listRowSeparator(.hidden)
            }
            ForEach(grouped, id: \.header) { group in
                Section {
                    ForEach(group.items) { m in
                        ManuscriptRow(manuscript: m)
                            .tag(m)
                    }
                } header: {
                    Text(group.header)
                        .font(AppTheme.serifTitle(20))
                        .foregroundStyle(.primary)
                        .padding(.vertical, 6)
                }
            }
        }
        .listStyle(.inset)
        .themedBackground()
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                // 状态筛选（多选，循环切换）
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ManuscriptStatus.allCases) { status in
                            let isOn = filter.statusFilter.contains(status)
                            Button {
                                if isOn { filter.statusFilter.remove(status) }
                                else { filter.statusFilter.insert(status) }
                            } label: {
                                Text(status.displayNameZh)
                                    .font(AppTheme.monoLabel(11))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(
                                isOn ? AppTheme.statusColor(status).opacity(0.25)
                                      : Color.primary.opacity(0.06)
                            )
                            .foregroundStyle(isOn ? AppTheme.statusColor(status) : .secondary)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 4)
                }
                Menu {
                    Picker("排序", selection: $filter.sortMode) {
                        ForEach(SortMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    if !FilterState.allTags(from: allManuscripts).isEmpty {
                        Divider()
                        Text("标签筛选")
                        ForEach(FilterState.allTags(from: allManuscripts), id: \.self) { tag in
                            Toggle(tag, isOn: Binding(
                                get: { filter.tagFilter.contains(tag) },
                                set: { on in
                                    if on { filter.tagFilter.insert(tag) }
                                    else { filter.tagFilter.remove(tag) }
                                }
                            ))
                        }
                    }
                    if filter.hasActiveFilter {
                        Divider()
                        Button("清除筛选", role: .destructive) {
                            filter.searchText = ""
                            filter.statusFilter = []
                            filter.tagFilter = []
                        }
                    }
                } label: {
                    Image(systemName: filter.hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.plain)
                .help("筛选与排序")
            }
            .padding(.vertical, 6)
        }
        .searchable(text: $filter.searchText, placement: .toolbar, prompt: "搜索标题 / 期刊 / 合作者 / 标签")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("共 \(allManuscripts.count) 篇")
                    .font(AppTheme.monoLabel(12))
                    .foregroundStyle(.secondary)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("新增稿件 (⌘N)")
            }
        }
    }
}

/// 列表行
struct ManuscriptRow: View {
    let manuscript: Manuscript
    @ObservedObject private var fontManager = FontSizeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(manuscript.title)
                    .font(AppTheme.serifBody(15))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Spacer()
                AppTheme.statusBadge(manuscript.currentStatus)
            }
            HStack(spacing: 8) {
                Image(systemName: AppTheme.venueIcon(manuscript.venueType))
                    .font(.system(size: 10 * fontManager.scale))
                    .foregroundStyle(.secondary)
                Text(manuscript.venue)
                    .font(AppTheme.serifBody(12))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(manuscript.submissionDate, format: .dateTime.year().month().day())
                    .font(AppTheme.monoLabel(11))
                    .foregroundStyle(.tertiary)
            }
            if !manuscript.collaborators.items.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person.2")
                        .font(.system(size: 9 * fontManager.scale))
                        .foregroundStyle(.secondary.opacity(0.8))
                    Text(manuscript.collaborators.items.joined(separator: ", "))
                        .font(AppTheme.serifBody(11))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}
