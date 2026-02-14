import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public final class NotificationService {
    public static let shared = NotificationService()

    private let notificationCenter = UNUserNotificationCenter.current()

    private init() {}

    private struct ReminderConfiguration {
        let notificationsEnabled: Bool
        let timing: ReminderTiming

        static func current() -> ReminderConfiguration {
            let defaults = UserDefaults.standard
            let enabled = defaults.bool(forKey: Constants.UserDefaultsKeys.notificationsEnabled)
            let timingRaw = defaults.string(forKey: Constants.UserDefaultsKeys.reminderTiming)
            let timing = timingRaw.flatMap(ReminderTiming.init(rawValue:)) ?? .dayBefore
            return ReminderConfiguration(
                notificationsEnabled: enabled,
                timing: timing
            )
        }
    }

    // MARK: - Permission

    public func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }

    public func checkPermissionStatus() async -> UNAuthorizationStatus {
        let settings = await notificationCenter.notificationSettings()
        return settings.authorizationStatus
    }

    public func authorizationStatusAfterPromptIfNeeded() async -> UNAuthorizationStatus {
        let currentStatus = await checkPermissionStatus()
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        _ = await requestPermission()
        return await checkPermissionStatus()
    }

    public func isPermissionGranted(_ status: UNAuthorizationStatus) -> Bool {
        Self.isPermissionGrantedStatus(status)
    }

    #if canImport(UIKit) || canImport(AppKit)
    @MainActor
    public func openNotificationSettings() {
        #if canImport(UIKit)
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
        #elseif canImport(AppKit)
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(settingsURL)
        #endif
    }
    #endif

    // MARK: - Scheduling

    public func scheduleFollowUpReminder(
        for applicationID: UUID,
        companyName: String,
        role: String,
        followUpDate: Date,
        timing: ReminderTiming
    ) async {
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

    @MainActor
    public func syncFollowUpReminder(for application: JobApplication) async {
        let config = ReminderConfiguration.current()
        let status = await checkPermissionStatus()
        await syncFollowUpReminder(
            for: application,
            notificationsEnabled: config.notificationsEnabled && Self.isPermissionGrantedStatus(status),
            timing: config.timing
        )
    }

    @MainActor
    public func syncFollowUpReminders(
        for applications: [JobApplication],
        notificationsEnabled: Bool,
        timing: ReminderTiming
    ) async {
        let permissionStatus = await checkPermissionStatus()
        let effectiveNotificationsEnabled = notificationsEnabled && Self.isPermissionGrantedStatus(permissionStatus)

        for application in applications {
            await syncFollowUpReminder(
                for: application,
                notificationsEnabled: effectiveNotificationsEnabled,
                timing: timing
            )
        }
    }

    private func syncFollowUpReminder(
        for application: JobApplication,
        notificationsEnabled: Bool,
        timing: ReminderTiming
    ) async {
        guard notificationsEnabled,
              application.status != .archived,
              let followUpDate = application.nextFollowUpDate else {
            await removeNotifications(for: application.id)
            return
        }

        let startOfToday = Calendar.current.startOfDay(for: Date())
        guard followUpDate >= startOfToday else {
            await removeNotifications(for: application.id)
            return
        }

        await scheduleFollowUpReminder(
            for: application.id,
            companyName: application.companyName,
            role: application.role,
            followUpDate: followUpDate,
            timing: timing
        )
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

        guard let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: followUpDate) else {
            return
        }
        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: dayBefore)
        dateComponents.hour = 9
        dateComponents.minute = 0

        guard let fireDate = Calendar.current.date(from: dateComponents),
              fireDate > Date() else {
            return
        }

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

        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: followUpDate)
        dateComponents.hour = 9
        dateComponents.minute = 0

        guard let fireDate = Calendar.current.date(from: dateComponents),
              fireDate > Date() else {
            return
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Failed to schedule morning-of notification: \(error)")
        }
    }

    // MARK: - Management

    public func removeNotifications(for applicationID: UUID) async {
        let identifierPrefix = "followup-\(applicationID.uuidString)"

        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let identifiersToRemove = pendingRequests
            .filter { $0.identifier.hasPrefix(identifierPrefix) }
            .map { $0.identifier }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
    }

    public func removeAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
    }

    public func getPendingNotifications() async -> [UNNotificationRequest] {
        return await notificationCenter.pendingNotificationRequests()
    }

    // MARK: - Categories

    public func registerCategories() {
        let followUpCategory = UNNotificationCategory(
            identifier: "FOLLOWUP_REMINDER",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([followUpCategory])
    }

    private static func isPermissionGrantedStatus(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }
}
