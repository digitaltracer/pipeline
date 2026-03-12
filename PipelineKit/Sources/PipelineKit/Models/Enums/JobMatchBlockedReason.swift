import Foundation

public enum JobMatchBlockedReason: String, Codable, CaseIterable, Sendable, Identifiable {
    case missingJobDescription = "missing_job_description"
    case missingMasterResume = "missing_master_resume"
    case missingPreferences = "missing_preferences"

    public var id: String { rawValue }

    public var message: String {
        switch self {
        case .missingJobDescription:
            return "Add a job description to generate a match score."
        case .missingMasterResume:
            return "Save a master resume before generating a match score."
        case .missingPreferences:
            return "Add salary or location preferences in Settings before generating a match score."
        }
    }
}
