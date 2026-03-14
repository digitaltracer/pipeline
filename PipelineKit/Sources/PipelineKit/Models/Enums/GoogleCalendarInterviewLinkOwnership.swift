import Foundation

public enum GoogleCalendarInterviewLinkOwnership: String, Codable, CaseIterable, Sendable {
    case importedExternal
    case pipelineCreated

    public var displayName: String {
        switch self {
        case .importedExternal:
            return "Imported from Google"
        case .pipelineCreated:
            return "Created by Pipeline"
        }
    }
}
