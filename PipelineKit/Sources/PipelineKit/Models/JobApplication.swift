import Foundation
import SwiftData

@Model
public final class JobApplication {
    public var id: UUID = UUID()
    public var companyName: String = ""
    public var role: String = ""
    public var location: String = ""
    public var jobURL: String?
    public var jobDescription: String?

    public private(set) var statusRawValue: String = ApplicationStatus.saved.rawValue
    public private(set) var priorityRawValue: String = Priority.medium.rawValue
    private var sourceRawValue: String = Source.jobPortal.rawValue
    private var platformRawValue: String = Platform.other.rawValue
    private var interviewStageRawValue: String?
    private var currencyRawValue: String = Currency.usd.rawValue

    public private(set) var salaryMin: Int?
    public private(set) var salaryMax: Int?
    public var appliedDate: Date?
    public var nextFollowUpDate: Date?

    @Relationship(deleteRule: .cascade, inverse: \InterviewLog.application)
    public var interviewLogs: [InterviewLog]?

    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    // MARK: - Computed Properties for Enums

    public var status: ApplicationStatus {
        get { ApplicationStatus(rawValue: statusRawValue) }
        set { statusRawValue = newValue.rawValue }
    }

    public var priority: Priority {
        get { Priority(rawValue: priorityRawValue) ?? .medium }
        set { priorityRawValue = newValue.rawValue }
    }

    public var source: Source {
        get { Source(rawValue: sourceRawValue) }
        set { sourceRawValue = newValue.rawValue }
    }

    public var platform: Platform {
        get { Platform(rawValue: platformRawValue) ?? .other }
        set { platformRawValue = newValue.rawValue }
    }

    public var interviewStage: InterviewStage? {
        get {
            guard let rawValue = interviewStageRawValue,
                  !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return InterviewStage(rawValue: rawValue)
        }
        set { interviewStageRawValue = newValue?.rawValue }
    }

    public var currency: Currency {
        get { Currency(rawValue: currencyRawValue) ?? .usd }
        set { currencyRawValue = newValue.rawValue }
    }

    // MARK: - Computed Properties

    public var salaryRange: String? {
        currency.formatRange(min: salaryMin, max: salaryMax)
    }

    public var sortedInterviewLogs: [InterviewLog] {
        (interviewLogs ?? []).sorted { $0.date > $1.date }
    }

    public var companyDomain: String? {
        let cleaned = companyName.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "inc", with: "")
            .replacingOccurrences(of: "ltd", with: "")
            .replacingOccurrences(of: "llc", with: "")

        return "\(cleaned).com"
    }

    public func googleS2FaviconURL(size: Int = 64) -> URL? {
        let domainFromJobURL = jobURL.flatMap { URLHelpers.extractCompanyDomain(from: $0) }
        let domain = domainFromJobURL ?? companyDomain
        guard let domain else { return nil }
        return URLHelpers.googleFaviconURL(domain: domain, size: size)
    }

    public var companyInitial: String {
        String(companyName.prefix(1)).uppercased()
    }

    // MARK: - Initializer

    public init(
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
        setSalaryRange(min: salaryMin, max: salaryMax)
        self.appliedDate = appliedDate
        self.nextFollowUpDate = nextFollowUpDate
        self.interviewLogs = interviewLogs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Methods

    public func updateTimestamp() {
        updatedAt = Date()
    }

    public func addInterviewLog(_ log: InterviewLog) {
        if interviewLogs == nil {
            interviewLogs = []
        }
        interviewLogs?.append(log)
        updateTimestamp()
    }

    public func setSalaryRange(min: Int?, max: Int?) {
        guard let min, let max else {
            salaryMin = min
            salaryMax = max
            return
        }

        if min <= max {
            salaryMin = min
            salaryMax = max
        } else {
            salaryMin = max
            salaryMax = min
        }
    }
}
