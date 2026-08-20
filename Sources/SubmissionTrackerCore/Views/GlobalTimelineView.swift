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

// MARK: - 全局投稿时间流 (跨所有论文的全局倒序时间线)

struct GlobalTimelineView: View {
    @Query private var allManuscripts: [Manuscript]
    var onSelectManuscript: ((Manuscript) -> Void)?

    @State private var searchText: String = ""
    @State private var selectedStatus: Set<ManuscriptStatus> = []
    @State private var selectedVenue: String? = nil
    @State private var onlyWithAttachments: Bool = false
    @State private var previewPayload: FilePreviewPayload?

    init(onSelectManuscript: ((Manuscript) -> Void)? = nil) {
        self.onSelectManuscript = onSelectManuscript
        _allManuscripts = Query(filter: nil, sort: \Manuscript.submissionDate, order: .reverse)
    }

    // 展平并提取所有论文的所有状态日志事件
    private var allFeedItems: [TimelineFeedItem] {
        var items: [TimelineFeedItem] = []

        for m in allManuscripts {
            let logs = m.sortedStatusLogs
            if logs.isEmpty {
                // 若该论文暂无日志记录，显示初始投稿节点
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
        let t = searchText.trimmingCharacters(in: .whitespaces)

        if !t.isEmpty {
            let hit = m.title.localizedStandardContains(t)
                || m.venue.localizedStandardContains(t)
                || item.note.localizedStandardContains(t)
                || m.tags.items.contains { $0.localizedStandardContains(t) }
                || m.collaborators.items.contains { $0.localizedStandardContains(t) }
                || m.manuscriptNumber.localizedStandardContains(t)
            if !hit { return false }
        }

        if !selectedStatus.isEmpty, !selectedStatus.contains(item.status) {
            return false
        }

        if let selVenue = selectedVenue, m.venue != selVenue {
            return false
        }

        if onlyWithAttachments, item.attachments.isEmpty {
            return false
        }

        return true
    }

    // 按年月分组
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
                return ("\(year)年\(month)月", items.sorted { $0.date > $1.date })
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 顶部标题与说明
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("全局投稿动态流")
                            .font(AppTheme.serifTitle(24))
                        Spacer()
                        Text("汇集全库 \(allManuscripts.count) 篇论文共 \(allFeedItems.count) 条历史动态")
                            .font(AppTheme.monoLabel(12))
                            .foregroundStyle(.secondary)
                    }

                    // 快速筛选胶囊条
                    filterBar
                }
                .padding(.bottom, 6)

                if visibleFeedItems.isEmpty {
                    ContentUnavailableView(
                        "暂无符合条件的动态记录",
                        systemImage: "calendar.badge.clock",
                        description: Text("当前筛选条件下未匹配到动态记录，可点击下方重置筛选")
                    )
                    .padding(.top, 40)
                    .overlay(
                        Button("重置筛选") {
                            searchText = ""
                            selectedStatus = []
                            selectedVenue = nil
                            onlyWithAttachments = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 90)
                    )
                } else {
                    ForEach(groupedFeed, id: \.header) { group in
                        VStack(alignment: .leading, spacing: 14) {
                            // 年月大标题
                            Text(group.header)
                                .font(AppTheme.serifTitle(20))
                                .foregroundStyle(.primary)
                                .padding(.leading, 4)

                            // 纵向时间线列表
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                    TimelineCardRow(
                                        item: item,
                                        isFirst: index == 0,
                                        isLast: index == group.items.count - 1,
                                        onOpenAttachment: { att in
                                            openPDF(for: att, manuscriptTitle: item.manuscript.title)
                                        },
                                        onSelectManuscript: {
                                            onSelectManuscript?(item.manuscript)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .themedBackground()
        .sheet(item: $previewPayload) { payload in
            PDFViewerSheet(payload: payload)
        }
    }

    // MARK: - 筛选条

    private var filterBar: some View {
        HStack(spacing: 8) {
            // 搜索框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("搜索论文标题 / 期刊 / 动态内容 / 备注", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(AppTheme.serifBody(12))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: 260)

            // 状态胶囊筛选
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(ManuscriptStatus.allCases) { status in
                        let isOn = selectedStatus.contains(status)
                        Button {
                            if isOn { selectedStatus.remove(status) }
                            else { selectedStatus.insert(status) }
                        } label: {
                            Text(status.displayNameZh)
                                .font(AppTheme.monoLabel(11))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
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

            if !selectedStatus.isEmpty || !searchText.isEmpty || selectedVenue != nil || onlyWithAttachments {
                Button("重置") {
                    searchText = ""
                    selectedStatus = []
                    selectedVenue = nil
                    onlyWithAttachments = false
                }
                .font(AppTheme.monoLabel(11))
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
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

// MARK: - 动态卡片行 (带纵向时间轴线)

struct TimelineCardRow: View {
    let item: TimelineFeedItem
    let isFirst: Bool
    let isLast: Bool
    let onOpenAttachment: (Attachment) -> Void
    let onSelectManuscript: () -> Void

    private var daysAgoText: String {
        let days = Calendar.current.dateComponents([.day], from: item.date, to: Date()).day ?? 0
        if days == 0 { return "今天" }
        if days == 1 { return "昨天" }
        if days < 30 { return "\(days) 天前" }
        let months = days / 30
        return "\(months) 个月前"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // 左侧纵向时间连线 + 状态实心圆点
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : Color.primary.opacity(0.15))
                    .frame(width: 2)
                    .frame(height: 10)

                Circle()
                    .fill(AppTheme.statusColor(item.status))
                    .frame(width: 10, height: 10)

                Rectangle()
                    .fill(isLast ? Color.clear : Color.primary.opacity(0.15))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 12)

            // 右侧动态卡片
            VStack(alignment: .leading, spacing: 6) {
                // 顶部：日期 · 状态徽章 · 阶段 · 距今天数 · 详情入口
                HStack(spacing: 8) {
                    AppTheme.statusBadge(item.status)

                    if !item.stage.isEmpty {
                        Text(item.stage)
                            .font(AppTheme.monoLabel(10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(Capsule())
                    }

                    Text(item.date, format: .dateTime.year().month().day())
                        .font(AppTheme.monoLabel(11))
                        .foregroundStyle(.tertiary)

                    Text("(\((daysAgoText)))")
                        .font(AppTheme.monoLabel(10))
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Button {
                        onSelectManuscript()
                    } label: {
                        Label("查看论文详情", systemImage: "doc.plaintext")
                            .font(AppTheme.monoLabel(10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                // 论文标题（可点击切换至该论文）
                Button {
                    onSelectManuscript()
                } label: {
                    Text(item.manuscript.title)
                        .font(AppTheme.serifBody(15))
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)

                // 期刊信息
                HStack(spacing: 6) {
                    Image(systemName: AppTheme.venueIcon(item.manuscript.venueType))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(item.manuscript.venue)
                        .font(AppTheme.serifBody(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if !item.manuscript.manuscriptNumber.isEmpty {
                        Text("#\(item.manuscript.manuscriptNumber)")
                            .font(AppTheme.monoLabel(10))
                            .foregroundStyle(.tertiary)
                    }
                }

                // 动态内容 / 备注
                if !item.note.isEmpty {
                    Text(item.note)
                        .font(AppTheme.serifBody(13))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                }

                // 节点附件 Chips
                if !item.attachments.isEmpty {
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
            .padding(12)
            .background(Color.primary.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
            .padding(.bottom, 12)
        }
    }
}
