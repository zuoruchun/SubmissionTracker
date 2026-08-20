import SwiftUI
import SwiftData

/// 偏好设置视图（可通过 ⌘, 快捷键或工具栏齿轮打开）
public struct SettingsView: View {
    @ObservedObject private var syncService = WebDAVSyncService.shared
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showingPassword = false
    @State private var testAlertMessage: String?
    @State private var showingTestAlert = false
    @State private var showingRestoreConfirm = false
    @State private var restoreResultAlert: String?
    @State private var showingRestoreResult = false
    @State private var selectedTab = 0

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("偏好设置")
                    .font(AppTheme.serifTitle(16))
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            TabView(selection: $selectedTab) {
                cloudSyncTab
                    .tabItem {
                        Label("云端同步", systemImage: "icloud.and.arrow.up")
                    }
                    .tag(0)

                aboutTab
                    .tabItem {
                        Label("关于与备份", systemImage: "info.circle")
                    }
                    .tag(1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 560, height: 500)
        .alert("连接测试", isPresented: $showingTestAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(testAlertMessage ?? "")
        }
        .alert("确认从云端恢复？", isPresented: $showingRestoreConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认拉取恢复", role: .destructive) {
                performRestore()
            }
        } message: {
            Text("将从坚果云下载最新的备份数据并合并至本地数据库，已存在的记录不会丢失。")
        }
        .alert("恢复结果", isPresented: $showingRestoreResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(restoreResultAlert ?? "")
        }
    }

    // MARK: - 坚果云 / WebDAV 同步 Tab

    private var cloudSyncTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 顶部状态条
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("坚果云 / WebDAV 自动同步")
                            .font(AppTheme.serifTitle(16))
                        if syncService.isSyncing, !syncService.syncProgressMessage.isEmpty {
                            Text(syncService.syncProgressMessage)
                                .font(AppTheme.monoLabel(11))
                                .foregroundStyle(AppTheme.navy)
                        } else {
                            Text("将论文投稿数据及 PDF 附件安全同步至云端，防丢失且支持跨设备恢复。")
                                .font(AppTheme.serifBody(12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if syncService.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        statusBadge
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // 表单配置
                VStack(alignment: .leading, spacing: 12) {
                    // 服务器地址
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("服务器地址 (WebDAV URL)")
                                .font(AppTheme.monoLabel(11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("重置为坚果云") {
                                syncService.serverURL = "https://dav.jianguoyun.com/dav/"
                            }
                            .buttonStyle(.plain)
                            .font(AppTheme.monoLabel(10))
                            .foregroundStyle(AppTheme.accent)
                        }
                        TextField("https://dav.jianguoyun.com/dav/", text: $syncService.serverURL)
                            .textFieldStyle(.roundedBorder)
                    }

                    // 账号
                    VStack(alignment: .leading, spacing: 4) {
                        Text("坚果云账号 (注册邮箱)")
                            .font(AppTheme.monoLabel(11))
                            .foregroundStyle(.secondary)
                        TextField("your_email@example.com", text: $syncService.username)
                            .textFieldStyle(.roundedBorder)
                    }

                    // 应用密码
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("第三方应用授权密码")
                                .font(AppTheme.monoLabel(11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(showingPassword ? "隐藏" : "显示") {
                                showingPassword.toggle()
                            }
                            .buttonStyle(.plain)
                            .font(AppTheme.monoLabel(10))
                            .foregroundStyle(.secondary)
                        }
                        if showingPassword {
                            TextField("坚果云生成的应用密码", text: $syncService.password)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("坚果云生成的应用密码", text: $syncService.password)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    // 自动同步开关
                    Toggle("数据变动时自动上传快照至云端", isOn: $syncService.autoSyncEnabled)
                        .font(AppTheme.serifBody(13))
                        .padding(.top, 4)
                }

                Divider()

                // 操作按钮组
                HStack(spacing: 12) {
                    Button {
                        testConnection()
                    } label: {
                        Label("测试连接", systemImage: "network")
                    }
                    .buttonStyle(.bordered)
                    .disabled(syncService.isSyncing)

                    Button {
                        uploadNow()
                    } label: {
                        Label("立即备份到云端", systemImage: "arrow.up.to.line")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(syncService.isSyncing)

                    Button {
                        showingRestoreConfirm = true
                    } label: {
                        Label("从云端恢复", systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(.bordered)
                    .disabled(syncService.isSyncing)
                }

                // 坚果云密码获取指南
                nutstoreHelpBox
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - 状态标签

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(syncService.lastSyncStatus.contains("成功") || syncService.lastSyncStatus.contains("已备份") ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text(syncService.lastSyncStatus)
                .font(AppTheme.monoLabel(11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 坚果云设置教程

    private var nutstoreHelpBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(AppTheme.accent)
                Text("如何获取坚果云「应用密码」？")
                    .font(AppTheme.serifTitle(13))
            }
            Text("1. 打开浏览器登录 [坚果云网页版](https://www.jianguoyun.com)\n2. 点击右上角「账户名」→「账户信息」→「安全设置」\n3. 找到「第三方应用管理」，点击「添加应用密码」\n4. 应用名称填写「SubmissionTracker」，将生成的密码填入上方。")
                .font(AppTheme.serifBody(11))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 关于与数据 Tab

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: "doc.text.magnifyingglass")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("SubmissionTracker")
                        .font(AppTheme.serifTitle(20))
                    Text("版本 1.0.0 (macOS 原生学术论文投稿管理工具)")
                        .font(AppTheme.monoLabel(11))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("本地数据与存储")
                    .font(AppTheme.serifTitle(14))
                Text("所有投稿数据默认存储在本地 SwiftData 引擎中：\n`~/Library/Application Support/Main.store`")
                    .font(AppTheme.monoLabel(11))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("数据主权与隐私")
                    .font(AppTheme.serifTitle(14))
                Text("SubmissionTracker 为 100% 本地优先应用，除坚果云 WebDAV 同步外，不向任何第三方服务器收集或上传您的任何科研投稿数据。")
                    .font(AppTheme.serifBody(12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
    }

    // MARK: - 动作

    private func testConnection() {
        Task {
            let result = await syncService.testConnection()
            switch result {
            case .success(let msg):
                testAlertMessage = "✅ " + msg
            case .failure(let err):
                testAlertMessage = "❌ " + err.localizedDescription
            }
            showingTestAlert = true
        }
    }

    private func uploadNow() {
        Task {
            let result = await syncService.uploadBackup(from: context)
            switch result {
            case .success(let date):
                testAlertMessage = "✅ 上传成功！\n云端时间: \(date.formatted(date: .abbreviated, time: .standard))"
            case .failure(let err):
                testAlertMessage = "❌ 上传失败: \(err.localizedDescription)"
            }
            showingTestAlert = true
        }
    }

    private func performRestore() {
        Task {
            let result = await syncService.downloadAndRestore(into: context)
            switch result {
            case .success(let count):
                restoreResultAlert = "✅ 成功从坚果云恢复了 \(count) 篇稿件及完整时间线！"
            case .failure(let err):
                restoreResultAlert = "❌ 恢复失败: \(err.localizedDescription)"
            }
            showingRestoreResult = true
        }
    }
}
