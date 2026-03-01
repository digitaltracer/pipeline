// JobApplication is now provided by PipelineKit.
// Sample data kept here for previews.
import Foundation
import SwiftData
import PipelineKit

extension JobApplication {
    static var sampleData: [JobApplication] {
        [
            JobApplication(
                companyName: "Apple",
                role: "Senior iOS Developer",
                location: "Cupertino, CA",
                jobURL: "https://jobs.apple.com/12345",
                status: .interviewing,
                priority: .high,
                source: .companyWebsite,
                platform: .other,
                interviewStage: .technicalRound1,
                currency: .usd,
                salaryMin: 180000,
                salaryMax: 250000,
                appliedDate: Calendar.current.date(byAdding: .day, value: -14, to: Date()),
                nextFollowUpDate: Calendar.current.date(byAdding: .day, value: 2, to: Date())
            ),
            JobApplication(
                companyName: "Google",
                role: "Staff Software Engineer",
                location: "Mountain View, CA",
                jobURL: "https://careers.google.com/jobs/12345",
                status: .applied,
                priority: .high,
                source: .referral,
                platform: .linkedin,
                currency: .usd,
                salaryMin: 200000,
                salaryMax: 300000,
                appliedDate: Calendar.current.date(byAdding: .day, value: -7, to: Date())
            ),
            JobApplication(
                companyName: "Stripe",
                role: "Backend Engineer",
                location: "San Francisco, CA",
                status: .saved,
                priority: .medium,
                source: .jobPortal,
                platform: .linkedin,
                currency: .usd,
                salaryMin: 150000,
                salaryMax: 200000
            ),
            JobApplication(
                companyName: "Infosys",
                role: "Technical Lead",
                location: "Bangalore, India",
                status: .rejected,
                priority: .low,
                source: .hr,
                platform: .naukri,
                currency: .inr,
                salaryMin: 3000000,
                salaryMax: 4000000,
                appliedDate: Calendar.current.date(byAdding: .day, value: -30, to: Date())
            ),
            JobApplication(
                companyName: "Microsoft",
                role: "Principal Engineer",
                location: "Redmond, WA",
                status: .offered,
                priority: .high,
                source: .agent,
                platform: .linkedin,
                interviewStage: .offerExtended,
                currency: .usd,
                salaryMin: 220000,
                salaryMax: 280000,
                appliedDate: Calendar.current.date(byAdding: .day, value: -45, to: Date())
            )
        ]
    }
}
