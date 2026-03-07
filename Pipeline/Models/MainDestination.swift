import Foundation
import PipelineKit

enum MainDestination: Hashable {
    case dashboard
    case applications(SidebarFilter)
    case contacts
    case resume
    case costCenter

    var applicationFilter: SidebarFilter? {
        if case .applications(let filter) = self {
            return filter
        }
        return nil
    }

    var title: String {
        switch self {
        case .dashboard:
            return "Dashboard"
        case .applications(let filter):
            return filter.displayName
        case .contacts:
            return "Contacts"
        case .resume:
            return "Resume"
        case .costCenter:
            return "Cost Center"
        }
    }
}
