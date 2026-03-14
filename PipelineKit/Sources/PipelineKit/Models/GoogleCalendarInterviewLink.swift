import Foundation
import SwiftData

@Model
public final class GoogleCalendarInterviewLink {
    public var id: UUID = UUID()
    public var activityID: UUID = UUID()
    public var applicationID: UUID = UUID()
    public var remoteCalendarID: String = ""
    public var remoteCalendarName: String = ""
    public var prepCalendarID: String?
    public var prepCalendarName: String?
    public var interviewEventID: String = ""
    public var interviewEventETag: String?
    public var prepEventID: String?
    public var prepEventETag: String?
    private var ownershipRawValue: String = GoogleCalendarInterviewLinkOwnership.pipelineCreated.rawValue
    private var syncStatusRawValue: String = GoogleCalendarInterviewLinkSyncStatus.active.rawValue
    public var lastSyncedAt: Date?
    public var lastRemoteModifiedAt: Date?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var ownership: GoogleCalendarInterviewLinkOwnership {
        get { GoogleCalendarInterviewLinkOwnership(rawValue: ownershipRawValue) ?? .pipelineCreated }
        set { ownershipRawValue = newValue.rawValue }
    }

    public var syncStatus: GoogleCalendarInterviewLinkSyncStatus {
        get { GoogleCalendarInterviewLinkSyncStatus(rawValue: syncStatusRawValue) ?? .active }
        set { syncStatusRawValue = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        activityID: UUID,
        applicationID: UUID,
        remoteCalendarID: String,
        remoteCalendarName: String,
        prepCalendarID: String? = nil,
        prepCalendarName: String? = nil,
        interviewEventID: String,
        interviewEventETag: String? = nil,
        prepEventID: String? = nil,
        prepEventETag: String? = nil,
        ownership: GoogleCalendarInterviewLinkOwnership,
        syncStatus: GoogleCalendarInterviewLinkSyncStatus = .active,
        lastSyncedAt: Date? = nil,
        lastRemoteModifiedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.activityID = activityID
        self.applicationID = applicationID
        self.remoteCalendarID = remoteCalendarID
        self.remoteCalendarName = remoteCalendarName
        self.prepCalendarID = prepCalendarID
        self.prepCalendarName = prepCalendarName
        self.interviewEventID = interviewEventID
        self.interviewEventETag = interviewEventETag
        self.prepEventID = prepEventID
        self.prepEventETag = prepEventETag
        self.ownershipRawValue = ownership.rawValue
        self.syncStatusRawValue = syncStatus.rawValue
        self.lastSyncedAt = lastSyncedAt
        self.lastRemoteModifiedAt = lastRemoteModifiedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var hasPrepEvent: Bool {
        guard let prepEventID else { return false }
        return !prepEventID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }
}
