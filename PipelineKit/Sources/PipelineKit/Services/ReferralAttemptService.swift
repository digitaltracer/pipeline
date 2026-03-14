import Foundation
import SwiftData

@MainActor
public enum ReferralAttemptService {
    @discardableResult
    public static func createAttempt(
        for application: JobApplication,
        importedConnection: ImportedNetworkConnection?,
        contact: Contact?,
        subject: String?,
        body: String?,
        status: ReferralAttemptStatus,
        askedAt: Date? = nil,
        followUpNeededAt: Date? = nil,
        notes: String? = nil,
        sentEmailActivity: ApplicationActivity? = nil,
        in context: ModelContext
    ) throws -> ReferralAttempt {
        let attempt = ReferralAttempt(
            status: status,
            subject: subject,
            body: body,
            askedAt: askedAt,
            followUpNeededAt: followUpNeededAt,
            notes: notes,
            application: application,
            importedConnection: importedConnection,
            contact: contact,
            sentEmailActivity: sentEmailActivity
        )
        context.insert(attempt)
        application.addReferralAttempt(attempt)
        importedConnection?.updateTimestamp()
        contact?.updateTimestamp()
        try context.save()
        return attempt
    }

    public static func updateStatus(
        _ status: ReferralAttemptStatus,
        for attempt: ReferralAttempt,
        followUpNeededAt: Date? = nil,
        notes: String? = nil,
        in context: ModelContext
    ) throws {
        attempt.status = status
        attempt.followUpNeededAt = followUpNeededAt
        if let notes = CompanyProfile.normalizedText(notes) {
            attempt.notes = notes
        }
        attempt.updateTimestamp()
        attempt.application?.updateTimestamp()
        try context.save()
    }
}
