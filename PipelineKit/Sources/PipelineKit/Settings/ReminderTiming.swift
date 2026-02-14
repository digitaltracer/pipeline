import Foundation

public enum ReminderTiming: String, CaseIterable, Identifiable, Sendable {
    case dayBefore = "Day Before"
    case morningOf = "Morning Of (9 AM)"
    case both = "Both"

    public var id: String { rawValue }
}
