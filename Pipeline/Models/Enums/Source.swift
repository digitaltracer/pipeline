import Foundation
import SwiftUI

enum Source: String, Codable, CaseIterable, Identifiable {
    case agent = "Agent"
    case hr = "HR"
    case jobPortal = "Job Portal"
    case companyWebsite = "Company Website"
    case referral = "Referral"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .agent: return "person.badge.shield.checkmark"
        case .hr: return "person.crop.rectangle"
        case .jobPortal: return "globe"
        case .companyWebsite: return "building.2"
        case .referral: return "person.2"
        }
    }

    var color: Color {
        switch self {
        case .agent: return .purple
        case .hr: return .blue
        case .jobPortal: return .cyan
        case .companyWebsite: return .orange
        case .referral: return .green
        }
    }
}
