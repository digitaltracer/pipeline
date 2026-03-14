import Foundation
import SwiftData

@MainActor
public final class GoogleCalendarImportCoordinator {
    public static let shared = GoogleCalendarImportCoordinator()

    private let oauthService = GoogleOAuthService.shared
    private let calendarService = GoogleCalendarService.shared
    private let interviewSyncCoordinator = GoogleCalendarInterviewSyncCoordinator.shared

    private init() {}

    public func restoreSessionIfPossible(in context: ModelContext) async {
        guard let credentials = await oauthService.restorePreviousSession() else {
            markAccountDisconnected(in: context)
            return
        }

        do {
            try upsertAccount(with: credentials, in: context)
        } catch {
            context.rollback()
        }
    }

    public func connect(in context: ModelContext) async throws {
        let credentials = try await oauthService.signIn()
        try upsertAccount(with: credentials, in: context)
        try await refreshCalendarList(in: context)
        try await syncNow(in: context)
    }

    public func disconnect(in context: ModelContext) async {
        await oauthService.disconnect()
        markAccountDisconnected(in: context)
    }

    public func refreshCalendarList(in context: ModelContext) async throws {
        let accessToken = try await oauthService.accessToken()
        let calendars = try await calendarService.fetchCalendars(accessToken: accessToken)
        try upsertSubscriptions(calendars, in: context)
    }

    public func syncIfNeeded(in context: ModelContext) async {
        guard let account = fetchAccount(in: context), account.isConnected else { return }
        do {
            if account.lastSyncedAt == nil || abs(account.lastSyncedAt?.timeIntervalSinceNow ?? 0) > 60 {
                try await syncNow(in: context)
            }
        } catch {
            // Ignore transient sync failures during passive refresh.
        }
    }

    public func syncNow(in context: ModelContext, referenceDate: Date = Date()) async throws {
        guard let account = fetchAccount(in: context), account.isConnected else { return }

        let accessToken = try await oauthService.accessToken()
        let subscriptions = fetchSelectedSubscriptions(in: context)
        guard !subscriptions.isEmpty else { return }

        let applications = fetchApplications(in: context)

        for subscription in subscriptions {
            do {
                let response = try await calendarService.syncEvents(
                    calendarID: subscription.calendarID,
                    calendarName: subscription.title,
                    accessToken: accessToken,
                    syncToken: subscription.syncToken,
                    referenceDate: referenceDate
                )
                try await apply(
                    response.events,
                    to: subscription,
                    applications: applications,
                    in: context
                )
                subscription.syncToken = response.nextSyncToken
            } catch let error as GoogleCalendarServiceError where error == .invalidSyncToken {
                subscription.syncToken = nil
                let response = try await calendarService.syncEvents(
                    calendarID: subscription.calendarID,
                    calendarName: subscription.title,
                    accessToken: accessToken,
                    syncToken: nil,
                    referenceDate: referenceDate
                )
                try await apply(
                    response.events,
                    to: subscription,
                    applications: applications,
                    in: context
                )
                subscription.syncToken = response.nextSyncToken
            }

            subscription.lastSyncedAt = referenceDate
            subscription.updateTimestamp()
        }

        account.lastSyncedAt = referenceDate
        account.updateTimestamp()
        try context.save()
    }

    public func setCalendarSelection(
        _ subscription: GoogleCalendarSubscription,
        isSelected: Bool,
        in context: ModelContext
    ) throws {
        subscription.isSelected = isSelected
        if !isSelected {
            subscription.syncToken = nil
        }
        subscription.updateTimestamp()
        try context.save()
    }

    public func setWriteTarget(
        _ subscription: GoogleCalendarSubscription,
        in context: ModelContext
    ) throws {
        for candidate in fetchSubscriptions(in: context) {
            candidate.isWriteTarget = candidate.id == subscription.id
            candidate.updateTimestamp()
        }
        try context.save()
    }

    public func acceptImport(
        _ record: GoogleCalendarImportRecord,
        into application: JobApplication,
        in context: ModelContext
    ) async throws {
        let activity: ApplicationActivity
        let eventPayload = GoogleCalendarEventPayload(
            calendarID: record.remoteCalendarID,
            calendarName: record.remoteCalendarName,
            eventID: record.remoteEventID,
            etag: record.remoteETag,
            status: record.remoteStatus,
            htmlLink: record.htmlLink,
            summary: record.summary,
            location: record.location,
            details: record.details,
            organizerEmail: record.organizerEmail,
            startDate: record.startDate,
            endDate: record.endDate,
            isAllDay: record.isAllDay,
            privateMetadata: [:]
        )

        if let importedActivity = record.importedActivity {
            activity = importedActivity
        } else if let existingNearby = dedupeCandidate(for: application, event: eventPayload) {
            activity = existingNearby
            record.importedActivity = existingNearby
        } else {
            activity = ApplicationActivity(kind: .interview, application: application)
            context.insert(activity)
            application.addActivity(activity)
            record.importedActivity = activity
        }

        activity.kind = .interview
        activity.occurredAt = record.startDate
        activity.scheduledDurationMinutes = scheduledDurationMinutes(start: record.startDate, end: record.endDate)
        activity.interviewStage = GoogleCalendarMatchingService.inferInterviewStage(for: eventPayload)
        activity.notes = composedActivityNotes(for: record)
        activity.emailSubject = nil
        activity.emailBodySnapshot = nil
        activity.updateTimestamp()

        record.suggestedApplication = application
        record.state = .imported
        record.updateTimestamp()

        syncInterviewState(for: application, context: context)

        try context.save()
        try await interviewSyncCoordinator.syncImportedInterview(
            activity,
            application: application,
            remoteEvent: eventPayload,
            in: context
        )
    }

    public func ignoreImport(_ record: GoogleCalendarImportRecord, in context: ModelContext) throws {
        record.state = record.importedActivity == nil ? .ignored : .imported
        record.updateTimestamp()
        try context.save()
    }

    private func upsertAccount(with credentials: GoogleOAuthCredentialBundle, in context: ModelContext) throws {
        let account = fetchAccount(in: context) ?? GoogleCalendarAccount(
            googleUserID: credentials.googleUserID,
            email: credentials.email
        )

        if account.modelContext == nil {
            context.insert(account)
        }

        account.googleUserID = credentials.googleUserID
        account.email = credentials.email
        account.displayName = credentials.displayName
        account.avatarURLString = credentials.avatarURLString
        account.isConnected = true
        account.updateTimestamp()
        try context.save()
    }

    private func markAccountDisconnected(in context: ModelContext) {
        guard let account = fetchAccount(in: context) else { return }
        account.isConnected = false
        account.updateTimestamp()
        try? context.save()
    }

    private func upsertSubscriptions(_ calendars: [GoogleCalendarListEntry], in context: ModelContext) throws {
        let existing = fetchSubscriptions(in: context)
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.calendarID, $0) })
        let hasSelection = existing.contains(where: \.isSelected)
        let hasWriteTarget = existing.contains(where: \.isWriteTarget)

        for entry in calendars {
            let subscription = existingByID[entry.id] ?? GoogleCalendarSubscription(
                calendarID: entry.id,
                title: entry.title
            )
            if subscription.modelContext == nil {
                context.insert(subscription)
            }
            subscription.title = entry.title
            subscription.colorHex = entry.colorHex
            subscription.isPrimary = entry.isPrimary
            if !hasSelection {
                subscription.isSelected = entry.isPrimary
            }
            if !hasWriteTarget {
                subscription.isWriteTarget = entry.isPrimary
            }
            subscription.updateTimestamp()
        }

        let incomingIDs = Set(calendars.map(\.id))
        for subscription in existing where !incomingIDs.contains(subscription.calendarID) {
            context.delete(subscription)
        }

        if let account = fetchAccount(in: context) {
            account.lastCalendarListRefreshAt = Date()
            account.updateTimestamp()
        }

        try context.save()
    }

    private func apply(
        _ events: [GoogleCalendarEventPayload],
        to subscription: GoogleCalendarSubscription,
        applications: [JobApplication],
        in context: ModelContext
    ) async throws {
        let existingRecords = fetchImportRecords(for: subscription.calendarID, in: context)
        let recordsByID = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.remoteEventID, $0) })
        let aliases = fetchCompanyAliases(in: context)

        for event in events {
            if let link = interviewSyncCoordinator.fetchLink(forRemoteEventID: event.eventID, in: context) {
                await interviewSyncCoordinator.applyRemoteEvent(event, to: link, in: context)
                continue
            }

            if event.privateMetadata["pipelineEventKind"] == "prep" {
                continue
            }

            if event.status.lowercased() == "cancelled", recordsByID[event.eventID] == nil {
                continue
            }

            let suggestion = GoogleCalendarMatchingService.bestMatch(
                for: event,
                among: applications,
                aliases: aliases
            )?.application
            let record = recordsByID[event.eventID] ?? GoogleCalendarImportRecord(
                remoteCalendarID: subscription.calendarID,
                remoteCalendarName: subscription.title,
                remoteEventID: event.eventID,
                startDate: event.startDate,
                endDate: event.endDate,
                suggestedApplication: suggestion
            )

            let previousETag = record.remoteETag

            if record.modelContext == nil {
                context.insert(record)
            }

            record.remoteCalendarID = subscription.calendarID
            record.remoteCalendarName = subscription.title
            record.remoteETag = event.etag
            record.remoteStatus = event.status
            record.htmlLink = event.htmlLink
            record.summary = event.summary
            record.location = event.location
            record.details = event.details
            record.organizerEmail = event.organizerEmail
            record.startDate = event.startDate
            record.endDate = event.endDate
            record.isAllDay = event.isAllDay
            record.lastSeenAt = Date()
            record.suggestedApplication = record.importedActivity?.application ?? suggestion

            if event.status.lowercased() == "cancelled" {
                record.state = .upstreamDeleted
            } else if record.importedActivity == nil {
                record.state = .pendingReview
            } else if previousETag != nil, previousETag != event.etag {
                record.state = .updatePending
            }

            record.updateTimestamp()
        }
    }

    private func composedActivityNotes(for record: GoogleCalendarImportRecord) -> String {
        var sections: [String] = []

        sections.append("Imported from Google Calendar")
        sections.append("Calendar: \(record.remoteCalendarName)")

        if let location = record.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            sections.append("Location: \(location)")
        }

        if let organizerEmail = record.organizerEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !organizerEmail.isEmpty {
            sections.append("Organizer: \(organizerEmail)")
        }

        if let htmlLink = record.htmlLink?.trimmingCharacters(in: .whitespacesAndNewlines), !htmlLink.isEmpty {
            sections.append("Join Link: \(htmlLink)")
        }

        if let details = record.details?.trimmingCharacters(in: .whitespacesAndNewlines), !details.isEmpty {
            sections.append("")
            sections.append(details)
        }

        return sections.joined(separator: "\n")
    }

    private func syncInterviewState(for application: JobApplication, context: ModelContext) {
        let latestInterviewStage = application.sortedActivities
            .filter { $0.kind == .interview }
            .compactMap(\.interviewStage)
            .sorted { $0.sortOrder > $1.sortOrder }
            .first

        application.interviewStage = latestInterviewStage

        if latestInterviewStage != nil && (application.status == .saved || application.status == .applied) {
            let previousStatus = application.status
            application.status = .interviewing
            ApplicationTimelineRecorderService.recordStatusChange(
                for: application,
                from: previousStatus,
                to: application.status,
                in: context
            )
        }
    }

    private func scheduledDurationMinutes(start: Date, end: Date) -> Int? {
        let minutes = Int(end.timeIntervalSince(start) / 60)
        guard minutes > 0 else { return nil }
        return min(max(minutes, 15), 8 * 60)
    }

    private func fetchAccount(in context: ModelContext) -> GoogleCalendarAccount? {
        let descriptor = FetchDescriptor<GoogleCalendarAccount>()
        return try? context.fetch(descriptor).first
    }

    private func fetchSubscriptions(in context: ModelContext) -> [GoogleCalendarSubscription] {
        let descriptor = FetchDescriptor<GoogleCalendarSubscription>(
            sortBy: [SortDescriptor(\.title)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchSelectedSubscriptions(in context: ModelContext) -> [GoogleCalendarSubscription] {
        fetchSubscriptions(in: context).filter { $0.isSelected || $0.isWriteTarget }
    }

    private func fetchImportRecords(for calendarID: String, in context: ModelContext) -> [GoogleCalendarImportRecord] {
        let descriptor = FetchDescriptor<GoogleCalendarImportRecord>()
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.remoteCalendarID == calendarID }
    }

    private func fetchApplications(in context: ModelContext) -> [JobApplication] {
        let descriptor = FetchDescriptor<JobApplication>()
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchCompanyAliases(in context: ModelContext) -> [CompanyAlias] {
        let descriptor = FetchDescriptor<CompanyAlias>()
        return (try? context.fetch(descriptor)) ?? []
    }

    private func dedupeCandidate(
        for application: JobApplication,
        event: GoogleCalendarEventPayload
    ) -> ApplicationActivity? {
        application.sortedInterviewActivities.first { activity in
            let delta = abs(activity.occurredAt.timeIntervalSince(event.startDate))
            return delta <= 2 * 60 * 60
        }
    }
}
