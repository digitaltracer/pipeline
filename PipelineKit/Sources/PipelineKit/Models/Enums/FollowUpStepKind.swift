import Foundation

public enum FollowUpStepKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case ackCheck
    case followUp1
    case followUp2
    case followUp3
    case archiveSuggestion
    case postInterviewThankYou
    case legacyManual

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ackCheck:
            return "Check for acknowledgment"
        case .followUp1:
            return "First follow-up"
        case .followUp2:
            return "Second follow-up"
        case .followUp3:
            return "Final follow-up"
        case .archiveSuggestion:
            return "Archive suggestion"
        case .postInterviewThankYou:
            return "Post-interview thank you"
        case .legacyManual:
            return "Manual follow-up"
        }
    }

    public var rationaleText: String {
        switch self {
        case .ackCheck:
            return "Check whether the company already sent an automated acknowledgment before following up."
        case .followUp1:
            return "Send a polite follow-up while the application is still fresh."
        case .followUp2:
            return "Try a second follow-up with a new angle or added context."
        case .followUp3:
            return "Send one final follow-up before moving on."
        case .archiveSuggestion:
            return "If there is still no traction, Pipeline can suggest archiving this application."
        case .postInterviewThankYou:
            return "Send a thank-you note soon after the interview while the conversation is fresh."
        case .legacyManual:
            return "This is a manual follow-up carried forward from the previous single-date reminder flow."
        }
    }

    public var supportsDraftGeneration: Bool {
        switch self {
        case .followUp1, .followUp2, .followUp3, .postInterviewThankYou, .legacyManual:
            return true
        case .ackCheck, .archiveSuggestion:
            return false
        }
    }
}
