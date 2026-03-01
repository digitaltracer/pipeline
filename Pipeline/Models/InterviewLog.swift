// InterviewLog is now provided by PipelineKit.
// Sample data kept here for previews.
import Foundation
import SwiftData
import PipelineKit

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
