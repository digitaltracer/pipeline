import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

public enum InterviewQuestionCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case behavioral
    case coding
    case systemDesign
    case domain
    case product
    case debugging
    case recruiter
    case hiringManager
    case other

    public var id: String { rawValue }

    public init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "behavioral", "behavioural":
            self = .behavioral
        case "coding", "code":
            self = .coding
        case "systemdesign", "system design":
            self = .systemDesign
        case "domain":
            self = .domain
        case "product":
            self = .product
        case "debugging", "debug":
            self = .debugging
        case "recruiter":
            self = .recruiter
        case "hiringmanager", "hiring manager":
            self = .hiringManager
        default:
            self = .other
        }
    }

    public var displayName: String {
        switch self {
        case .behavioral:
            return "Behavioral"
        case .coding:
            return "Coding"
        case .systemDesign:
            return "System Design"
        case .domain:
            return "Domain"
        case .product:
            return "Product"
        case .debugging:
            return "Debugging"
        case .recruiter:
            return "Recruiter"
        case .hiringManager:
            return "Hiring Manager"
        case .other:
            return "Other"
        }
    }

    #if canImport(SwiftUI)
    public var color: Color {
        switch self {
        case .behavioral:
            return .pink
        case .coding:
            return .blue
        case .systemDesign:
            return .orange
        case .domain:
            return .mint
        case .product:
            return .purple
        case .debugging:
            return .red
        case .recruiter:
            return .teal
        case .hiringManager:
            return .indigo
        case .other:
            return .secondary
        }
    }
    #endif
}
