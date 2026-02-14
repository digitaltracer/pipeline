import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

public enum Platform: String, Codable, CaseIterable, Identifiable, Sendable {
    case linkedin = "LinkedIn"
    case naukri = "Naukri"
    case instahyre = "Instahyre"
    case indeed = "Indeed"
    case glassdoor = "Glassdoor"
    case other = "Other"

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    public var icon: String {
        switch self {
        case .linkedin: return "link"
        case .naukri: return "n.circle.fill"
        case .instahyre: return "i.circle.fill"
        case .indeed: return "magnifyingglass.circle.fill"
        case .glassdoor: return "door.left.hand.open"
        case .other: return "globe"
        }
    }

    #if canImport(SwiftUI)
    public var color: Color {
        switch self {
        case .linkedin: return Color(red: 0.0, green: 0.47, blue: 0.71)
        case .naukri: return Color(red: 0.29, green: 0.56, blue: 0.89)
        case .instahyre: return Color(red: 0.0, green: 0.73, blue: 0.83)
        case .indeed: return Color(red: 0.16, green: 0.35, blue: 0.67)
        case .glassdoor: return Color(red: 0.0, green: 0.69, blue: 0.31)
        case .other: return .gray
        }
    }
    #endif

    /// Detect platform from URL
    public static func detect(from urlString: String?) -> Platform {
        guard let urlString = urlString?.lowercased() else { return .other }

        if urlString.contains("linkedin.com") {
            return .linkedin
        } else if urlString.contains("naukri.com") {
            return .naukri
        } else if urlString.contains("instahyre.com") {
            return .instahyre
        } else if urlString.contains("indeed.com") {
            return .indeed
        } else if urlString.contains("glassdoor.com") {
            return .glassdoor
        }

        return .other
    }
}
