import Foundation

public enum DarkThemeStyle: String, CaseIterable, Identifiable, Sendable {
    case coolBlue
    case warmNeutral
    case deepOcean
    case trueDark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .coolBlue: return "Cool Blue"
        case .warmNeutral: return "Warm Neutral"
        case .deepOcean: return "Deep Ocean"
        case .trueDark: return "True Dark"
        }
    }

    public var description: String {
        switch self {
        case .coolBlue: return "Blue-tinted dark (default)"
        case .warmNeutral: return "Warm charcoal grays"
        case .deepOcean: return "Deep saturated blue-black"
        case .trueDark: return "Near-black OLED"
        }
    }

    public var palette: DarkThemePalette {
        switch self {
        case .coolBlue: return .coolBlue
        case .warmNeutral: return .warmNeutral
        case .deepOcean: return .deepOcean
        case .trueDark: return .trueDark
        }
    }
}

public extension DarkThemeStyle {
    static let userDefaultsKey = "darkThemeStyle"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _current: DarkThemeStyle = {
        let stored = UserDefaults.standard.string(forKey: userDefaultsKey)
        return stored.flatMap(DarkThemeStyle.init(rawValue:)) ?? .coolBlue
    }()

    static var current: DarkThemeStyle {
        lock.lock()
        defer { lock.unlock() }
        return _current
    }

    static func setCurrent(_ style: DarkThemeStyle) {
        lock.lock()
        _current = style
        lock.unlock()
        UserDefaults.standard.set(style.rawValue, forKey: userDefaultsKey)
    }
}
