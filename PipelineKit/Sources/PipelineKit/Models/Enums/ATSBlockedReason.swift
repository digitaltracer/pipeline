import Foundation

public enum ATSBlockedReason: String, Codable, CaseIterable, Sendable, Identifiable {
    case missingJobDescription = "missing_job_description"
    case missingResumeSource = "missing_resume_source"

    public var id: String { rawValue }

    public var message: String {
        switch self {
        case .missingJobDescription:
            return "ATS analysis needs a job description."
        case .missingResumeSource:
            return "ATS analysis needs a saved master resume or tailored snapshot."
        }
    }
}
