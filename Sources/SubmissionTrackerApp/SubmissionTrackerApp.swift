import SwiftUI
import SwiftData
import SubmissionTrackerCore
#if os(macOS)
import AppKit
#endif

@main
struct SubmissionTrackerApp: App {
    /// 主容器：优先 CloudKit 同步（容器 iCloud.com.zuoruchun.SubmissionTracker），
    /// 未配置 / 未登录 iCloud 时自动回退本地存储。
    private let container: ModelContainer
    private let cloudKitEnabled: Bool
    @State private var showingNewForm = false

    init() {
        let made = SyncConfig.makeContainer()
        self.container = made.container
        self.cloudKitEnabled = made.cloudKitEnabled

        // 自动导入初始元数据（若尚未导入）
        let context = made.container.mainContext
        if let initialDataURL = Bundle.module.url(forResource: "InitialManuscripts", withExtension: "json"),
           let data = try? Data(contentsOf: initialDataURL) {
            _ = try? ExportService.restore(from: data, into: context)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(showingNewForm: $showingNewForm)
                .modelContainer(container)
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 560)
                #endif
        }
        #if os(macOS)
        .commands {
            CommandGroup(after: .newItem) {
                Button("新增稿件") { showingNewForm = true }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        .defaultSize(width: 1150, height: 720)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(container)
        }
        #endif
    }
}
