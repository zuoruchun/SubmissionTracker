import SwiftUI
import SwiftData

// MARK: - 全局动态事件模型

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

// MARK: - 全局投稿时间流页面 (替代看板的完整页面)

struct GlobalTimelineView: View {
    @Query private var allManuscripts: [Manuscript]
    @EnvironmentObject var filter: FilterState

    @State private var previewPayload: FilePreviewPayload?
    @State private var inspectedManuscript: Manuscript?
    @State private var showingEditForm = false

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

        // 2. 状态匹配
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
        VStack(spacing: 0) {
            // 顶部多维筛选控制条
            filterHeaderBar

            Divider()

            // 上下滑动的时间线主体
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if visibleFeedItems.isEmpty {
                        ContentUnavailableView(
                            "暂无动态记录",
                            systemImage: "calendar.badge.clock",
                            description: Text(filter.hasActiveFilter ? "尝试清除或放宽筛选条件" : "点击右上角 + 记录第一篇投稿")
                        )
                        .padding(.top, 60)
                    } else {
                        ForEach(groupedFeed, id: \.header) { group in
                            VStack(alignment: .leading, spacing: 14) {
                                // 年月分组大标题
                                HStack(spacing: 8) {
                                    Text(group.header)
                                        .font(AppTheme.serifTitle(22))
                                        .foregroundStyle(.primary)
                                    Text("(\((group.items.count)) 条动态)")
                                        .font(AppTheme.monoLabel(12))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.leading, 6)

                                // 组内纵向连线时间轴
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                        TimelineEventRow(
                                            item: item,
                                            isFirst: index == 0,
                                            isLast: index == group.items.count - 1,
                                            onOpenAttachment: { att in
                                                openPDF(for: att, manuscriptTitle: item.manuscript.title)
                                            },
                                            onInspectManuscript: {
                                                inspectedManuscript = item.manuscript
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: 960, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .themedBackground()
        .sheet(item: $previewPayload) { payload in
            PDFViewerSheet(payload: payload)
        }
        .sheet(item: $inspectedManuscript) { m in
            NavigationStack {
                ManuscriptDetailView(manuscript: m)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { inspectedManuscript = nil }
                        }
                    }
            }
            .frame(minWidth: 780, minHeight: 560)
        }
    }

    // MARK: - 顶部筛选栏

    private var filterHeaderBar: some View {
        HStack(spacing: 12) {
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索论文 / 期刊 / 稿件号 / 标签 / 备注", text: $filter.searchText)
                    .textFieldStyle(.plain)
                    .font(AppTheme.serifBody(13))
                if !filter.searchText.isEmpty {
                    Button {
                        filter.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 320)

            // 状态胶囊筛选
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
                                  : Color.primary.opacity(0.05)
                        )
                        .foregroundStyle(isOn ? AppTheme.statusColor(status) : .secondary)
                        .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            // 更多筛选菜单
            Menu {
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

                Menu("修改截止倒计时") {
                    ForEach(DeadlineFilterOption.allCases) { opt in
                        Button(opt.rawValue) { filter.deadlineFilter = opt }
                    }
                }

                Toggle("仅看含附件", isOn: $filter.onlyWithAttachments)

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
                Label("筛选", systemImage: filter.hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(AppTheme.monoLabel(12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.02))
    }

    private func openPDF(for att: Attachment, manuscriptTitle: String) {
        if let url = FileService.resolveURL(for: att), FileManager.default.fileExists(atPath: url.path) {
            let dispName = att.displayName.isEmpty ? (att.originalFileName.isEmpty ? att.fileType.displayNameZh : att.originalFileName) : att.displayName
            previewPayload = FilePreviewPayload(
                url: url,
                title: manuscriptTitle,
                subtitle: "\(att.fileType.displayNameZh) · \(dispName)"
            )
        }
    }
}

// MARK: - 纵向时间轴单事件卡片 (TimelineEventRow)

struct TimelineEventRow: View {
    let item: TimelineFeedItem
    let isFirst: Bool
    let isLast: Bool
    let onOpenAttachment: (Attachment) -> Void
    let onInspectManuscript: () -> Void

    private var daysAgoText: String {
        let days = Calendar.current.dateComponents([.day], from: item.date, to: Date()).day ?? 0
        if days == 0 { return "今天" }
        if days == 1 { return "昨天" }
        if days < 30 { return "\(days) 天前" }
        let months = days / 30
        return "\(months) 个月前"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // 左侧纵向时间连线 + 状态圆点
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : Color.primary.opacity(0.15))
                    .frame(width: 2)
                    .frame(height: 12)

                Circle()
                    .fill(AppTheme.statusColor(item.status))
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))

                Rectangle()
                    .fill(isLast ? Color.clear : Color.primary.opacity(0.15))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 14)

            // 右侧事件卡片
            VStack(alignment: .leading, spacing: 8) {
                // 顶部：日期 · 距今 · 状态徽章 · 轮次
                HStack(spacing: 8) {
                    Text(item.date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                        .font(AppTheme.monoLabel(13))
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text("(\((daysAgoText)))")
                        .font(AppTheme.monoLabel(11))
                        .foregroundStyle(.tertiary)

                    AppTheme.statusBadge(item.status)

                    if !item.stage.isEmpty {
                        Text(item.stage)
                            .font(AppTheme.monoLabel(10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(AppTheme.navy.opacity(0.1))
                            .foregroundStyle(AppTheme.navy)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    if let dl = item.manuscript.deadlineDate {
                        let days = Calendar.current.dateComponents([.day], from: Date(), to: dl).day ?? 0
                        let text = days >= 0 ? "剩 \(days) 天" : "已逾期 \(abs(days)) 天"
                        HStack(spacing: 4) {
                            Image(systemName: "calendar.badge.clock")
                            Text(text)
                        }
                        .font(AppTheme.monoLabel(10))
                        .foregroundStyle(days < 7 ? AppTheme.brick : AppTheme.ochre)
                    }
                }

                // 论文标题（可点击直接查看这篇论文的详情）
                Button {
                    onInspectManuscript()
                } label: {
                    Text(item.manuscript.title)
                        .font(AppTheme.serifBody(16))
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)

                // 期刊信息
                HStack(spacing: 8) {
                    Label(item.manuscript.venue, systemImage: AppTheme.venueIcon(item.manuscript.venueType))
                        .font(AppTheme.serifBody(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if !item.manuscript.manuscriptNumber.isEmpty {
                        Text("#\(item.manuscript.manuscriptNumber)")
                            .font(AppTheme.monoLabel(11))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button {
                        onInspectManuscript()
                    } label: {
                        Label("查看稿件详情", systemImage: "arrow.up.forward.app")
                            .font(AppTheme.monoLabel(10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                // 动态备注说明
                if !item.note.isEmpty {
                    Text(item.note)
                        .font(AppTheme.serifBody(13))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }

                // 本轮绑定的附件 Chips (带 PDFKit 原生查看)
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
                                        let name = att.displayName.isEmpty ? (att.originalFileName.isEmpty ? att.fileType.displayNameZh : att.originalFileName) : att.displayName
                                        Text(name)
                                            .font(AppTheme.monoLabel(10))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3.5)
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
            .padding(14)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .padding(.bottom, 16)
        }
    }
}
