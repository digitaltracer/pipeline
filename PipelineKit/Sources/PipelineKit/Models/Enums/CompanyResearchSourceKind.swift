import Foundation

public enum CompanyResearchSourceKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case companyWebsite = "company_website"
    case jobPosting = "job_posting"
    case linkedIn = "linkedin"
    case glassdoor = "glassdoor"
    case levelsFYI = "levels_fyi"
    case teamBlind = "teamblind"
    case search = "search"
    case manual = "manual"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .companyWebsite:
            return "Company Website"
        case .jobPosting:
            return "Job Posting"
        case .linkedIn:
            return "LinkedIn"
        case .glassdoor:
            return "Glassdoor"
        case .levelsFYI:
            return "Levels.fyi"
        case .teamBlind:
            return "TeamBlind"
        case .search:
            return "Search"
        case .manual:
            return "Manual"
        }
    }
}

public enum CompanyResearchFetchStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case fetched = "fetched"
    case failed = "failed"
    case skipped = "skipped"

    public var id: String { rawValue }
}
