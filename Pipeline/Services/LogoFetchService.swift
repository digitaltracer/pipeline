import Foundation

final class LogoFetchService {
    static let shared = LogoFetchService()

    private let clearbitBaseURL = "https://logo.clearbit.com/"
    private var cache: [String: String] = [:]

    private init() {}

    /// Generate a Clearbit logo URL for a domain
    func logoURL(for domain: String) -> String {
        return "\(clearbitBaseURL)\(domain)"
    }

    /// Generate a Clearbit logo URL from a company name
    func logoURL(forCompanyName name: String) -> String? {
        let domain = extractDomain(from: name)
        guard !domain.isEmpty else { return nil }
        return logoURL(for: domain)
    }

    /// Extract a likely domain from a company name
    func extractDomain(from companyName: String) -> String {
        // Clean up the company name
        var domain = companyName.lowercased()

        // Remove common suffixes
        let suffixes = [
            " inc", " inc.", " incorporated",
            " llc", " l.l.c.",
            " ltd", " ltd.", " limited",
            " corp", " corp.", " corporation",
            " co", " co.",
            " gmbh", " ag", " sa", " bv",
            " pvt", " pvt.", " private"
        ]

        for suffix in suffixes {
            if domain.hasSuffix(suffix) {
                domain = String(domain.dropLast(suffix.count))
            }
        }

        // Remove special characters and spaces
        domain = domain
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "&", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "-", with: "")

        // Add .com if it looks like a simple name
        if !domain.contains(".") {
            domain = "\(domain).com"
        }

        return domain
    }

    /// Check if a logo exists at the Clearbit URL
    func checkLogoExists(for domain: String) async -> Bool {
        // Check cache first
        if let cached = cache[domain] {
            return cached == "exists"
        }

        guard let url = URL(string: logoURL(for: domain)) else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let exists = httpResponse.statusCode == 200
                cache[domain] = exists ? "exists" : "notfound"
                return exists
            }
        } catch {
            cache[domain] = "notfound"
        }

        return false
    }

    /// Get a verified logo URL, checking if it exists
    func getVerifiedLogoURL(forCompanyName name: String) async -> String? {
        guard let domain = logoURL(forCompanyName: name) else {
            return nil
        }

        let domainOnly = extractDomain(from: name)
        let exists = await checkLogoExists(for: domainOnly)

        return exists ? domain : nil
    }

    /// Clear the cache
    func clearCache() {
        cache.removeAll()
    }
}
