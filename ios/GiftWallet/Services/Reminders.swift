import Foundation
import SwiftData
import UserNotifications

/// Local notifications before a voucher expires (30, 7 and 1 days ahead, at 10:00).
enum Reminders {
    static let prefix = "expiry."

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    @MainActor
    static func reschedule(container: ModelContainer) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        guard AppSettings.shared.expiryReminders else { return }

        let vouchers = (try? ModelContext(container).fetch(FetchDescriptor<Voucher>())) ?? []
        let cal = Calendar.current
        for v in vouchers where v.isUsable {
            guard let expiry = v.expiry else { continue }
            for daysBefore in [30, 7, 1] {
                guard let day = cal.date(byAdding: .day, value: -daysBefore, to: expiry),
                      var fire = cal.date(bySettingHour: 10, minute: 0, second: 0, of: day),
                      fire > .now else { continue }
                if fire < .now { fire = .now.addingTimeInterval(60) }
                let content = UNMutableNotificationContent()
                content.title = daysBefore == 1 ? "⏰ השובר פג מחר" : "⏰ השובר יפוג בעוד \(daysBefore) ימים"
                content.body = "\(v.displayTitle) · יתרה \(v.balance.shekels). כדאי לתכנן מימוש."
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
                    repeats: false)
                let id = "\(prefix)\(v.persistentModelID.hashValue).\(daysBefore)"
                try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }
}
