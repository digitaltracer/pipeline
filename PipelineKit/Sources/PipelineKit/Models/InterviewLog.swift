import Foundation
import SwiftData

@Model
public final class InterviewLog {
    public var id: UUID = UUID()
    private var interviewTypeRawValue: String = InterviewStage.phoneScreen.rawValue
    public var date: Date = Date()
    public var interviewerName: String?
    public var rating: Int = 3
    public var notes: String?

    public var application: JobApplication?

    // MARK: - Computed Properties

    public var interviewType: InterviewStage {
        get { InterviewStage(rawValue: interviewTypeRawValue) }
        set { interviewTypeRawValue = newValue.rawValue }
    }

    // MARK: - Initializer

    public init(
        id: UUID = UUID(),
        interviewType: InterviewStage,
        date: Date = Date(),
        interviewerName: String? = nil,
        rating: Int = 3,
        notes: String? = nil,
        application: JobApplication? = nil
    ) {
        self.id = id
        self.interviewTypeRawValue = interviewType.rawValue
        self.date = date
        self.interviewerName = interviewerName
        self.rating = min(max(rating, 1), 5)
        self.notes = notes
        self.application = application
    }

    // MARK: - Validation

    public var isValid: Bool {
        rating >= 1 && rating <= 5
    }
}
