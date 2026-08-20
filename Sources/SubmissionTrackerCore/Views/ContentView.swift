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
    @AppStorage("STViewMode") private var viewModeRaw: String = "list"

    @State private var showingSettings = false

    public init(showingNewForm: Binding<Bool>) {
        self._showingNewForm = showingNewForm
    }

    enum ViewMode: String, CaseIterable, Identifiable {
        case list = "列表"
        case board = "看板"
        var id: String { rawValue }
    }

    private var viewMode: ViewMode {
        get { ViewMode(rawValue: viewModeRaw) ?? .list }
        set { viewModeRaw = newValue.rawValue }
    }

    public var body: some View {
        Group {
            if viewMode == .board {
                KanbanBoardView()
            } else {
                NavigationSplitView {
                    ManuscriptListView(selection: $selection, showingNewForm: $showingNewForm)
                } detail: {
                    if let selection {
                        ManuscriptDetailView(manuscript: selection)
                    } else {
                        ContentUnavailableView("选择一篇稿件", systemImage: "sidebar.right",
                            description: Text("或点右上角 + 新增投稿记录"))
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
                Picker("视图", selection: $viewModeRaw) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
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
