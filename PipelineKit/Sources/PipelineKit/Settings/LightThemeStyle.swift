import Foundation

public enum LightThemeStyle: String, CaseIterable, Identifiable, Sendable {
    case classic
    case arcticWhite
    case warmPaper
    case slate

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .arcticWhite: return "Arctic White"
        case .warmPaper: return "Warm Paper"
        case .slate: return "Slate"
        }
    }

    public var description: String {
        switch self {
        case .classic: return "Cool neutral gray (default)"
        case .arcticWhite: return "Crisp, near-pure white"
        case .warmPaper: return "Warm cream and sepia tones"
        case .slate: return "Cool steel with high contrast"
        }
    }

    public var palette: LightThemePalette {
        switch self {
        case .classic: return .classic
        case .arcticWhite: return .arcticWhite
        case .warmPaper: return .warmPaper
        case .slate: return .slate
        }
    }
}

public extension LightThemeStyle {
    static let userDefaultsKey = Constants.UserDefaultsKeys.lightThemeStyle

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _current: LightThemeStyle = {
        let stored = UserDefaults.standard.string(forKey: userDefaultsKey)
        return stored.flatMap(LightThemeStyle.init(rawValue:)) ?? .classic
    }()

    static var current: LightThemeStyle {
        lock.lock()
        defer { lock.unlock() }
        return _current
    }

    static func setCurrent(_ style: LightThemeStyle) {
        lock.lock()
        _current = style
        lock.unlock()
        SettingsSyncCoordinator.shared.setSyncable(style.rawValue, forKey: userDefaultsKey)
    }

    /// Reloads `_current` from `UserDefaults`. Called by the sync coordinator
    /// after applying a remote change so the cached palette reflects iCloud.
    static func reloadCurrentFromDefaults() {
        let stored = UserDefaults.standard.string(forKey: userDefaultsKey)
        let resolved = stored.flatMap(LightThemeStyle.init(rawValue:)) ?? .classic
        lock.lock()
        _current = resolved
        lock.unlock()
    }
}
