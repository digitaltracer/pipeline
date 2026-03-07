import Foundation
import SwiftData

public enum ApplicationTimelineMigrationService {
    @discardableResult
    public static func migrateLegacyInterviewLogs(in context: ModelContext) throws -> Int {
        let logs = try context.fetch(FetchDescriptor<InterviewLog>())
        guard !logs.isEmpty else { return 0 }

        let contacts = try context.fetch(FetchDescriptor<Contact>())
        let activities = try context.fetch(FetchDescriptor<ApplicationActivity>())

        var contactsByLookupKey: [String: Contact] = [:]
        for contact in contacts {
            guard let key = Contact.normalizedLookupKey(
                name: contact.fullName,
                companyName: contact.companyName
            ) else { continue }
            contactsByLookupKey[key] = contact
        }

        var activitiesByLegacyID: [UUID: ApplicationActivity] = [:]
        for activity in activities {
            guard let legacyInterviewLogID = activity.legacyInterviewLogID else { continue }
            activitiesByLegacyID[legacyInterviewLogID] = activity
        }

        var migratedCount = 0

        for log in logs {
            guard let application = log.application else { continue }

            if let existingActivity = activitiesByLegacyID[log.id] {
                if log.migratedActivityID == nil {
                    log.migratedActivityID = existingActivity.id
                }
                continue
            }

            let linkedContact = contactForMigration(
                from: log,
                application: application,
                contactsByLookupKey: &contactsByLookupKey,
                context: context
            )

            let activity = ApplicationActivity(
                id: log.migratedActivityID ?? UUID(),
                kind: .interview,
                occurredAt: log.date,
                notes: log.notes,
                rating: log.rating,
                application: application,
                contact: linkedContact,
                interviewStage: log.interviewType,
                legacyInterviewLogID: log.id
            )
            context.insert(activity)
            application.addActivity(activity)
            log.migratedActivityID = activity.id
            activitiesByLegacyID[log.id] = activity
            migratedCount += 1
        }

        if migratedCount > 0 {
            try context.save()
        }

        return migratedCount
    }

    private static func contactForMigration(
        from log: InterviewLog,
        application: JobApplication,
        contactsByLookupKey: inout [String: Contact],
        context: ModelContext
    ) -> Contact? {
        guard let rawName = log.interviewerName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawName.isEmpty,
              let lookupKey = Contact.normalizedLookupKey(
                name: rawName,
                companyName: application.companyName
              )
        else {
            return nil
        }

        let contact: Contact
        if let existing = contactsByLookupKey[lookupKey] {
            contact = existing
            contact.mergeCompanyNameIfMissing(application.companyName)
        } else {
            let created = Contact(
                fullName: rawName,
                companyName: application.companyName
            )
            context.insert(created)
            contactsByLookupKey[lookupKey] = created
            contact = created
        }

        ensureContactLink(
            contact: contact,
            application: application,
            context: context
        )

        return contact
    }

    private static func ensureContactLink(
        contact: Contact,
        application: JobApplication,
        context: ModelContext
    ) {
        if (application.contactLinks ?? []).contains(where: { $0.contact?.id == contact.id }) {
            return
        }

        let link = ApplicationContactLink(
            application: application,
            contact: contact,
            role: .interviewer
        )
        context.insert(link)
        application.addContactLink(link)
        contact.updateTimestamp()
    }
}
