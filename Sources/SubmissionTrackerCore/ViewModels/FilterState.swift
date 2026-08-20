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

/// 列表/筛选状态（由 UI 持有，供 @Query 动态谓词使用）。
@MainActor
final class FilterState: ObservableObject {
    @Published var searchText: String = ""
    /// 已勾选的状态筛选（空 = 不过滤）
    @Published var statusFilter: Set<ManuscriptStatus> = []
    /// 已勾选的标签筛选（空 = 不过滤）
    @Published var tagFilter: Set<String> = []
    @Published var sortMode: SortMode = .submissionDateDesc

    var hasActiveFilter: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
            || !statusFilter.isEmpty
            || !tagFilter.isEmpty
    }

    /// 用于 @Query 的动态谓词：标题/期刊/标签/备注全文搜索 + 状态 + 标签筛选。
    var predicate: Predicate<Manuscript>? {
        let text = searchText.trimmingCharacters(in: .whitespaces)
        let statuses = statusFilter.map(\.rawValue)
        let tags = Array(tagFilter)

        if text.isEmpty && statuses.isEmpty && tags.isEmpty { return nil }

        let t = text
        let s = statuses
        let g = tags
        return #Predicate<Manuscript> { m in
            (t.isEmpty ||
                m.title.localizedStandardContains(t) ||
                m.venue.localizedStandardContains(t) ||
                m.notes.localizedStandardContains(t) ||
                m.tags.items.contains { $0.localizedStandardContains(t) })
            && (s.isEmpty || s.contains(m.currentStatusRaw))
            && (g.isEmpty || g.allSatisfy { tag in m.tags.items.contains(tag) })
        }
    }

    /// 所有出现过的标签（用于筛选菜单）
    static func allTags(from manuscripts: [Manuscript]) -> [String] {
        var set = Set<String>()
        for m in manuscripts { set.formUnion(m.tags.items) }
        return set.sorted()
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
}
