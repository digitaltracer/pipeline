import Foundation
import SwiftData

@Model
public final class ApplicationActivity {
    public var id: UUID = UUID()
    private var kindRawValue: String = ApplicationActivityKind.note.rawValue
    private var interviewStageRawValue: String?
    public var scheduledDurationMinutes: Int?
    public var fromStatusRawValue: String?
    public var toStatusRawValue: String?
    public var fromFollowUpDate: Date?
    public var toFollowUpDate: Date?
    public var occurredAt: Date = Date()
    public var notes: String?
    public var rating: Int?
    public var emailSubject: String?
    public var emailBodySnapshot: String?
    public var legacyInterviewLogID: UUID?
    public var isSystemGenerated: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var application: JobApplication?
    public var contact: Contact?
    public var debrief: InterviewDebrief?
    public var rejectionLog: RejectionLog?

    public var kind: ApplicationActivityKind {
        get { ApplicationActivityKind(rawValue: kindRawValue) }
        set { kindRawValue = newValue.rawValue }
    }

    public var interviewStage: InterviewStage? {
        get {
            guard let interviewStageRawValue,
                  !interviewStageRawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return InterviewStage(rawValue: interviewStageRawValue)
        }
        set { interviewStageRawValue = newValue?.rawValue }
    }

    public var fromStatus: ApplicationStatus? {
        get {
            guard let fromStatusRawValue,
                  !fromStatusRawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return ApplicationStatus(rawValue: fromStatusRawValue)
        }
        set { fromStatusRawValue = newValue?.rawValue }
    }

    public var toStatus: ApplicationStatus? {
        get {
            guard let toStatusRawValue,
                  !toStatusRawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return ApplicationStatus(rawValue: toStatusRawValue)
        }
        set { toStatusRawValue = newValue?.rawValue }
    }

    public init(
        id: UUID = UUID(),
        kind: ApplicationActivityKind,
        occurredAt: Date = Date(),
        notes: String? = nil,
        rating: Int? = nil,
        emailSubject: String? = nil,
        emailBodySnapshot: String? = nil,
        application: JobApplication? = nil,
        contact: Contact? = nil,
        interviewStage: InterviewStage? = nil,
        scheduledDurationMinutes: Int? = nil,
        legacyInterviewLogID: UUID? = nil,
        fromStatus: ApplicationStatus? = nil,
        toStatus: ApplicationStatus? = nil,
        fromFollowUpDate: Date? = nil,
        toFollowUpDate: Date? = nil,
        isSystemGenerated: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.occurredAt = occurredAt
        self.notes = notes
        self.rating = rating
        self.emailSubject = emailSubject
        self.emailBodySnapshot = emailBodySnapshot
        self.application = application
        self.contact = contact
        self.interviewStageRawValue = interviewStage?.rawValue
        self.scheduledDurationMinutes = Self.normalizedScheduledDuration(scheduledDurationMinutes)
        self.legacyInterviewLogID = legacyInterviewLogID
        self.fromStatusRawValue = fromStatus?.rawValue
        self.toStatusRawValue = toStatus?.rawValue
        self.fromFollowUpDate = fromFollowUpDate
        self.toFollowUpDate = toFollowUpDate
        self.isSystemGenerated = isSystemGenerated
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var title: String {
        switch kind {
        case .interview:
            return interviewStage?.displayName ?? kind.displayName
        case .email:
            if let emailSubject,
               !emailSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return emailSubject
            }
            return kind.displayName
        case .statusChange:
            if let toStatus {
                return "Status changed to \(toStatus.displayName)"
            }
            return "Status updated"
        case .followUp:
            if toFollowUpDate != nil {
                return fromFollowUpDate == nil ? "Follow-up scheduled" : "Follow-up rescheduled"
            }
            if fromFollowUpDate != nil {
                return "Follow-up cleared"
            }
            return "Follow-up updated"
        case .call, .text, .note:
            return kind.displayName
        }
    }

    public var summary: String? {
        switch kind {
        case .email:
            return emailBodySnapshot
        case .statusChange:
            if let fromStatus, let toStatus {
                return "\(fromStatus.displayName) -> \(toStatus.displayName)"
            }
            return toStatus?.displayName
        case .followUp:
            switch (fromFollowUpDate, toFollowUpDate) {
            case let (nil, toDate?):
                return "Set for \(toDate.formatted(date: .abbreviated, time: .omitted))"
            case let (fromDate?, toDate?):
                return "\(fromDate.formatted(date: .abbreviated, time: .omitted)) -> \(toDate.formatted(date: .abbreviated, time: .omitted))"
            case let (fromDate?, nil):
                return "Previously \(fromDate.formatted(date: .abbreviated, time: .omitted))"
            case (nil, nil):
                return nil
            }
        default:
            return notes
        }
    }

    public var scheduledEndAt: Date {
        guard let scheduledDurationMinutes = Self.normalizedScheduledDuration(scheduledDurationMinutes) else {
            return occurredAt
        }
        return Calendar.current.date(
            byAdding: .minute,
            value: scheduledDurationMinutes,
            to: occurredAt
        ) ?? occurredAt
    }

    public var isScheduledInterview: Bool {
        kind == .interview && occurredAt > Date()
    }

    public var hasDebrief: Bool {
        debrief != nil
    }

    public var isRejectionStatusChange: Bool {
        kind == .statusChange && toStatus == .rejected
    }

    public var hasRejectionLog: Bool {
        rejectionLog != nil
    }

    public var needsRejectionLog: Bool {
        isRejectionStatusChange && rejectionLog == nil
    }

    public var needsDebrief: Bool {
        kind == .interview && !isScheduledInterview && debrief == nil
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }

    private static func normalizedScheduledDuration(_ value: Int?) -> Int? {
        guard let value else { return nil }
        let clamped = min(max(value, 15), 8 * 60)
        return clamped
    }
}
