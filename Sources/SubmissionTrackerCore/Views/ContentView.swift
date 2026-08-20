import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

/// 主视图：列表 + 详情双栏（macOS 用 NavigationSplitView），
/// 工具栏支持列表 / 看板两种视图切换。
public struct ContentView: View {
    @Query private var allManuscripts: [Manuscript]
    @StateObject private var filter = FilterState()
    @State private var selection: Manuscript? = nil
    @Binding var showingNewForm: Bool
    @AppStorage("STMainViewMode") private var viewModeRaw: String = "detail"
    @State private var showingSettings = false

    public init(showingNewForm: Binding<Bool>) {
        self._showingNewForm = showingNewForm
        self._allManuscripts = Query(filter: nil, sort: \Manuscript.submissionDate, order: .reverse)
    }

    enum ViewMode: String, CaseIterable, Identifiable {
        case detail = "稿件详情"
        case timeline = "全局动态"
        var id: String { rawValue }
    }

    private var viewMode: ViewMode {
        get { ViewMode(rawValue: viewModeRaw) ?? .detail }
        set { viewModeRaw = newValue.rawValue }
    }

    public var body: some View {
        NavigationSplitView {
            ManuscriptListView(selection: $selection, showingNewForm: $showingNewForm)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
        } detail: {
            Group {
                if viewMode == .timeline {
                    GlobalTimelineView(onSelectManuscript: { m in
                        selection = m
                        viewModeRaw = "detail"
                    })
                } else {
                    if let selected = selection ?? allManuscripts.first {
                        ManuscriptDetailView(manuscript: selected)
                    } else {
                        ContentUnavailableView("暂无稿件", systemImage: "book.closed",
                            description: Text("点击左侧右上角 + 新增第一篇投稿记录"))
                        .themedBackground()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("视图模式", selection: $viewModeRaw) {
                        Text("稿件详情").tag("detail")
                        Text("全局动态").tag("timeline")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("偏好设置与坚果云同步 (⌘,)")
                }
            }
        }
        .themedBackground()
        .environmentObject(filter)
        .sheet(isPresented: $showingNewForm) {
            ManuscriptFormView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}
