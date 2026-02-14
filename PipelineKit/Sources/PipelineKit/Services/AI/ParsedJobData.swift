import Foundation

public struct ParsedJobData: Sendable {
    public var companyName: String
    public var role: String
    public var location: String
    public var jobDescription: String
    public var salaryMin: Int?
    public var salaryMax: Int?
    public var currency: Currency

    public init(
        companyName: String = "",
        role: String = "",
        location: String = "",
        jobDescription: String = "",
        salaryMin: Int? = nil,
        salaryMax: Int? = nil,
        currency: Currency = .usd
    ) {
        self.companyName = companyName
        self.role = role
        self.location = location
        self.jobDescription = jobDescription
        self.salaryMin = salaryMin
        self.salaryMax = salaryMax
        self.currency = currency
    }

    public var hasMeaningfulContent: Bool {
        !companyName.isEmpty ||
            !role.isEmpty ||
            !location.isEmpty ||
            !jobDescription.isEmpty ||
            salaryMin != nil ||
            salaryMax != nil
    }
}
