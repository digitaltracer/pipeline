import Foundation

public enum PipelineDeepLinkService {
    public static let scheme = "pipeline"

    public static func applicationURL(applicationID: UUID) -> URL {
        URL(string: "\(scheme)://application/\(applicationID.uuidString)")!
    }

    public static func interviewPrepURL(applicationID: UUID, activityID: UUID?) -> URL {
        var value = "\(scheme)://interview-prep/\(applicationID.uuidString)"
        if let activityID {
            value += "/\(activityID.uuidString)"
        }
        return URL(string: value)!
    }

    public static func openRequest(from url: URL) -> NotificationOpenRequest? {
        guard url.scheme?.lowercased() == scheme else { return nil }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        switch url.host?.lowercased() {
        case "application":
            guard let applicationID = pathComponents.first.flatMap(UUID.init(uuidString:)) else { return nil }
            return NotificationOpenRequest(
                kind: .interviewPrepBrief,
                applicationID: applicationID
            )
        case "interview-prep":
            guard let applicationID = pathComponents.first.flatMap(UUID.init(uuidString:)) else { return nil }
            let activityID = pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:))
            return NotificationOpenRequest(
                kind: .interviewPrepBrief,
                applicationID: applicationID,
                interviewActivityID: activityID
            )
        default:
            return nil
        }
    }
}
