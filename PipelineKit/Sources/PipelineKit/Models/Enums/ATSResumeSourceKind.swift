import Foundation

public enum ATSResumeSourceKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case tailoredSnapshot = "tailored_snapshot"
    case masterResume = "master_resume"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tailoredSnapshot:
            return "Latest Tailored Resume"
        case .masterResume:
            return "Master Resume"
        }
    }
}
