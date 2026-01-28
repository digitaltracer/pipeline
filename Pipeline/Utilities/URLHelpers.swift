import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum URLHelpers {
    /// Validate if a string is a valid URL
    static func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return url.scheme != nil && url.host != nil
    }

    /// Normalize a URL string (add https if missing)
    static func normalize(_ urlString: String) -> String {
        var normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Add https:// if no scheme present
        if !normalized.lowercased().hasPrefix("http://") &&
           !normalized.lowercased().hasPrefix("https://") {
            normalized = "https://\(normalized)"
        }

        return normalized
    }

    /// Extract domain from a URL string
    static func extractDomain(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return nil
        }

        // Remove www. prefix
        var domain = host
        if domain.hasPrefix("www.") {
            domain = String(domain.dropFirst(4))
        }

        return domain
    }

    /// Extract the company domain for logo fetching
    static func extractCompanyDomain(from urlString: String) -> String? {
        guard let domain = extractDomain(from: urlString) else {
            return nil
        }

        // For job boards, we can't determine the company from the URL
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
    static func displayURL(_ urlString: String, maxLength: Int = 50) -> String {
        var display = urlString

        // Remove protocol
        display = display.replacingOccurrences(of: "https://", with: "")
        display = display.replacingOccurrences(of: "http://", with: "")

        // Remove trailing slash
        if display.hasSuffix("/") {
            display = String(display.dropLast())
        }

        // Truncate if needed
        if display.count > maxLength {
            let prefixLength = (maxLength - 3) / 2
            let suffixLength = maxLength - 3 - prefixLength
            display = "\(display.prefix(prefixLength))...\(display.suffix(suffixLength))"
        }

        return display
    }

    /// Build a Google search URL for a company
    static func companySearchURL(companyName: String) -> URL? {
        let query = "\(companyName) company careers".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.google.com/search?q=\(query)")
    }

    /// Build a LinkedIn search URL for a company
    static func linkedInCompanyURL(companyName: String) -> URL? {
        let query = companyName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.linkedin.com/company/\(query)")
    }

    /// Open a URL in the default browser
    @MainActor
    static func openInBrowser(_ urlString: String) {
        guard let url = URL(string: normalize(urlString)) else { return }

        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}

// MARK: - URL Extensions

extension URL {
    var displayString: String {
        URLHelpers.displayURL(absoluteString)
    }

    var domain: String? {
        URLHelpers.extractDomain(from: absoluteString)
    }
}
