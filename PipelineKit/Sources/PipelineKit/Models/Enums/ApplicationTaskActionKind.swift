import Foundation

public enum ApplicationTaskActionKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case none
    case resumeTailoring
    case coverLetter
    case companyResearch
    case manageContacts
    case interviewPrep
    case followUpDrafter
    case salaryComparison

    public var id: String { rawValue }
}
