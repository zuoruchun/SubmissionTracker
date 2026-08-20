import Foundation
import UserNotifications

/// 本地通知服务：deadline 提醒（到期前 N 天推送）。
enum NotificationService {

    /// 请求通知权限（首次调用时）。
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    /// 为某篇稿件的 deadline 安排"提前 N 天"的本地提醒。
    /// - Parameters:
    ///   - id: 稿件 id（用作通知标识，便于去重）
    ///   - title: 稿件标题
    ///   - venue: 期刊/会议名
    ///   - deadline: 截止时间
    ///   - daysBefore: 提前几天提醒（默认 3 天）
    static func scheduleDeadlineReminder(
        id: UUID,
        title: String,
        venue: String,
        deadline: Date,
        daysBefore: Int = 3
    ) async {
        let center = UNUserNotificationCenter.current()
        // 去重：同一稿件只保留最新的一条 deadline 提醒
        center.removePendingNotificationRequests(withIdentifiers: [reminderID(id: id)])

        let fireDate = deadline.addingTimeInterval(TimeInterval(-daysBefore * 86400))
        guard fireDate > Date() else { return } // 已过期的不安排

        let content = UNMutableNotificationContent()
        content.title = "投稿截止提醒"
        content.body = "《\(title)》(\(venue)) 的下一步截止时间为 \(fireDate.formatted(date: .abbreviated, time: .omitted))，请提前准备。"
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: reminderID(id: id), content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// 取消某篇稿件的提醒。
    static func cancelReminder(id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reminderID(id: id)])
    }

    private static func reminderID(id: UUID) -> String {
        "deadline.\(id.uuidString)"
    }
}
