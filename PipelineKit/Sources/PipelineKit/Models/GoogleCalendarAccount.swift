import Foundation
import SwiftData

@Model
public final class GoogleCalendarAccount {
    public var id: UUID = UUID()
    public var googleUserID: String = ""
    public var email: String = ""
    public var displayName: String?
    public var avatarURLString: String?
    public var isConnected: Bool = false
    public var lastSyncedAt: Date?
    public var lastCalendarListRefreshAt: Date?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        googleUserID: String,
        email: String,
        displayName: String? = nil,
        avatarURLString: String? = nil,
        isConnected: Bool = true,
        lastSyncedAt: Date? = nil,
        lastCalendarListRefreshAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.googleUserID = googleUserID
        self.email = email
        self.displayName = displayName
        self.avatarURLString = avatarURLString
        self.isConnected = isConnected
        self.lastSyncedAt = lastSyncedAt
        self.lastCalendarListRefreshAt = lastCalendarListRefreshAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }
}
