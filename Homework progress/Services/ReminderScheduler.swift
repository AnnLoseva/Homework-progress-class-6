//
//  ReminderScheduler.swift
//  Homework progress
//

import Foundation
import UserNotifications

/// Optional local reminders. Off by default; the app works fully when notifications are denied.
enum ReminderSettings {
    static let deadlineEnabledKey = "reminders.deadlines.enabled"
    static let deadlineLeadHoursKey = "reminders.deadlines.leadHours"
    static let weeklyReviewEnabledKey = "reminders.weeklyReview.enabled"
    static let weeklyReviewWeekdayKey = "reminders.weeklyReview.weekday"
    static let weeklyReviewHourKey = "reminders.weeklyReview.hour"
}

struct ReminderScheduler {
    private static let deadlinePrefix = "deadline."
    private static let weeklyReviewID = "weekly-review"

    struct DeadlineItem {
        var id: UUID
        var title: String
        var courseName: String
        var dueDate: Date
    }

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces all pending reminders created by this app with ones matching current settings.
    static func reschedule(deadlines: [DeadlineItem], defaults: UserDefaults = .standard, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter {
            $0.hasPrefix(deadlinePrefix) || $0 == weeklyReviewID
        })

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        if defaults.bool(forKey: ReminderSettings.deadlineEnabledKey) {
            let lead = defaults.object(forKey: ReminderSettings.deadlineLeadHoursKey) as? Int ?? 24
            let upcoming = deadlines
                .map { ($0, $0.dueDate.addingTimeInterval(TimeInterval(-lead * 3600))) }
                .filter { $0.1 > now }
                .sorted { $0.1 < $1.1 }
                .prefix(50) // iOS keeps at most 64 pending requests per app
            for (item, fireDate) in upcoming {
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = String(localized: "\(item.courseName) · due \(item.dueDate.formatted(date: .abbreviated, time: .shortened))")
                content.sound = .default
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let request = UNNotificationRequest(
                    identifier: deadlinePrefix + item.id.uuidString,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
                try? await center.add(request)
            }
        }

        if defaults.bool(forKey: ReminderSettings.weeklyReviewEnabledKey) {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Weekly review")
            content.body = String(localized: "Take a minute to check this week’s homework and set up next week.")
            var components = DateComponents()
            components.weekday = defaults.object(forKey: ReminderSettings.weeklyReviewWeekdayKey) as? Int ?? 7
            components.hour = defaults.object(forKey: ReminderSettings.weeklyReviewHourKey) as? Int ?? 19
            let request = UNNotificationRequest(
                identifier: weeklyReviewID,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            )
            try? await center.add(request)
        }
    }
}
