import Foundation
import SwiftData

@Model
final class InterviewLog {
    var id: UUID = UUID()
    private var interviewTypeRawValue: String = InterviewStage.phoneScreen.rawValue
    var date: Date = Date()
    var interviewerName: String?
    var rating: Int = 3
    var notes: String?

    var application: JobApplication?

    // MARK: - Computed Properties

    var interviewType: InterviewStage {
        get { InterviewStage(rawValue: interviewTypeRawValue) ?? .phoneScreen }
        set { interviewTypeRawValue = newValue.rawValue }
    }

    // MARK: - Initializer

    init(
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
        self.rating = min(max(rating, 1), 5) // Clamp between 1 and 5
        self.notes = notes
        self.application = application
    }

    // MARK: - Validation

    var isValid: Bool {
        rating >= 1 && rating <= 5
    }
}

// MARK: - Sample Data

extension InterviewLog {
    static var sampleData: [InterviewLog] {
        [
            InterviewLog(
                interviewType: .phoneScreen,
                date: Calendar.current.date(byAdding: .day, value: -10, to: Date())!,
                interviewerName: "John Smith",
                rating: 4,
                notes: "Great initial call. Discussed team structure and role expectations."
            ),
            InterviewLog(
                interviewType: .technicalRound1,
                date: Calendar.current.date(byAdding: .day, value: -5, to: Date())!,
                interviewerName: "Sarah Chen",
                rating: 3,
                notes: "Coding interview went well. Had some difficulty with the graph problem but worked through it."
            ),
            InterviewLog(
                interviewType: .systemDesign,
                date: Calendar.current.date(byAdding: .day, value: -2, to: Date())!,
                interviewerName: "Mike Johnson",
                rating: 5,
                notes: "Designed a scalable notification system. Interviewer was impressed with the trade-off analysis."
            )
        ]
    }
}
