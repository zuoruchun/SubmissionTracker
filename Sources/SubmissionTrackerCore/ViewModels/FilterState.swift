import Foundation
import SwiftUI
import SwiftData

/// 排序方式
enum SortMode: String, CaseIterable, Identifiable {
    case submissionDateDesc = "投稿日期 ↓"
    case submissionDateAsc = "投稿日期 ↑"
    case updatedAtDesc = "最近更新"
    case titleAsc = "标题 A-Z"

    var id: String { rawValue }
}

/// 截止日期筛选
enum DeadlineFilterOption: String, CaseIterable, Identifiable {
    case all = "全部"
    case upcoming7Days = "7天内截止"
    case overdue = "已逾期"

    var id: String { rawValue }
}

/// 列表/筛选状态（由 UI 持有，供 @Query 与动态时间流使用）。
@MainActor
final class FilterState: ObservableObject {
    @Published var searchText: String = ""
    /// 已勾选的状态筛选（空 = 不过滤）
    @Published var statusFilter: Set<ManuscriptStatus> = []
    /// 已勾选的标签筛选（空 = 不过滤）
    @Published var tagFilter: Set<String> = []
    /// 指定期刊筛选
    @Published var selectedVenue: String? = nil
    /// 是否仅看含附件
    @Published var onlyWithAttachments: Bool = false
    /// 截止日期筛选
    @Published var deadlineFilter: DeadlineFilterOption = .all
    @Published var sortMode: SortMode = .submissionDateDesc

    init() {}

    var hasActiveFilter: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
            || !statusFilter.isEmpty
            || !tagFilter.isEmpty
            || selectedVenue != nil
            || onlyWithAttachments
            || deadlineFilter != .all
    }

    func clearAllFilters() {
        searchText = ""
        statusFilter = []
        tagFilter = []
        selectedVenue = nil
        onlyWithAttachments = false
        deadlineFilter = .all
    }

    /// 按 sortMode 对结果排序
    func sort(_ manuscripts: [Manuscript]) -> [Manuscript] {
        switch sortMode {
        case .submissionDateDesc:
            return manuscripts.sorted { $0.submissionDate > $1.submissionDate }
        case .submissionDateAsc:
            return manuscripts.sorted { $0.submissionDate < $1.submissionDate }
        case .updatedAtDesc:
            return manuscripts.sorted { $0.updatedAt > $1.updatedAt }
        case .titleAsc:
            return manuscripts.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        }
    }

    /// 所有出现过的标签（用于筛选菜单）
    static func allTags(from manuscripts: [Manuscript]) -> [String] {
        var set = Set<String>()
        for m in manuscripts { set.formUnion(m.tags.items) }
        return set.sorted()
    }

    /// 所有出现过的期刊/会议名称
    static func allVenues(from manuscripts: [Manuscript]) -> [String] {
        var set = Set<String>()
        for m in manuscripts where !m.venue.trimmingCharacters(in: .whitespaces).isEmpty {
            set.insert(m.venue)
        }
        return set.sorted()
    }
}
