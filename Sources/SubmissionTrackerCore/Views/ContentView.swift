import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

/// 主视图：列表 + 详情双栏（macOS 用 NavigationSplitView），
/// 工具栏支持列表 / 看板两种视图切换。
public struct ContentView: View {
    @StateObject private var filter = FilterState()
    @State private var selection: Manuscript? = nil
    @Binding var showingNewForm: Bool
    @AppStorage("STMainViewMode") private var viewModeRaw: String = "list"
    @State private var showingSettings = false

    public init(showingNewForm: Binding<Bool>) {
        self._showingNewForm = showingNewForm
    }

    enum ViewMode: String, CaseIterable, Identifiable {
        case list = "稿件列表"
        case timeline = "全局动态"
        var id: String { rawValue }
    }

    private var viewMode: ViewMode {
        get { ViewMode(rawValue: viewModeRaw) ?? .list }
        set { viewModeRaw = newValue.rawValue }
    }

    public var body: some View {
        Group {
            if viewMode == .timeline {
                GlobalTimelineView()
            } else {
                NavigationSplitView {
                    ManuscriptListView(selection: $selection, showingNewForm: $showingNewForm)
                        .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 450)
                } detail: {
                    if let selection {
                        ManuscriptDetailView(manuscript: selection)
                    } else {
                        ContentUnavailableView("选择一篇稿件", systemImage: "sidebar.right",
                            description: Text("在左侧稿件列表中选择一篇稿件或点右上角 + 新增投稿记录"))
                        .themedBackground()
                    }
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
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("视图模式", selection: $viewModeRaw) {
                    Text("稿件列表").tag("list")
                    Text("全局动态").tag("timeline")
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
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
}
