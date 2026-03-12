import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct NotificationOpenRequest: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case interviewDebrief
        case weeklyDigest
    }

    public let kind: Kind
    public let applicationID: UUID?
    public let interviewActivityID: UUID?
    public let weeklyDigestSnapshotID: UUID?

    public init(
        kind: Kind,
        applicationID: UUID? = nil,
        interviewActivityID: UUID? = nil,
        weeklyDigestSnapshotID: UUID? = nil
    ) {
        self.kind = kind
        self.applicationID = applicationID
        self.interviewActivityID = interviewActivityID
        self.weeklyDigestSnapshotID = weeklyDigestSnapshotID
    }
}

public final class NotificationService: NSObject {
    public static let shared = NotificationService()

    private let notificationCenter = UNUserNotificationCenter.current()
    private var pendingOpenRequest: NotificationOpenRequest?
    @MainActor private var openRequestHandler: ((NotificationOpenRequest) -> Void)?

    private override init() {}

    private enum NotificationCategory {
        static let followUp = "FOLLOWUP_REMINDER"
        static let task = "TASK_REMINDER"
        static let interviewDebrief = "INTERVIEW_DEBRIEF"
        static let weeklyDigest = "WEEKLY_DIGEST"
    }

    private enum NotificationIdentifier {
        static let weeklyDigestReminder = "weekly-digest-reminder"
    }

    private enum NotificationUserInfoKey {
        static let applicationID = "applicationID"
        static let interviewActivityID = "interviewActivityID"
        static let weeklyDigestSnapshotID = "weeklyDigestSnapshotID"
        static let openKind = "openKind"
    }

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
        await removeFollowUpNotifications(for: applicationID)

        let baseIdentifier = "followup-\(applicationID.uuidString)"

        switch timing {
        case .dayBefore:
            await scheduleDayBeforeNotification(
                identifier: "\(baseIdentifier)-daybefore",
                title: "Follow-up Reminder",
                body: "Tomorrow: Follow up with \(companyName) for \(role)",
                dueDate: followUpDate,
                categoryIdentifier: NotificationCategory.followUp
            )

        case .morningOf:
            await scheduleMorningOfNotification(
                identifier: "\(baseIdentifier)-morningof",
                title: "Follow-up Today",
                body: "Time to follow up with \(companyName) for \(role)",
                dueDate: followUpDate,
                categoryIdentifier: NotificationCategory.followUp
            )

        case .both:
            await scheduleDayBeforeNotification(
                identifier: "\(baseIdentifier)-daybefore",
                title: "Follow-up Reminder",
                body: "Tomorrow: Follow up with \(companyName) for \(role)",
                dueDate: followUpDate,
                categoryIdentifier: NotificationCategory.followUp
            )
            await scheduleMorningOfNotification(
                identifier: "\(baseIdentifier)-morningof",
                title: "Follow-up Today",
                body: "Time to follow up with \(companyName) for \(role)",
                dueDate: followUpDate,
                categoryIdentifier: NotificationCategory.followUp
            )
        }
    }

    public func scheduleTaskReminder(
        for taskID: UUID,
        applicationID: UUID,
        companyName: String,
        role: String,
        taskTitle: String,
        dueDate: Date,
        timing: ReminderTiming
    ) async {
        await removeTaskNotifications(for: taskID, applicationID: applicationID)

        let baseIdentifier = "task-\(applicationID.uuidString)-\(taskID.uuidString)"

        switch timing {
        case .dayBefore:
            await scheduleDayBeforeNotification(
                identifier: "\(baseIdentifier)-daybefore",
                title: "Task Reminder",
                body: "Tomorrow: \(taskTitle) for \(companyName) (\(role))",
                dueDate: dueDate,
                categoryIdentifier: NotificationCategory.task
            )

        case .morningOf:
            await scheduleMorningOfNotification(
                identifier: "\(baseIdentifier)-morningof",
                title: "Task Due Today",
                body: "Due today: \(taskTitle) for \(companyName)",
                dueDate: dueDate,
                categoryIdentifier: NotificationCategory.task
            )

        case .both:
            await scheduleDayBeforeNotification(
                identifier: "\(baseIdentifier)-daybefore",
                title: "Task Reminder",
                body: "Tomorrow: \(taskTitle) for \(companyName) (\(role))",
                dueDate: dueDate,
                categoryIdentifier: NotificationCategory.task
            )
            await scheduleMorningOfNotification(
                identifier: "\(baseIdentifier)-morningof",
                title: "Task Due Today",
                body: "Due today: \(taskTitle) for \(companyName)",
                dueDate: dueDate,
                categoryIdentifier: NotificationCategory.task
            )
        }
    }

    public func scheduleInterviewDebriefReminder(
        for activityID: UUID,
        applicationID: UUID,
        companyName: String,
        role: String,
        interviewEndDate: Date
    ) async {
        await removeInterviewDebriefNotifications(for: activityID, applicationID: applicationID)

        let content = UNMutableNotificationContent()
        content.title = "How did your interview at \(companyName) go?"
        content.body = "Capture questions, confidence, and follow-up actions while the details are fresh."
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.interviewDebrief
        content.userInfo = [
            NotificationUserInfoKey.applicationID: applicationID.uuidString,
            NotificationUserInfoKey.interviewActivityID: activityID.uuidString,
            NotificationUserInfoKey.openKind: NotificationOpenRequest.Kind.interviewDebrief.rawValue
        ]

        guard let fireDate = Self.debriefReminderDate(for: interviewEndDate) else {
            return
        }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let request = UNNotificationRequest(
            identifier: interviewDebriefNotificationIdentifier(
                applicationID: applicationID,
                activityID: activityID
            ),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Failed to schedule interview debrief reminder: \(error)")
        }
    }

    public func scheduleWeeklyDigestNotification(for snapshot: WeeklyDigestSnapshot) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = "Your Week in Review"
        content.body = weeklyDigestNotificationBody(for: snapshot)
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.weeklyDigest
        content.userInfo = [
            NotificationUserInfoKey.weeklyDigestSnapshotID: snapshot.id.uuidString,
            NotificationUserInfoKey.openKind: NotificationOpenRequest.Kind.weeklyDigest.rawValue
        ]

        let request = UNNotificationRequest(
            identifier: weeklyDigestNotificationIdentifier(snapshotID: snapshot.id),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        do {
            try await notificationCenter.add(request)
            return true
        } catch {
            print("Failed to schedule weekly digest notification: \(error)")
            return false
        }
    }

    @MainActor
    public func syncWeeklyDigestReminder(
        schedule: WeeklyDigestSchedule,
        notificationsEnabled: Bool,
        digestNotificationsEnabled: Bool
    ) async {
        let permissionStatus = await checkPermissionStatus()
        let effectiveNotificationsEnabled = notificationsEnabled &&
            digestNotificationsEnabled &&
            Self.isPermissionGrantedStatus(permissionStatus)

        await syncWeeklyDigestReminder(
            schedule: schedule,
            notificationsEnabled: effectiveNotificationsEnabled
        )
    }

    @MainActor
    public func syncFollowUpReminder(for application: JobApplication) async {
        await syncReminderState(for: application)
    }

    @MainActor
    public func syncTaskReminder(for task: ApplicationTask) async {
        let config = ReminderConfiguration.current()
        let status = await checkPermissionStatus()
        await syncTaskReminder(
            for: task,
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
        await syncReminderState(
            for: applications,
            notificationsEnabled: notificationsEnabled,
            timing: timing
        )
    }

    @MainActor
    public func syncReminderState(for application: JobApplication) async {
        let config = ReminderConfiguration.current()
        let status = await checkPermissionStatus()
        await syncReminderState(
            for: application,
            notificationsEnabled: config.notificationsEnabled && Self.isPermissionGrantedStatus(status),
            timing: config.timing
        )
    }

    @MainActor
    public func syncReminderState(
        for applications: [JobApplication],
        notificationsEnabled: Bool,
        timing: ReminderTiming
    ) async {
        let permissionStatus = await checkPermissionStatus()
        let effectiveNotificationsEnabled = notificationsEnabled && Self.isPermissionGrantedStatus(permissionStatus)

        for application in applications {
            await syncReminderState(
                for: application,
                notificationsEnabled: effectiveNotificationsEnabled,
                timing: timing
            )
        }
    }

    private func syncReminderState(
        for application: JobApplication,
        notificationsEnabled: Bool,
        timing: ReminderTiming
    ) async {
        await syncFollowUpReminder(
            for: application,
            notificationsEnabled: notificationsEnabled,
            timing: timing
        )

        for task in application.sortedTasks {
            await syncTaskReminder(
                for: task,
                notificationsEnabled: notificationsEnabled,
                timing: timing
            )
        }

        for activity in application.sortedInterviewActivities {
            await syncInterviewDebriefReminder(
                for: activity,
                notificationsEnabled: notificationsEnabled
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
            await removeFollowUpNotifications(for: application.id)
            return
        }

        let startOfToday = Calendar.current.startOfDay(for: Date())
        guard followUpDate >= startOfToday else {
            await removeFollowUpNotifications(for: application.id)
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

    private func syncTaskReminder(
        for task: ApplicationTask,
        notificationsEnabled: Bool,
        timing: ReminderTiming
    ) async {
        guard let application = task.application else { return }

        guard notificationsEnabled,
              application.status != .archived,
              !task.isCompleted,
              let dueDate = task.dueDate else {
            await removeTaskNotifications(for: task.id, applicationID: application.id)
            return
        }

        let startOfToday = Calendar.current.startOfDay(for: Date())
        guard dueDate >= startOfToday else {
            await removeTaskNotifications(for: task.id, applicationID: application.id)
            return
        }

        await scheduleTaskReminder(
            for: task.id,
            applicationID: application.id,
            companyName: application.companyName,
            role: application.role,
            taskTitle: task.displayTitle,
            dueDate: dueDate,
            timing: timing
        )
    }

    private func syncInterviewDebriefReminder(
        for activity: ApplicationActivity,
        notificationsEnabled: Bool
    ) async {
        guard let application = activity.application else { return }

        guard notificationsEnabled,
              application.status != .archived,
              activity.kind == .interview,
              activity.debrief == nil else {
            await removeInterviewDebriefNotifications(for: activity.id, applicationID: application.id)
            return
        }

        await scheduleInterviewDebriefReminder(
            for: activity.id,
            applicationID: application.id,
            companyName: application.companyName,
            role: application.role,
            interviewEndDate: activity.scheduledEndAt
        )
    }

    private func scheduleDayBeforeNotification(
        identifier: String,
        title: String,
        body: String,
        dueDate: Date,
        categoryIdentifier: String
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier

        guard let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: dueDate) else {
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
        title: String,
        body: String,
        dueDate: Date,
        categoryIdentifier: String
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier

        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: dueDate)
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
        let followUpPrefix = "followup-\(applicationID.uuidString)"
        let taskPrefix = "task-\(applicationID.uuidString)-"
        let interviewPrefix = "interview-debrief-\(applicationID.uuidString)-"

        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let identifiersToRemove = pendingRequests
            .filter {
                $0.identifier.hasPrefix(followUpPrefix) ||
                $0.identifier.hasPrefix(taskPrefix) ||
                $0.identifier.hasPrefix(interviewPrefix)
            }
            .map { $0.identifier }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
    }

    public func removeFollowUpNotifications(for applicationID: UUID) async {
        let identifierPrefix = "followup-\(applicationID.uuidString)"

        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let identifiersToRemove = pendingRequests
            .filter { $0.identifier.hasPrefix(identifierPrefix) }
            .map { $0.identifier }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
    }

    public func removeTaskNotifications(for taskID: UUID, applicationID: UUID) async {
        let identifierPrefix = "task-\(applicationID.uuidString)-\(taskID.uuidString)"

        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let identifiersToRemove = pendingRequests
            .filter { $0.identifier.hasPrefix(identifierPrefix) }
            .map { $0.identifier }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
    }

    public func removeInterviewDebriefNotifications(for activityID: UUID, applicationID: UUID) async {
        let identifierPrefix = interviewDebriefNotificationIdentifier(
            applicationID: applicationID,
            activityID: activityID
        )

        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let identifiersToRemove = pendingRequests
            .filter { $0.identifier.hasPrefix(identifierPrefix) }
            .map { $0.identifier }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
    }

    public func removeWeeklyDigestNotifications() {
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [NotificationIdentifier.weeklyDigestReminder]
        )
    }

    public func removeAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
    }

    public func getPendingNotifications() async -> [UNNotificationRequest] {
        return await notificationCenter.pendingNotificationRequests()
    }

    // MARK: - Categories

    public func registerCategories() {
        notificationCenter.delegate = self
        let followUpCategory = UNNotificationCategory(
            identifier: NotificationCategory.followUp,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        let taskCategory = UNNotificationCategory(
            identifier: NotificationCategory.task,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        let interviewDebriefCategory = UNNotificationCategory(
            identifier: NotificationCategory.interviewDebrief,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        let weeklyDigestCategory = UNNotificationCategory(
            identifier: NotificationCategory.weeklyDigest,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([
            followUpCategory,
            taskCategory,
            interviewDebriefCategory,
            weeklyDigestCategory
        ])
    }

    @MainActor
    public func setOpenRequestHandler(_ handler: @escaping (NotificationOpenRequest) -> Void) {
        openRequestHandler = handler
        if let pendingOpenRequest {
            self.pendingOpenRequest = nil
            handler(pendingOpenRequest)
        }
    }

    @MainActor
    public func clearOpenRequestHandler() {
        openRequestHandler = nil
    }

    @MainActor
    public func consumePendingOpenRequest() -> NotificationOpenRequest? {
        defer { pendingOpenRequest = nil }
        return pendingOpenRequest
    }

    static func debriefReminderDate(for interviewEndDate: Date) -> Date? {
        let fireDate = interviewEndDate.addingTimeInterval(30 * 60)
        return fireDate > Date() ? fireDate : nil
    }

    private func syncWeeklyDigestReminder(
        schedule: WeeklyDigestSchedule,
        notificationsEnabled: Bool
    ) async {
        removeWeeklyDigestNotifications()

        guard notificationsEnabled else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Your weekly digest is ready"
        content.body = "Open Pipeline to review this week's momentum, follow-ups, and next actions."
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.weeklyDigest
        content.userInfo = [
            NotificationUserInfoKey.openKind: NotificationOpenRequest.Kind.weeklyDigest.rawValue
        ]

        var dateComponents = DateComponents()
        dateComponents.weekday = schedule.weekday
        dateComponents.hour = schedule.hour
        dateComponents.minute = schedule.minute

        let request = UNNotificationRequest(
            identifier: NotificationIdentifier.weeklyDigestReminder,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Failed to sync weekly digest reminder: \(error)")
        }
    }

    private func interviewDebriefNotificationIdentifier(applicationID: UUID, activityID: UUID) -> String {
        "interview-debrief-\(applicationID.uuidString)-\(activityID.uuidString)"
    }

    private func weeklyDigestNotificationIdentifier(snapshotID: UUID) -> String {
        "weekly-digest-\(snapshotID.uuidString)"
    }

    private func weeklyDigestNotificationBody(for snapshot: WeeklyDigestSnapshot) -> String {
        var fragments = [
            "\(snapshot.newApplicationsCount) new app\(snapshot.newApplicationsCount == 1 ? "" : "s")",
            "\(Int((snapshot.responseRate * 100).rounded()))% response rate"
        ]

        if snapshot.interviewsScheduledCount > 0 {
            fragments.append("\(snapshot.interviewsScheduledCount) interview\(snapshot.interviewsScheduledCount == 1 ? "" : "s") next week")
        }

        if let primaryInsight = snapshot.sortedInsights.first {
            fragments.append(primaryInsight.title)
        }

        return fragments.joined(separator: " • ")
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

extension NotificationService: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let request = openRequest(from: response.notification.request.content.userInfo) else {
            return
        }

        await MainActor.run {
            if let openRequestHandler {
                openRequestHandler(request)
            } else {
                pendingOpenRequest = request
            }
        }
    }

    private func openRequest(from userInfo: [AnyHashable: Any]) -> NotificationOpenRequest? {
        guard let rawKind = userInfo[NotificationUserInfoKey.openKind] as? String,
              let kind = NotificationOpenRequest.Kind(rawValue: rawKind) else {
            return nil
        }

        let applicationID: UUID?
        if let rawApplicationID = userInfo[NotificationUserInfoKey.applicationID] as? String {
            applicationID = UUID(uuidString: rawApplicationID)
        } else {
            applicationID = nil
        }

        let activityID: UUID?
        if let rawActivityID = userInfo[NotificationUserInfoKey.interviewActivityID] as? String {
            activityID = UUID(uuidString: rawActivityID)
        } else {
            activityID = nil
        }

        let snapshotID: UUID?
        if let rawSnapshotID = userInfo[NotificationUserInfoKey.weeklyDigestSnapshotID] as? String {
            snapshotID = UUID(uuidString: rawSnapshotID)
        } else {
            snapshotID = nil
        }

        return NotificationOpenRequest(
            kind: kind,
            applicationID: applicationID,
            interviewActivityID: activityID,
            weeklyDigestSnapshotID: snapshotID
        )
    }
}
