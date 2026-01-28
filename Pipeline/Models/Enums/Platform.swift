import Foundation
import SwiftUI

enum Platform: String, Codable, CaseIterable, Identifiable {
    case linkedin = "LinkedIn"
    case naukri = "Naukri"
    case instahyre = "Instahyre"
    case indeed = "Indeed"
    case glassdoor = "Glassdoor"
    case other = "Other"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .linkedin: return "link"
        case .naukri: return "n.circle.fill"
        case .instahyre: return "i.circle.fill"
        case .indeed: return "magnifyingglass.circle.fill"
        case .glassdoor: return "door.left.hand.open"
        case .other: return "globe"
        }
    }

    var color: Color {
        switch self {
        case .linkedin: return Color(red: 0.0, green: 0.47, blue: 0.71) // LinkedIn blue
        case .naukri: return Color(red: 0.29, green: 0.56, blue: 0.89) // Naukri blue
        case .instahyre: return Color(red: 0.0, green: 0.73, blue: 0.83) // Instahyre teal
        case .indeed: return Color(red: 0.16, green: 0.35, blue: 0.67) // Indeed blue
        case .glassdoor: return Color(red: 0.0, green: 0.69, blue: 0.31) // Glassdoor green
        case .other: return .gray
        }
    }

    /// Detect platform from URL
    static func detect(from urlString: String?) -> Platform {
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
