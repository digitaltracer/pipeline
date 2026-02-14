import Foundation

public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .system: return "desktopcomputer"
        }
    }
}
