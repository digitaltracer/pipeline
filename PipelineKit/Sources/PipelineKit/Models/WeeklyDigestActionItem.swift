import Foundation
import SwiftData

@Model
public final class WeeklyDigestActionItem {
    public var id: UUID = UUID()
    private var kindRawValue: String = WeeklyDigestActionKind.summary.rawValue
    public var sortOrder: Int = 0
    public var title: String = ""
    public var subtitle: String?
    public var dueDate: Date?
    public var applicationID: UUID?
    public var isOverdue: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var snapshot: WeeklyDigestSnapshot?

    public var kind: WeeklyDigestActionKind {
        get { WeeklyDigestActionKind(rawValue: kindRawValue) ?? .summary }
        set {
            guard kindRawValue != newValue.rawValue else { return }
            kindRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }

    public init(
        id: UUID = UUID(),
        kind: WeeklyDigestActionKind,
        sortOrder: Int,
        title: String,
        subtitle: String? = nil,
        dueDate: Date? = nil,
        applicationID: UUID? = nil,
        isOverdue: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.sortOrder = sortOrder
        self.title = title
        self.subtitle = subtitle
        self.dueDate = dueDate
        self.applicationID = applicationID
        self.isOverdue = isOverdue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
