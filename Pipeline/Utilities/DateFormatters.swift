import Foundation

enum DateFormatters {
    // MARK: - Standard Formatters

    /// Full date format: "January 15, 2024"
    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    /// Medium date format: "Jan 15, 2024"
    static let mediumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// Short date format: "1/15/24"
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    /// Date with time: "Jan 15, 2024 at 2:30 PM"
    static let dateWithTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Custom Formatters

    /// Compact format for cards: "Jan 15"
    static let compact: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    /// ISO format: "2024-01-15"
    static let iso: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Relative Formatting

    /// Relative date formatter for "today", "yesterday", etc.
    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    /// Relative date formatter with abbreviated style
    static let relativeAbbreviated: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    // MARK: - Helper Functions

    /// Format a date as a relative string if recent, otherwise as medium date
    static func smartFormat(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current

        // If within the last week, use relative formatting
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
           date > weekAgo {
            return relative.localizedString(for: date, relativeTo: now)
        }

        // If this year, show month and day only
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return compact.string(from: date)
        }

        // Otherwise, show full date
        return mediumDate.string(from: date)
    }

    /// Format a follow-up date with urgency indication
    static func formatFollowUp(_ date: Date) -> (text: String, isOverdue: Bool, isToday: Bool) {
        let now = Date()
        let calendar = Calendar.current

        let isOverdue = date < now && !calendar.isDateInToday(date)
        let isToday = calendar.isDateInToday(date)

        let text: String
        if isToday {
            text = "Today"
        } else if calendar.isDateInTomorrow(date) {
            text = "Tomorrow"
        } else if isOverdue {
            let days = calendar.dateComponents([.day], from: date, to: now).day ?? 0
            text = "\(days) day\(days == 1 ? "" : "s") overdue"
        } else {
            text = compact.string(from: date)
        }

        return (text, isOverdue, isToday)
    }

    /// Calculate days since a date
    static func daysSince(_ date: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: date, to: Date())
        return components.day ?? 0
    }

    /// Calculate days until a date
    static func daysUntil(_ date: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: date)
        return components.day ?? 0
    }
}

// MARK: - Date Extensions

extension Date {
    var smartFormatted: String {
        DateFormatters.smartFormat(self)
    }

    var compactFormatted: String {
        DateFormatters.compact.string(from: self)
    }

    var mediumFormatted: String {
        DateFormatters.mediumDate.string(from: self)
    }

    var relativeFormatted: String {
        DateFormatters.relative.localizedString(for: self, relativeTo: Date())
    }

    var daysSinceNow: Int {
        DateFormatters.daysSince(self)
    }

    var daysUntilNow: Int {
        DateFormatters.daysUntil(self)
    }
}
