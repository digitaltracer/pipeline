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
    case verified = "verified"
    case partial = "partial"
    case blocked = "blocked"
    case invalid = "invalid"
    case manual = "manual"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fetched:
            return "Fetched"
        case .failed:
            return "Failed"
        case .skipped:
            return "Skipped"
        case .verified:
            return "Verified"
        case .partial:
            return "Partial"
        case .blocked:
            return "Blocked"
        case .invalid:
            return "Invalid"
        case .manual:
            return "Manual"
        }
    }
}

public enum ResearchAcquisitionMethod: String, Codable, CaseIterable, Sendable, Identifiable {
    case providerSearch = "provider_search"
    case urlSession = "url_session"
    case wkWebView = "wkwebview"
    case manual = "manual"
    case none = "none"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .providerSearch:
            return "Provider Search"
        case .urlSession:
            return "Direct Fetch"
        case .wkWebView:
            return "Browser Fallback"
        case .manual:
            return "Manual"
        case .none:
            return "None"
        }
    }
}

public enum ResearchValidationStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case verified = "verified"
    case partial = "partial"
    case blocked = "blocked"
    case invalid = "invalid"
    case skipped = "skipped"
    case manual = "manual"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .verified:
            return "Verified"
        case .partial:
            return "Partial"
        case .blocked:
            return "Blocked"
        case .invalid:
            return "Invalid"
        case .skipped:
            return "Skipped"
        case .manual:
            return "Manual"
        }
    }
}

public enum ResearchConfidence: String, Codable, CaseIterable, Sendable, Identifiable {
    case high = "high"
    case medium = "medium"
    case low = "low"

    public var id: String { rawValue }

    public var title: String { rawValue.capitalized }
}

public enum ResearchRunStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case succeeded = "succeeded"
    case partial = "partial"
    case failed = "failed"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .succeeded:
            return "Verified"
        case .partial:
            return "Partial"
        case .failed:
            return "Failed"
        }
    }
}
