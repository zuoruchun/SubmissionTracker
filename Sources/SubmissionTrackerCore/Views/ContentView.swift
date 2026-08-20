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
    @State private var showingSettings = false

    public init(showingNewForm: Binding<Bool>) {
        self._showingNewForm = showingNewForm
    }

    public var body: some View {
        NavigationSplitView {
            GlobalTimelineView(selection: $selection, showingNewForm: $showingNewForm)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 500)
        } detail: {
            if let selection {
                ManuscriptDetailView(manuscript: selection)
            } else {
                ContentUnavailableView("选择一篇稿件", systemImage: "sidebar.right",
                    description: Text("在左侧动态流中选择事件或点右上角 + 新增投稿记录"))
                .themedBackground()
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
