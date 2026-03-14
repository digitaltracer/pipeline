import Foundation
import SwiftData

@MainActor
public final class GoogleCalendarInterviewSyncCoordinator {
    public static let shared = GoogleCalendarInterviewSyncCoordinator()

    private enum MetadataKey {
        static let managedBy = "pipelineManagedBy"
        static let applicationID = "pipelineApplicationID"
        static let activityID = "pipelineActivityID"
        static let eventKind = "pipelineEventKind"
    }

    private let calendarService: GoogleCalendarService
    private let accessTokenProvider: @Sendable () async throws -> String

    public init(
        calendarService: GoogleCalendarService = .shared,
        accessTokenProvider: (@Sendable () async throws -> String)? = nil
    ) {
        self.calendarService = calendarService
        self.accessTokenProvider = accessTokenProvider ?? {
            try await GoogleOAuthService.shared.accessToken()
        }
    }

    public func syncActivity(
        _ activity: ApplicationActivity,
        for application: JobApplication,
        in context: ModelContext
    ) async {
        guard activity.kind == .interview else { return }

        let existingLink = fetchLink(activityID: activity.id, in: context)

        guard let account = fetchAccount(in: context), account.isConnected else {
            mark(existingLink, as: .orphaned, in: context)
            return
        }

        guard activity.occurredAt > Date() else {
            await retireLink(existingLink, deleteRemoteInterview: existingLink?.ownership == .pipelineCreated, in: context)
            return
        }

        guard let writeTarget = fetchWriteTarget(in: context) else {
            mark(existingLink, as: .orphaned, in: context)
            return
        }

        let accessToken: String
        do {
            accessToken = try await accessTokenProvider()
        } catch {
            mark(existingLink, as: .permissionError, in: context)
            return
        }

        do {
            let link = existingLink ?? GoogleCalendarInterviewLink(
                activityID: activity.id,
                applicationID: application.id,
                remoteCalendarID: writeTarget.calendarID,
                remoteCalendarName: writeTarget.title,
                prepCalendarID: writeTarget.calendarID,
                prepCalendarName: writeTarget.title,
                interviewEventID: "",
                ownership: .pipelineCreated
            )

            if link.modelContext == nil {
                context.insert(link)
            }

            if link.interviewEventID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let createdInterview = try await calendarService.createEvent(
                    calendarID: writeTarget.calendarID,
                    calendarName: writeTarget.title,
                    accessToken: accessToken,
                    draft: interviewDraft(for: activity, application: application)
                )
                link.remoteCalendarID = writeTarget.calendarID
                link.remoteCalendarName = writeTarget.title
                link.interviewEventID = createdInterview.eventID
                link.interviewEventETag = createdInterview.etag
                link.lastRemoteModifiedAt = Date()
            } else {
                let updatedInterview = try await calendarService.updateEvent(
                    calendarID: link.remoteCalendarID,
                    calendarName: link.remoteCalendarName,
                    eventID: link.interviewEventID,
                    accessToken: accessToken,
                    draft: interviewDraft(for: activity, application: application)
                )
                link.interviewEventETag = updatedInterview.etag
                link.lastRemoteModifiedAt = Date()
            }

            let prepTargetCalendarID = link.prepCalendarID ?? writeTarget.calendarID
            let prepTargetCalendarName = link.prepCalendarName ?? writeTarget.title
            if let prepEventID = link.prepEventID,
               !prepEventID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let updatedPrep = try await calendarService.updateEvent(
                    calendarID: prepTargetCalendarID,
                    calendarName: prepTargetCalendarName,
                    eventID: prepEventID,
                    accessToken: accessToken,
                    draft: prepDraft(for: activity, application: application)
                )
                link.prepEventETag = updatedPrep.etag
            } else {
                let createdPrep = try await calendarService.createEvent(
                    calendarID: writeTarget.calendarID,
                    calendarName: writeTarget.title,
                    accessToken: accessToken,
                    draft: prepDraft(for: activity, application: application)
                )
                link.prepCalendarID = writeTarget.calendarID
                link.prepCalendarName = writeTarget.title
                link.prepEventID = createdPrep.eventID
                link.prepEventETag = createdPrep.etag
            }

            link.syncStatus = .active
            link.lastSyncedAt = Date()
            link.updateTimestamp()
            try context.save()
        } catch {
            mark(existingLink, as: .permissionError, in: context)
        }
    }

    public func syncImportedInterview(
        _ activity: ApplicationActivity,
        application: JobApplication,
        remoteEvent: GoogleCalendarEventPayload,
        in context: ModelContext
    ) async throws {
        let link = fetchLink(activityID: activity.id, in: context) ?? GoogleCalendarInterviewLink(
            activityID: activity.id,
            applicationID: application.id,
            remoteCalendarID: remoteEvent.calendarID,
            remoteCalendarName: remoteEvent.calendarName,
            interviewEventID: remoteEvent.eventID,
            interviewEventETag: remoteEvent.etag,
            ownership: .importedExternal,
            syncStatus: .active,
            lastSyncedAt: Date(),
            lastRemoteModifiedAt: Date()
        )

        if link.modelContext == nil {
            context.insert(link)
        }

        link.remoteCalendarID = remoteEvent.calendarID
        link.remoteCalendarName = remoteEvent.calendarName
        link.interviewEventID = remoteEvent.eventID
        link.interviewEventETag = remoteEvent.etag
        link.lastRemoteModifiedAt = Date()
        link.syncStatus = .active
        link.updateTimestamp()

        try context.save()

        await syncPrepEventOnly(for: activity, application: application, link: link, in: context)
    }

    public func deleteActivity(
        _ activity: ApplicationActivity,
        application: JobApplication,
        in context: ModelContext
    ) async {
        guard let link = fetchLink(activityID: activity.id, in: context) else { return }
        await retireLink(link, deleteRemoteInterview: link.ownership == .pipelineCreated, in: context)
        context.delete(link)
        try? context.save()
    }

    public func applyRemoteEvent(
        _ event: GoogleCalendarEventPayload,
        to link: GoogleCalendarInterviewLink,
        in context: ModelContext
    ) async {
        if event.eventID == link.prepEventID {
            if event.status.lowercased() == "cancelled" {
                link.prepEventID = nil
                link.prepEventETag = nil
            } else {
                link.prepEventETag = event.etag
            }
            link.lastSyncedAt = Date()
            link.updateTimestamp()
            try? context.save()
            return
        }

        guard let activity = fetchActivity(id: link.activityID, in: context),
              let application = fetchApplication(id: link.applicationID, in: context) else {
            link.syncStatus = .orphaned
            link.updateTimestamp()
            try? context.save()
            return
        }

        if event.status.lowercased() == "cancelled" {
            link.syncStatus = .deletedUpstream
            link.lastRemoteModifiedAt = Date()
            link.lastSyncedAt = Date()
            link.updateTimestamp()
            try? context.save()
            await NotificationService.shared.syncReminderState(for: application)
            return
        }

        activity.occurredAt = event.startDate
        activity.scheduledDurationMinutes = scheduledDurationMinutes(start: event.startDate, end: event.endDate)
        if let inferredStage = GoogleCalendarMatchingService.inferInterviewStage(for: event) {
            activity.interviewStage = inferredStage
        }
        activity.notes = mergedNotes(existing: activity.notes, event: event, ownership: link.ownership)
        activity.updateTimestamp()

        link.interviewEventETag = event.etag
        link.lastRemoteModifiedAt = Date()
        link.lastSyncedAt = Date()
        link.syncStatus = .active
        link.updateTimestamp()

        try? context.save()
        await NotificationService.shared.syncReminderState(for: application)
    }

    public func fetchLink(activityID: UUID, in context: ModelContext) -> GoogleCalendarInterviewLink? {
        let descriptor = FetchDescriptor<GoogleCalendarInterviewLink>()
        return (try? context.fetch(descriptor))?.first(where: { $0.activityID == activityID })
    }

    public func fetchLinks(in context: ModelContext) -> [GoogleCalendarInterviewLink] {
        let descriptor = FetchDescriptor<GoogleCalendarInterviewLink>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    public func fetchLink(forRemoteEventID eventID: String, in context: ModelContext) -> GoogleCalendarInterviewLink? {
        let descriptor = FetchDescriptor<GoogleCalendarInterviewLink>()
        return (try? context.fetch(descriptor))?.first {
            $0.interviewEventID == eventID || $0.prepEventID == eventID
        }
    }

    private func syncPrepEventOnly(
        for activity: ApplicationActivity,
        application: JobApplication,
        link: GoogleCalendarInterviewLink,
        in context: ModelContext
    ) async {
        guard activity.occurredAt > Date(),
              let writeTarget = fetchWriteTarget(in: context) else {
            return
        }

        let accessToken: String
        do {
            accessToken = try await accessTokenProvider()
        } catch {
            mark(link, as: .permissionError, in: context)
            return
        }

        do {
            let createdPrep = try await calendarService.createEvent(
                calendarID: writeTarget.calendarID,
                calendarName: writeTarget.title,
                accessToken: accessToken,
                draft: prepDraft(for: activity, application: application)
            )
            link.prepCalendarID = writeTarget.calendarID
            link.prepCalendarName = writeTarget.title
            link.prepEventID = createdPrep.eventID
            link.prepEventETag = createdPrep.etag
            link.lastSyncedAt = Date()
            link.updateTimestamp()
            try context.save()
        } catch {
            mark(link, as: .permissionError, in: context)
        }
    }

    private func retireLink(
        _ link: GoogleCalendarInterviewLink?,
        deleteRemoteInterview: Bool,
        in context: ModelContext
    ) async {
        guard let link else { return }

        let accessToken = try? await accessTokenProvider()

        if let prepEventID = link.prepEventID,
           let prepCalendarID = link.prepCalendarID ?? link.remoteCalendarID as String?,
           let accessToken {
            try? await calendarService.deleteEvent(
                calendarID: prepCalendarID,
                eventID: prepEventID,
                accessToken: accessToken
            )
            link.prepEventID = nil
            link.prepEventETag = nil
        }

        if deleteRemoteInterview,
           let accessToken,
           !link.interviewEventID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? await calendarService.deleteEvent(
                calendarID: link.remoteCalendarID,
                eventID: link.interviewEventID,
                accessToken: accessToken
            )
            link.interviewEventID = ""
            link.interviewEventETag = nil
        }

        link.syncStatus = .orphaned
        link.lastSyncedAt = Date()
        link.updateTimestamp()
        try? context.save()
    }

    private func mark(
        _ link: GoogleCalendarInterviewLink?,
        as status: GoogleCalendarInterviewLinkSyncStatus,
        in context: ModelContext
    ) {
        guard let link else { return }
        link.syncStatus = status
        link.lastSyncedAt = Date()
        link.updateTimestamp()
        try? context.save()
    }

    private func interviewDraft(
        for activity: ApplicationActivity,
        application: JobApplication
    ) -> GoogleCalendarEventDraft {
        let stageTitle = activity.interviewStage?.displayName ?? "Interview"
        let title = "Interview — \(application.companyName) — \(stageTitle)"
        return GoogleCalendarEventDraft(
            summary: title,
            details: eventDescription(for: activity, application: application, includePrepLink: true),
            startDate: activity.occurredAt,
            endDate: activity.scheduledEndAt,
            privateMetadata: [
                MetadataKey.managedBy: "Pipeline",
                MetadataKey.applicationID: application.id.uuidString,
                MetadataKey.activityID: activity.id.uuidString,
                MetadataKey.eventKind: "interview"
            ]
        )
    }

    private func prepDraft(
        for activity: ApplicationActivity,
        application: JobApplication
    ) -> GoogleCalendarEventDraft {
        let stageTitle = activity.interviewStage?.displayName ?? "Interview"
        let prepStart = Calendar.current.date(byAdding: .minute, value: -30, to: activity.occurredAt) ?? activity.occurredAt
        return GoogleCalendarEventDraft(
            summary: "Review Prep — \(application.companyName) — \(stageTitle)",
            details: eventDescription(for: activity, application: application, includePrepLink: true),
            startDate: prepStart,
            endDate: activity.occurredAt,
            privateMetadata: [
                MetadataKey.managedBy: "Pipeline",
                MetadataKey.applicationID: application.id.uuidString,
                MetadataKey.activityID: activity.id.uuidString,
                MetadataKey.eventKind: "prep"
            ]
        )
    }

    private func eventDescription(
        for activity: ApplicationActivity,
        application: JobApplication,
        includePrepLink: Bool
    ) -> String {
        var sections: [String] = []

        sections.append("Tracked in Pipeline")
        sections.append("Application: \(PipelineDeepLinkService.applicationURL(applicationID: application.id).absoluteString)")
        if includePrepLink {
            sections.append(
                "Interview Prep: \(PipelineDeepLinkService.interviewPrepURL(applicationID: application.id, activityID: activity.id).absoluteString)"
            )
        }

        if let notes = activity.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !notes.isEmpty {
            sections.append("")
            sections.append("Notes")
            sections.append(String(notes.prefix(1_200)))
        }

        let interviewerNames = application.sortedContactLinks
            .filter { $0.role == .interviewer }
            .compactMap(\.contact?.fullName)
        if !interviewerNames.isEmpty {
            sections.append("")
            sections.append("Interviewers: \(interviewerNames.joined(separator: ", "))")
        }

        return sections.joined(separator: "\n")
    }

    private func mergedNotes(
        existing: String?,
        event: GoogleCalendarEventPayload,
        ownership: GoogleCalendarInterviewLinkOwnership
    ) -> String? {
        let base = (existing ?? "")
            .components(separatedBy: "\n\nGoogle Calendar Sync\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var calendarSections: [String] = []
        if let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            calendarSections.append("Location: \(location)")
        }
        if let organizerEmail = event.organizerEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !organizerEmail.isEmpty {
            calendarSections.append("Organizer: \(organizerEmail)")
        }
        if let details = event.details?.trimmingCharacters(in: .whitespacesAndNewlines), !details.isEmpty {
            calendarSections.append(details)
        }

        guard !calendarSections.isEmpty else {
            return base.isEmpty ? nil : base
        }

        let auditLabel = ownership == .pipelineCreated ? "Created by Pipeline" : "Imported from Google"
        let calendarBlock = (["Google Calendar Sync", auditLabel] + calendarSections).joined(separator: "\n")

        if base.isEmpty {
            return calendarBlock
        }

        return "\(base)\n\n\(calendarBlock)"
    }

    private func fetchAccount(in context: ModelContext) -> GoogleCalendarAccount? {
        let descriptor = FetchDescriptor<GoogleCalendarAccount>()
        return try? context.fetch(descriptor).first
    }

    private func fetchWriteTarget(in context: ModelContext) -> GoogleCalendarSubscription? {
        let descriptor = FetchDescriptor<GoogleCalendarSubscription>()
        return (try? context.fetch(descriptor))?.first(where: \.isWriteTarget)
    }

    private func fetchActivity(id: UUID, in context: ModelContext) -> ApplicationActivity? {
        let descriptor = FetchDescriptor<ApplicationActivity>()
        return (try? context.fetch(descriptor))?.first(where: { $0.id == id })
    }

    private func fetchApplication(id: UUID, in context: ModelContext) -> JobApplication? {
        let descriptor = FetchDescriptor<JobApplication>()
        return (try? context.fetch(descriptor))?.first(where: { $0.id == id })
    }

    private func scheduledDurationMinutes(start: Date, end: Date) -> Int? {
        let minutes = Int(end.timeIntervalSince(start) / 60)
        guard minutes > 0 else { return nil }
        return min(max(minutes, 15), 8 * 60)
    }
}
