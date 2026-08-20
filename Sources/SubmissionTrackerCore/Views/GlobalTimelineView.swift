import SwiftUI
import SwiftData

// MARK: - 动态流条目模型

struct TimelineFeedItem: Identifiable {
    var id: String
    var date: Date
    var status: ManuscriptStatus
    var stage: String
    var note: String
    var manuscript: Manuscript
    var statusLog: StatusLogEntry?
    var attachments: [Attachment]

    init(
        id: String,
        date: Date,
        status: ManuscriptStatus,
        stage: String,
        note: String,
        manuscript: Manuscript,
        statusLog: StatusLogEntry? = nil,
        attachments: [Attachment] = []
    ) {
        self.id = id
        self.date = date
        self.status = status
        self.stage = stage
        self.note = note
        self.manuscript = manuscript
        self.statusLog = statusLog
        self.attachments = attachments
    }
}

// MARK: - 全局投稿动态流视图

struct GlobalTimelineView: View {
    @Query private var allManuscripts: [Manuscript]
    @EnvironmentObject var filter: FilterState
    @Binding var selection: Manuscript?
    @Binding var showingNewForm: Bool

    @State private var previewAttachment: Attachment?
    @State private var previewURL: URL?
    @State private var previewTitle: String = ""

    init(selection: Binding<Manuscript?>, showingNewForm: Binding<Bool>) {
        self._selection = selection
        self._showingNewForm = showingNewForm
    }

    // 展平并构建所有动态事件
    private var allFeedItems: [TimelineFeedItem] {
        var items: [TimelineFeedItem] = []

        for m in allManuscripts {
            let logs = m.sortedStatusLogs
            if logs.isEmpty {
                // 无日志时的兜底事件
                items.append(
                    TimelineFeedItem(
                        id: "m_\(m.id.uuidString)",
                        date: m.submissionDate,
                        status: m.currentStatus,
                        stage: "初始投稿",
                        note: m.notes,
                        manuscript: m,
                        statusLog: nil,
                        attachments: m.unassignedAttachments
                    )
                )
            } else {
                for log in logs {
                    items.append(
                        TimelineFeedItem(
                            id: "log_\(log.id.uuidString)",
                            date: log.date,
                            status: log.status,
                            stage: log.stage,
                            note: log.note,
                            manuscript: m,
                            statusLog: log,
                            attachments: log.sortedAttachments
                        )
                    )
                }
            }
        }

        return items
    }

    // 筛选与严格全局倒序排序
    private var visibleFeedItems: [TimelineFeedItem] {
        let base = allFeedItems.filter { matches($0) }
        return base.sorted { $0.date > $1.date }
    }

    private func matches(_ item: TimelineFeedItem) -> Bool {
        let m = item.manuscript
        let t = filter.searchText.trimmingCharacters(in: .whitespaces)

        // 1. 全文搜索
        if !t.isEmpty {
            let hit = m.title.localizedStandardContains(t)
                || m.venue.localizedStandardContains(t)
                || item.note.localizedStandardContains(t)
                || m.tags.items.contains { $0.localizedStandardContains(t) }
                || m.collaborators.items.contains { $0.localizedStandardContains(t) }
                || m.manuscriptNumber.localizedStandardContains(t)
            if !hit { return false }
        }

        // 2. 状态匹配（精准匹配该事件节点的状态）
        if !filter.statusFilter.isEmpty, !filter.statusFilter.contains(item.status) {
            return false
        }

        // 3. 期刊筛选
        if let selVenue = filter.selectedVenue, m.venue != selVenue {
            return false
        }

        // 4. 仅看有附件
        if filter.onlyWithAttachments, item.attachments.isEmpty {
            return false
        }

        // 5. 标签筛选
        if !filter.tagFilter.isEmpty {
            for tag in filter.tagFilter where !m.tags.items.contains(tag) { return false }
        }

        // 6. 截止日期筛选
        if filter.deadlineFilter != .all {
            guard let dl = m.deadlineDate else { return false }
            let days = Calendar.current.dateComponents([.day], from: Date(), to: dl).day ?? 0
            if filter.deadlineFilter == .upcoming7Days && (days < 0 || days > 7) { return false }
            if filter.deadlineFilter == .overdue && days >= 0 { return false }
        }

        return true
    }

    // 按年月分组（组与组、组内严格倒序）
    private var groupedFeed: [(header: String, items: [TimelineFeedItem])] {
        let cal = Calendar.current
        let byMonth = Dictionary(grouping: visibleFeedItems) { item in
            let c = cal.dateComponents([.year, .month], from: item.date)
            return (c.year ?? 0) * 100 + (c.month ?? 0)
        }
        return byMonth
            .sorted { $0.key > $1.key }
            .map { (key, items) in
                let year = key / 100
                let month = key % 100
                return ("\(year) 年 \(month) 月", items.sorted { $0.date > $1.date })
            }
    }

    var body: some View {
        List(selection: $selection) {
            if visibleFeedItems.isEmpty {
                ContentUnavailableView(
                    "暂无动态记录",
                    systemImage: "calendar.badge.clock",
                    description: Text(filter.hasActiveFilter ? "尝试清除筛选条件" : "点击右上角 + 记录第一篇投稿")
                )
                .listRowSeparator(.hidden)
            }

            ForEach(groupedFeed, id: \.header) { group in
                Section {
                    ForEach(group.items) { item in
                        TimelineFeedRow(
                            item: item,
                            isSelected: selection?.id == item.manuscript.id,
                            onOpenAttachment: { att in
                                openPDF(for: att, manuscriptTitle: item.manuscript.title)
                            }
                        )
                        .tag(item.manuscript)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                } header: {
                    Text(group.header)
                        .font(AppTheme.serifTitle(18))
                        .foregroundStyle(.primary)
                        .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.inset)
        .themedBackground()
        .safeAreaInset(edge: .bottom) {
            filterBar
        }
        .searchable(text: $filter.searchText, placement: .toolbar, prompt: "搜索论文 / 期刊 / 稿件号 / 标签")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("新增投稿记录 (⌘N)")
            }
        }
        .sheet(item: $previewAttachment) { att in
            if let url = previewURL {
                PDFViewerSheet(
                    fileURL: url,
                    title: previewTitle,
                    subtitle: att.fileType.displayNameZh + " · " + att.originalFileName
                )
            }
        }
    }

    // MARK: - 底部快捷筛选条

    private var filterBar: some View {
        HStack(spacing: 8) {
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
                // 期刊筛选
                let venues = FilterState.allVenues(from: allManuscripts)
                if !venues.isEmpty {
                    Menu("按期刊筛选") {
                        Button("全部期刊") { filter.selectedVenue = nil }
                        Divider()
                        ForEach(venues, id: \.self) { v in
                            Button(v) { filter.selectedVenue = v }
                        }
                    }
                }

                // 截止日期
                Menu("修改截止倒计时") {
                    ForEach(DeadlineFilterOption.allCases) { opt in
                        Button(opt.rawValue) { filter.deadlineFilter = opt }
                    }
                }

                Toggle("仅看含附件", isOn: $filter.onlyWithAttachments)

                // 标签筛选
                let tags = FilterState.allTags(from: allManuscripts)
                if !tags.isEmpty {
                    Divider()
                    Text("标签筛选")
                    ForEach(tags, id: \.self) { tag in
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
                    Button("清除全部筛选", role: .destructive) {
                        filter.clearAllFilters()
                    }
                }
            } label: {
                Image(systemName: filter.hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.plain)
            .help("多维筛选与期刊过滤")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.02))
    }

    private func openPDF(for att: Attachment, manuscriptTitle: String) {
        if let url = FileService.resolveURL(for: att) {
            previewURL = url
            previewTitle = manuscriptTitle
            previewAttachment = att
        }
    }
}

// MARK: - 动态流单条卡片

struct TimelineFeedRow: View {
    let item: TimelineFeedItem
    let isSelected: Bool
    let onOpenAttachment: (Attachment) -> Void

    private var daysAgoText: String {
        let days = Calendar.current.dateComponents([.day], from: item.date, to: Date()).day ?? 0
        if days == 0 { return "今天" }
        if days == 1 { return "昨天" }
        if days < 30 { return "\(days)天前" }
        let months = days / 30
        return "\(months)个月前"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 头部：日期 + 状态徽章 + 阶段轮次 + 距今
            HStack(spacing: 8) {
                Text(item.date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                    .font(AppTheme.monoLabel(12))
                    .foregroundStyle(.secondary)

                AppTheme.statusBadge(item.status)

                if !item.stage.isEmpty {
                    Text(item.stage)
                        .font(AppTheme.monoLabel(10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Capsule())
                }

                Spacer()

                Text(daysAgoText)
                    .font(AppTheme.monoLabel(10))
                    .foregroundStyle(.tertiary)
            }

            // 论文标题
            Text(item.manuscript.title)
                .font(AppTheme.serifBody(14))
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundStyle(.primary)

            // 期刊信息与截止时间
            HStack(spacing: 8) {
                Label(item.manuscript.venue, systemImage: AppTheme.venueIcon(item.manuscript.venueType))
                    .font(AppTheme.serifBody(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !item.manuscript.manuscriptNumber.isEmpty {
                    Text("#\(item.manuscript.manuscriptNumber)")
                        .font(AppTheme.monoLabel(10))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if let dl = item.manuscript.deadlineDate {
                    let days = Calendar.current.dateComponents([.day], from: Date(), to: dl).day ?? 0
                    let text = days >= 0 ? "剩 \(days) 天" : "逾期 \(abs(days)) 天"
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.clock")
                        Text(text)
                    }
                    .font(AppTheme.monoLabel(10))
                    .foregroundStyle(days < 7 ? AppTheme.brick : AppTheme.ochre)
                }
            }

            // 备注
            if !item.note.isEmpty {
                Text(item.note)
                    .font(AppTheme.serifBody(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 1)
            }

            // 绑定的附件可点击 Chips
            if !item.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(item.attachments) { att in
                            Button {
                                onOpenAttachment(att)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.text.fill")
                                        .font(.system(size: 10))
                                    Text(att.displayName.isEmpty ? att.fileType.displayNameZh : att.displayName)
                                        .font(AppTheme.monoLabel(10))
                                        .lineLimit(1)
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
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(isSelected ? AppTheme.navy.opacity(0.06) : Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? AppTheme.navy.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
