import Foundation

final class PlatformDetectionService {
    static let shared = PlatformDetectionService()

    private init() {}

    /// Platform detection patterns
    private let patterns: [(pattern: String, platform: Platform)] = [
        ("linkedin.com", .linkedin),
        ("naukri.com", .naukri),
        ("instahyre.com", .instahyre),
        ("indeed.com", .indeed),
        ("glassdoor.com", .glassdoor)
    ]

    /// Detect platform from a URL string
    func detectPlatform(from urlString: String?) -> Platform {
        guard let urlString = urlString?.lowercased() else {
            return .other
        }

        for (pattern, platform) in patterns {
            if urlString.contains(pattern) {
                return platform
            }
        }

        return .other
    }

    /// Detect platform from a URL
    func detectPlatform(from url: URL?) -> Platform {
        return detectPlatform(from: url?.absoluteString)
    }

    /// Extract the job ID from common job posting URLs
    func extractJobID(from urlString: String?) -> String? {
        guard let urlString = urlString else { return nil }

        // LinkedIn job ID pattern
        if urlString.contains("linkedin.com") {
            if let range = urlString.range(of: #"\/(\d+)\/?($|\?)"#, options: .regularExpression) {
                let match = urlString[range]
                let digits = match.filter { $0.isNumber }
                return digits.isEmpty ? nil : String(digits)
            }
        }

        // Indeed job ID pattern (usually "jk=<id>")
        if urlString.contains("indeed.com") {
            if let range = urlString.range(of: #"jk=([a-zA-Z0-9]+)"#, options: .regularExpression) {
                return String(urlString[range].dropFirst(3))
            }
        }

        // Glassdoor job ID pattern
        if urlString.contains("glassdoor.com") {
            if let range = urlString.range(of: #"jobListingId=(\d+)"#, options: .regularExpression) {
                let match = urlString[range]
                return String(match.dropFirst("jobListingId=".count))
            }
        }

        return nil
    }

    /// Validate if a URL looks like a job posting
    func isJobPostingURL(_ urlString: String?) -> Bool {
        guard let urlString = urlString?.lowercased() else { return false }

        let jobIndicators = [
            "jobs", "job", "careers", "career",
            "positions", "position", "vacancy",
            "opening", "apply", "hiring"
        ]

        return jobIndicators.contains { urlString.contains($0) }
    }
}
