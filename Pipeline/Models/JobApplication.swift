import Foundation
import SwiftData

@Model
final class JobApplication {
    var id: UUID = UUID()
    var companyName: String = ""
    var role: String = ""
    var location: String = ""
    var jobURL: String?
    var jobDescription: String?

    private(set) var statusRawValue: String = ApplicationStatus.saved.rawValue
    private(set) var priorityRawValue: String = Priority.medium.rawValue
    private var sourceRawValue: String = Source.jobPortal.rawValue
    private var platformRawValue: String = Platform.other.rawValue
    private var interviewStageRawValue: String?
    private var currencyRawValue: String = Currency.usd.rawValue

    var salaryMin: Int?
    var salaryMax: Int?
    var appliedDate: Date?
    var nextFollowUpDate: Date?

    @Relationship(deleteRule: .cascade, inverse: \InterviewLog.application)
    var interviewLogs: [InterviewLog]?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: - Computed Properties for Enums

    var status: ApplicationStatus {
        get { ApplicationStatus(rawValue: statusRawValue) }
        set { statusRawValue = newValue.rawValue }
    }

    var priority: Priority {
        get { Priority(rawValue: priorityRawValue) ?? .medium }
        set { priorityRawValue = newValue.rawValue }
    }

    var source: Source {
        get { Source(rawValue: sourceRawValue) }
        set { sourceRawValue = newValue.rawValue }
    }

    var platform: Platform {
        get { Platform(rawValue: platformRawValue) ?? .other }
        set { platformRawValue = newValue.rawValue }
    }

    var interviewStage: InterviewStage? {
        get {
            guard let rawValue = interviewStageRawValue,
                  !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return InterviewStage(rawValue: rawValue)
        }
        set { interviewStageRawValue = newValue?.rawValue }
    }

    var currency: Currency {
        get { Currency(rawValue: currencyRawValue) ?? .usd }
        set { currencyRawValue = newValue.rawValue }
    }

    // MARK: - Computed Properties

    var salaryRange: String? {
        currency.formatRange(min: salaryMin, max: salaryMax)
    }

    var sortedInterviewLogs: [InterviewLog] {
        (interviewLogs ?? []).sorted { $0.date > $1.date }
    }

    var companyDomain: String? {
        // Best-effort domain derived from company name (used for optional features like favicons).
        let cleaned = companyName.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "inc", with: "")
            .replacingOccurrences(of: "ltd", with: "")
            .replacingOccurrences(of: "llc", with: "")

        return "\(cleaned).com"
    }

    func googleS2FaviconURL(size: Int = 64) -> URL? {
        let domainFromJobURL = jobURL.flatMap { URLHelpers.extractCompanyDomain(from: $0) }
        let domain = domainFromJobURL ?? companyDomain
        guard let domain else { return nil }
        return URLHelpers.googleFaviconURL(domain: domain, size: size)
    }

    var companyInitial: String {
        String(companyName.prefix(1)).uppercased()
    }

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        companyName: String,
        role: String,
        location: String,
        jobURL: String? = nil,
        jobDescription: String? = nil,
        status: ApplicationStatus = .saved,
        priority: Priority = .medium,
        source: Source = .jobPortal,
        platform: Platform = .other,
        interviewStage: InterviewStage? = nil,
        currency: Currency = .usd,
        salaryMin: Int? = nil,
        salaryMax: Int? = nil,
        appliedDate: Date? = nil,
        nextFollowUpDate: Date? = nil,
        interviewLogs: [InterviewLog]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.companyName = companyName
        self.role = role
        self.location = location
        self.jobURL = jobURL
        self.jobDescription = jobDescription
        self.statusRawValue = status.rawValue
        self.priorityRawValue = priority.rawValue
        self.sourceRawValue = source.rawValue
        self.platformRawValue = platform.rawValue
        self.interviewStageRawValue = interviewStage?.rawValue
        self.currencyRawValue = currency.rawValue
        self.salaryMin = salaryMin
        self.salaryMax = salaryMax
        self.appliedDate = appliedDate
        self.nextFollowUpDate = nextFollowUpDate
        self.interviewLogs = interviewLogs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Methods

    func updateTimestamp() {
        updatedAt = Date()
    }

    func addInterviewLog(_ log: InterviewLog) {
        if interviewLogs == nil {
            interviewLogs = []
        }
        interviewLogs?.append(log)
        updateTimestamp()
    }
}

// MARK: - Sample Data

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
