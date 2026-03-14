import Foundation
import SwiftData

@Model
public final class GoogleCalendarSubscription {
    public var id: UUID = UUID()
    public var calendarID: String = ""
    public var title: String = ""
    public var colorHex: String?
    public var isPrimary: Bool = false
    public var isSelected: Bool = false
    public var isWriteTarget: Bool = false
    public var syncToken: String?
    public var lastSyncedAt: Date?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        calendarID: String,
        title: String,
        colorHex: String? = nil,
        isPrimary: Bool = false,
        isSelected: Bool = false,
        isWriteTarget: Bool = false,
        syncToken: String? = nil,
        lastSyncedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.calendarID = calendarID
        self.title = title
        self.colorHex = colorHex
        self.isPrimary = isPrimary
        self.isSelected = isSelected
        self.isWriteTarget = isWriteTarget
        self.syncToken = syncToken
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }
}
