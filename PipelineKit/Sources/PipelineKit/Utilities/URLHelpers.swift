import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public enum URLHelpers {
    /// Validate if a string is a valid URL
    public static func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return url.scheme != nil && url.host != nil
    }

    /// Validate a web URL (http/https only)
    public static func isValidWebURL(_ string: String) -> Bool {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              let host = url.host,
              !host.isEmpty else {
            return false
        }

        return scheme == "http" || scheme == "https"
    }

    /// Normalize a URL string (add https if missing)
    public static func normalize(_ urlString: String) -> String {
        var normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        if !normalized.lowercased().hasPrefix("http://") &&
           !normalized.lowercased().hasPrefix("https://") {
            normalized = "https://\(normalized)"
        }

        return normalized
    }

    /// Extract domain from a URL string
    public static func extractDomain(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return nil
        }

        var domain = host
        if domain.hasPrefix("www.") {
            domain = String(domain.dropFirst(4))
        }

        return domain
    }

    /// Extract the company domain for logo fetching
    public static func extractCompanyDomain(from urlString: String) -> String? {
        guard let domain = extractDomain(from: urlString) else {
            return nil
        }

        let jobBoards = [
            "linkedin.com", "indeed.com", "glassdoor.com",
            "naukri.com", "instahyre.com", "monster.com",
            "ziprecruiter.com", "dice.com", "careerbuilder.com"
        ]

        for board in jobBoards {
            if domain.contains(board) {
                return nil
            }
        }

        return domain
    }

    /// Clean and truncate a URL for display
    public static func displayURL(_ urlString: String, maxLength: Int = 50) -> String {
        var display = urlString

        display = display.replacingOccurrences(of: "https://", with: "")
        display = display.replacingOccurrences(of: "http://", with: "")

        if display.hasSuffix("/") {
            display = String(display.dropLast())
        }

        if display.count > maxLength {
            let prefixLength = (maxLength - 3) / 2
            let suffixLength = maxLength - 3 - prefixLength
            display = "\(display.prefix(prefixLength))...\(display.suffix(suffixLength))"
        }

        return display
    }

    /// Build a Google search URL for a company
    public static func companySearchURL(companyName: String) -> URL? {
        let query = "\(companyName) company careers".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.google.com/search?q=\(query)")
    }

    /// Build a LinkedIn search URL for a company
    public static func linkedInCompanyURL(companyName: String) -> URL? {
        let query = companyName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.linkedin.com/company/\(query)")
    }

    /// Build a Google S2 favicon URL for a domain.
    public static func googleFaviconURL(domain: String, size: Int = 64) -> URL? {
        var normalizedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedDomain.lowercased().hasPrefix("http://") || normalizedDomain.lowercased().hasPrefix("https://") {
            normalizedDomain = extractDomain(from: normalizedDomain) ?? normalizedDomain
        }

        if normalizedDomain.hasPrefix("www.") {
            normalizedDomain = String(normalizedDomain.dropFirst(4))
        }

        guard !normalizedDomain.isEmpty else { return nil }

        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [
            URLQueryItem(name: "domain", value: normalizedDomain),
            URLQueryItem(name: "sz", value: "\(max(16, min(size, 256)))")
        ]

        return components?.url
    }

    /// Open a URL in the default browser
    #if canImport(AppKit) || canImport(UIKit)
    @MainActor
    public static func openInBrowser(_ urlString: String) {
        guard let url = URL(string: normalize(urlString)) else { return }

        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #elseif canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
    #endif
}

// MARK: - URL Extensions

extension URL {
    public var displayString: String {
        URLHelpers.displayURL(absoluteString)
    }

    public var domain: String? {
        URLHelpers.extractDomain(from: absoluteString)
    }
}
