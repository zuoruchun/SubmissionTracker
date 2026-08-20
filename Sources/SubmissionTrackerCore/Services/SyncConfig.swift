import Foundation
import SwiftData
import CloudKit

/// CloudKit / SwiftData 容器配置。
///
/// 注意：
/// - `cloudKitDatabase: .automatic` 要求开发者账号里真实存在容器
///   `iCloud.com.zuoruchun.SubmissionTracker`，且运行设备登录了同一 Apple ID。
///   在 Xcode 生成 .xcodeproj 后，需在 Target → Signing & Capabilities 中
///   添加 iCloud（CloudKit）并选择该容器（此步必须在 Xcode 中手动完成）。
/// - 若容器尚未创建或设备未登录 iCloud，`ModelContainer` 初始化会抛错；
///   此时 `makeContainer` 回退到**仅本地**容器，保证 App 可用，待配置
///   容器后重启即自动切到云端同步。
public enum SyncConfig {

    public static let containerIdentifier = "iCloud.com.zuoruchun.SubmissionTracker"

    public static var schema: Schema {
        Schema([Manuscript.self, StatusLogEntry.self, Attachment.self])
    }

    /// 创建主容器：优先 CloudKit 同步，失败则回退本地。
    /// - Returns: (容器, 是否启用 CloudKit)
    @MainActor
    public static func makeContainer() -> (container: ModelContainer, cloudKitEnabled: Bool) {
        do {
            let config = ModelConfiguration(
                "Main",
                schema: schema,
                cloudKitDatabase: .automatic
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            return (container, true)
        } catch {
            #if DEBUG
            print("[SyncConfig] CloudKit 容器不可用（\(error)），回退到本地存储。请在 Xcode 中配置 iCloud capability 并确保已登录 iCloud 账号。")
            #endif
            let config = ModelConfiguration("Main", schema: schema)
            let container = try! ModelContainer(for: schema, configurations: [config])
            return (container, false)
        }
    }
}
