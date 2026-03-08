import Foundation
import SwiftData

@Model
public final class ApplicationChecklistSuggestion {
    public var id: UUID = UUID()
    public var title: String = ""
    public var rationale: String?
    private var statusRawValue: String = ApplicationChecklistSuggestionStatus.pending.rawValue
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var application: JobApplication?

    public init(
        id: UUID = UUID(),
        title: String,
        rationale: String? = nil,
        status: ApplicationChecklistSuggestionStatus = .pending,
        application: JobApplication? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.rationale = Self.normalizedText(rationale)
        self.statusRawValue = status.rawValue
        self.application = application
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var status: ApplicationChecklistSuggestionStatus {
        get { ApplicationChecklistSuggestionStatus(rawValue: statusRawValue) ?? .pending }
        set {
            guard statusRawValue != newValue.rawValue else { return }
            statusRawValue = newValue.rawValue
            updateTimestamp()
        }
    }

    public var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var displayTitle: String {
        let trimmedTitle = trimmedTitle
        return trimmedTitle.isEmpty ? "Untitled Suggestion" : trimmedTitle
    }

    public var normalizedRationale: String? {
        Self.normalizedText(rationale)
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
