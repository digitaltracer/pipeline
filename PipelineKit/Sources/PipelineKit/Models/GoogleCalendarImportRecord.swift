import Foundation
import SwiftData

@Model
public final class GoogleCalendarImportRecord {
    public var id: UUID = UUID()
    public var remoteCalendarID: String = ""
    public var remoteCalendarName: String = ""
    public var remoteEventID: String = ""
    public var remoteETag: String?
    public var remoteStatus: String = "confirmed"
    public var htmlLink: String?
    public var summary: String?
    public var location: String?
    public var details: String?
    public var organizerEmail: String?
    public var startDate: Date = Date()
    public var endDate: Date = Date()
    public var isAllDay: Bool = false
    public var lastSeenAt: Date = Date()
    private var stateRawValue: String = GoogleCalendarImportState.pendingReview.rawValue
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var suggestedApplication: JobApplication?
    public var importedActivity: ApplicationActivity?

    public var state: GoogleCalendarImportState {
        get { GoogleCalendarImportState(rawValue: stateRawValue) ?? .pendingReview }
        set { stateRawValue = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        remoteCalendarID: String,
        remoteCalendarName: String,
        remoteEventID: String,
        remoteETag: String? = nil,
        remoteStatus: String = "confirmed",
        htmlLink: String? = nil,
        summary: String? = nil,
        location: String? = nil,
        details: String? = nil,
        organizerEmail: String? = nil,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        lastSeenAt: Date = Date(),
        state: GoogleCalendarImportState = .pendingReview,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        suggestedApplication: JobApplication? = nil,
        importedActivity: ApplicationActivity? = nil
    ) {
        self.id = id
        self.remoteCalendarID = remoteCalendarID
        self.remoteCalendarName = remoteCalendarName
        self.remoteEventID = remoteEventID
        self.remoteETag = remoteETag
        self.remoteStatus = remoteStatus
        self.htmlLink = htmlLink
        self.summary = summary
        self.location = location
        self.details = details
        self.organizerEmail = organizerEmail
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.lastSeenAt = lastSeenAt
        self.stateRawValue = state.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.suggestedApplication = suggestedApplication
        self.importedActivity = importedActivity
    }

    public var displayTitle: String {
        let trimmed = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return "Untitled Calendar Event"
    }

    public var needsReview: Bool {
        state.needsReview
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }
}
