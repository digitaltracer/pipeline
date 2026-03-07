import Foundation
import SwiftData

@Model
public final class ApplicationTask {
    public var id: UUID = UUID()
    public var title: String = ""
    public var notes: String?
    public var dueDate: Date?
    public var isCompleted: Bool = false
    public var completedAt: Date?
    public private(set) var priorityRawValue: String = Priority.medium.rawValue
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var application: JobApplication?

    public var priority: Priority {
        get { Priority(rawValue: priorityRawValue) ?? .medium }
        set {
            guard priorityRawValue != newValue.rawValue else { return }
            priorityRawValue = newValue.rawValue
            updateTimestamp()
        }
    }

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        priority: Priority = .medium,
        application: JobApplication? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.priorityRawValue = priority.rawValue
        self.application = application
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var displayTitle: String {
        let trimmedTitle = trimmedTitle
        return trimmedTitle.isEmpty ? "Untitled Task" : trimmedTitle
    }

    public var normalizedNotes: String? {
        guard let notes else { return nil }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedNotes.isEmpty ? nil : trimmedNotes
    }

    public func setCompleted(_ value: Bool) {
        guard isCompleted != value else { return }
        isCompleted = value
        completedAt = value ? Date() : nil
        updateTimestamp()
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }
}
