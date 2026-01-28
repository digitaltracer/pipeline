import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()

    private let notificationCenter = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }

    func checkPermissionStatus() async -> UNAuthorizationStatus {
        let settings = await notificationCenter.notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - Scheduling

    /// Schedule a follow-up reminder for a job application
    func scheduleFollowUpReminder(
        for applicationID: UUID,
        companyName: String,
        role: String,
        followUpDate: Date,
        timing: ReminderTiming
    ) async {
        // Remove any existing notifications for this application
        await removeNotifications(for: applicationID)

        let baseIdentifier = "followup-\(applicationID.uuidString)"

        switch timing {
        case .dayBefore:
            await scheduleDayBeforeNotification(
                identifier: "\(baseIdentifier)-daybefore",
                companyName: companyName,
                role: role,
                followUpDate: followUpDate
            )

        case .morningOf:
            await scheduleMorningOfNotification(
                identifier: "\(baseIdentifier)-morningof",
                companyName: companyName,
                role: role,
                followUpDate: followUpDate
            )

        case .both:
            await scheduleDayBeforeNotification(
                identifier: "\(baseIdentifier)-daybefore",
                companyName: companyName,
                role: role,
                followUpDate: followUpDate
            )
            await scheduleMorningOfNotification(
                identifier: "\(baseIdentifier)-morningof",
                companyName: companyName,
                role: role,
                followUpDate: followUpDate
            )
        }
    }

    private func scheduleDayBeforeNotification(
        identifier: String,
        companyName: String,
        role: String,
        followUpDate: Date
    ) async {
        let content = UNMutableNotificationContent()
        content.title = "Follow-up Reminder"
        content.body = "Tomorrow: Follow up with \(companyName) for \(role)"
        content.sound = .default
        content.categoryIdentifier = "FOLLOWUP_REMINDER"

        // Schedule for 9 AM the day before
        let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: followUpDate)!
        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: dayBefore)
        dateComponents.hour = 9
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Failed to schedule day-before notification: \(error)")
        }
    }

    private func scheduleMorningOfNotification(
        identifier: String,
        companyName: String,
        role: String,
        followUpDate: Date
    ) async {
        let content = UNMutableNotificationContent()
        content.title = "Follow-up Today"
        content.body = "Time to follow up with \(companyName) for \(role)"
        content.sound = .default
        content.categoryIdentifier = "FOLLOWUP_REMINDER"

        // Schedule for 9 AM on the follow-up date
        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: followUpDate)
        dateComponents.hour = 9
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Failed to schedule morning-of notification: \(error)")
        }
    }

    // MARK: - Management

    /// Remove all notifications for a specific application
    func removeNotifications(for applicationID: UUID) async {
        let identifierPrefix = "followup-\(applicationID.uuidString)"

        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let identifiersToRemove = pendingRequests
            .filter { $0.identifier.hasPrefix(identifierPrefix) }
            .map { $0.identifier }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
    }

    /// Remove all scheduled notifications
    func removeAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
    }

    /// Get all pending notification requests
    func getPendingNotifications() async -> [UNNotificationRequest] {
        return await notificationCenter.pendingNotificationRequests()
    }

    // MARK: - Categories

    func registerCategories() {
        let followUpCategory = UNNotificationCategory(
            identifier: "FOLLOWUP_REMINDER",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([followUpCategory])
    }
}
