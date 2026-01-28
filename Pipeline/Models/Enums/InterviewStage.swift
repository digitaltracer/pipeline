import Foundation
import SwiftUI

enum InterviewStage: String, Codable, CaseIterable, Identifiable {
    case phoneScreen = "Phone Screen"
    case technicalRound1 = "Technical Round 1"
    case technicalRound2 = "Technical Round 2"
    case designChallenge = "Design Challenge"
    case systemDesign = "System Design"
    case hrRound = "HR Round"
    case finalRound = "Final Round"
    case offerExtended = "Offer Extended"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var shortName: String {
        switch self {
        case .phoneScreen: return "Phone"
        case .technicalRound1: return "Tech 1"
        case .technicalRound2: return "Tech 2"
        case .designChallenge: return "Design"
        case .systemDesign: return "System"
        case .hrRound: return "HR"
        case .finalRound: return "Final"
        case .offerExtended: return "Offer"
        }
    }

    var icon: String {
        switch self {
        case .phoneScreen: return "phone.fill"
        case .technicalRound1, .technicalRound2: return "laptopcomputer"
        case .designChallenge: return "paintbrush.fill"
        case .systemDesign: return "square.3.layers.3d"
        case .hrRound: return "person.fill"
        case .finalRound: return "star.fill"
        case .offerExtended: return "checkmark.seal.fill"
        }
    }

    var color: Color {
        switch self {
        case .phoneScreen: return .blue
        case .technicalRound1: return .orange
        case .technicalRound2: return .orange
        case .designChallenge: return .purple
        case .systemDesign: return .cyan
        case .hrRound: return .pink
        case .finalRound: return .yellow
        case .offerExtended: return .green
        }
    }

    var sortOrder: Int {
        switch self {
        case .phoneScreen: return 0
        case .technicalRound1: return 1
        case .technicalRound2: return 2
        case .designChallenge: return 3
        case .systemDesign: return 4
        case .hrRound: return 5
        case .finalRound: return 6
        case .offerExtended: return 7
        }
    }

    static var orderedCases: [InterviewStage] {
        allCases.sorted { $0.sortOrder < $1.sortOrder }
    }
}
