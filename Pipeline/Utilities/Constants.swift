import Foundation
import SwiftUI
import PipelineKit
#if os(macOS)
import AppKit
#endif

// MARK: - Color Extensions

extension Color {
    static let pipelineBlue = Color(red: 0.2, green: 0.4, blue: 0.9)
    static let pipelineGreen = Color(red: 0.2, green: 0.8, blue: 0.4)
    static let pipelineOrange = Color(red: 1.0, green: 0.6, blue: 0.2)
    static let pipelineRed = Color(red: 0.9, green: 0.3, blue: 0.3)
}

// MARK: - Design System

enum DesignSystem {
    enum Radius {
        static let card: CGFloat = 16
        static let cardSmall: CGFloat = 12
        static let input: CGFloat = 12
        static let pill: CGFloat = 999
    }

    enum Spacing {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
    }

    enum Colors {
        static let accent = Color.pipelineBlue

        static func windowGradient(_ scheme: ColorScheme) -> LinearGradient {
            if scheme == .dark {
                return LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.07, blue: 0.09),
                        Color(red: 0.05, green: 0.06, blue: 0.07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            return LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.97, blue: 0.99),
                    Color(red: 0.94, green: 0.95, blue: 0.97)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        static func sidebarBackground(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0.06, green: 0.07, blue: 0.09)
                : Color(red: 0.98, green: 0.98, blue: 0.99)
        }

        static func contentBackground(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0.05, green: 0.06, blue: 0.07)
                : Color(red: 0.95, green: 0.96, blue: 0.98)
        }

        static func surface(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0.10, green: 0.12, blue: 0.15)
                : .white
        }

        static func surfaceElevated(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0.12, green: 0.14, blue: 0.18)
                : Color(red: 0.99, green: 0.99, blue: 1.0)
        }

        static func inputBackground(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0.10, green: 0.12, blue: 0.15).opacity(0.8)
                : Color(red: 0.95, green: 0.96, blue: 0.98)
        }

        static func stroke(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color.white.opacity(0.06)
                : Color.black.opacity(0.08)
        }

        static func divider(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color.white.opacity(0.08)
                : Color.black.opacity(0.08)
        }

        static func shadow(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color.black.opacity(0.45)
                : Color.black.opacity(0.12)
        }

        static func placeholder(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color.white.opacity(0.35)
                : Color.black.opacity(0.35)
        }
    }
}

// MARK: - UI Constants (kept here for SwiftUI views)

extension Constants {
    enum UI {
        // Card dimensions
        static let cardMinWidth: CGFloat = 280
        static let cardMaxWidth: CGFloat = 350
        static let cardSpacing: CGFloat = 16

        // Avatar sizes
        static let avatarSmall: CGFloat = 32
        static let avatarMedium: CGFloat = 48
        static let avatarLarge: CGFloat = 64

        // Corner radii
        static let cornerRadiusSmall: CGFloat = 4
        static let cornerRadiusMedium: CGFloat = 8
        static let cornerRadiusLarge: CGFloat = 12

        // Padding
        static let paddingSmall: CGFloat = 4
        static let paddingMedium: CGFloat = 8
        static let paddingLarge: CGFloat = 16

        // Animation durations
        static let animationFast: Double = 0.15
        static let animationNormal: Double = 0.25
        static let animationSlow: Double = 0.4
    }

    // MARK: - Sidebar

    enum Sidebar {
        static let minWidth: CGFloat = 200
        static let idealWidth: CGFloat = 220
        static let maxWidth: CGFloat = 280
    }

    // MARK: - Content Column

    enum Content {
        static let minWidth: CGFloat = 400
        static let idealWidth: CGFloat = 500
        static let maxWidth: CGFloat = 700
    }
}

// MARK: - View Styles

private struct WindowBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(DesignSystem.Colors.windowGradient(colorScheme).ignoresSafeArea())
    }
}

private struct AppCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let elevated: Bool
    let showShadow: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(elevated ? DesignSystem.Colors.surfaceElevated(colorScheme) : DesignSystem.Colors.surface(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
            )
            .shadow(
                color: showShadow ? DesignSystem.Colors.shadow(colorScheme) : .clear,
                radius: showShadow ? 16 : 0,
                y: showShadow ? 8 : 0
            )
    }
}

private struct AppInputModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.input, style: .continuous)
                    .fill(DesignSystem.Colors.inputBackground(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.input, style: .continuous)
                    .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
            )
    }
}

extension View {
    func appWindowBackground() -> some View {
        modifier(WindowBackgroundModifier())
    }

    func appCard(cornerRadius: CGFloat = DesignSystem.Radius.cardSmall, elevated: Bool = false, shadow: Bool = false) -> some View {
        modifier(AppCardModifier(cornerRadius: cornerRadius, elevated: elevated, showShadow: shadow))
    }

    func appInput() -> some View {
        modifier(AppInputModifier())
    }
}

#if os(macOS)
@MainActor
final class CursorCoordinator {
    static let shared = CursorCoordinator()

    private var monitor: Any?
    private var lastCursorKind: CursorKind = .arrow

    private enum CursorKind {
        case arrow
        case iBeam
        case pointingHand

        var cursor: NSCursor {
            switch self {
            case .arrow:
                return .arrow
            case .iBeam:
                return .iBeam
            case .pointingHand:
                return .pointingHand
            }
        }
    }

    private init() {}

    func start() {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .mouseMoved,
                .cursorUpdate,
                .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                .otherMouseDown, .otherMouseUp, .otherMouseDragged,
                .scrollWheel
            ]
        ) { [weak self] event in
            self?.updateCursor(for: event)
            return event
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        setCursorIfNeeded(.arrow)
    }

    private func updateCursor(for event: NSEvent) {
        let window = event.window ?? NSApp.keyWindow
        guard let window else {
            setCursorIfNeeded(.arrow)
            return
        }

        window.acceptsMouseMovedEvents = true
        guard let contentView = window.contentView else {
            setCursorIfNeeded(.arrow)
            return
        }

        let locationInView = contentView.convert(event.locationInWindow, from: nil)
        guard contentView.bounds.contains(locationInView),
              let hitView = contentView.hitTest(locationInView) else {
            setCursorIfNeeded(.arrow)
            return
        }

        if isEditableTextInput(hitView) {
            setCursorIfNeeded(.iBeam)
            return
        }

        if isInteractive(hitView) {
            setCursorIfNeeded(.pointingHand)
            return
        }

        setCursorIfNeeded(.arrow)
    }

    private func isEditableTextInput(_ view: NSView) -> Bool {
        for candidate in view.ancestry {
            if candidate is NSTextView {
                return true
            }

            if let textField = candidate as? NSTextField, textField.isEditable {
                return true
            }

            if let comboBox = candidate as? NSComboBox, comboBox.isEditable {
                return true
            }

            let className = NSStringFromClass(type(of: candidate))
            if className.contains("TextField")
                || className.contains("TextEditor")
                || className.contains("NSTextView") {
                return true
            }
        }

        return false
    }

    private func isInteractive(_ view: NSView) -> Bool {
        for candidate in view.ancestry {
            if candidate.gestureRecognizers.contains(where: { $0 is NSClickGestureRecognizer }) {
                return true
            }

            if candidate is NSButton || candidate is NSPopUpButton || candidate is NSSegmentedControl {
                return true
            }

            if let control = candidate as? NSControl, !(control is NSTextField) {
                return true
            }

            let className = NSStringFromClass(type(of: candidate))
            if className.contains("Button")
                || className.contains("Link")
                || className.contains("Toggle")
                || className.contains("Picker")
                || className.contains("Segmented")
                || className.contains("Menu")
                || className.contains("ListRow")
                || className.contains("TableRow")
                || className.contains("OutlineRow") {
                return true
            }
        }

        return false
    }

    private func setCursorIfNeeded(_ kind: CursorKind) {
        guard kind != lastCursorKind else { return }
        kind.cursor.set()
        lastCursorKind = kind
    }
}

private extension NSView {
    var ancestry: AnySequence<NSView> {
        AnySequence(sequence(first: self, next: { $0.superview }))
    }
}
#endif

// MARK: - Custom Values

enum CustomValuesStore {
    private static let customStatusKey = "customApplicationStatuses"
    private static let customSourceKey = "customSources"
    private static let customInterviewStageKey = "customInterviewStages"

    static func customStatuses() -> [String] {
        UserDefaults.standard.stringArray(forKey: customStatusKey) ?? []
    }

    static func addCustomStatus(_ value: String) {
        add(value, to: customStatusKey, disallowing: ApplicationStatus.allCases.map(\.rawValue))
    }

    static func customSources() -> [String] {
        UserDefaults.standard.stringArray(forKey: customSourceKey) ?? []
    }

    static func addCustomSource(_ value: String) {
        add(value, to: customSourceKey, disallowing: Source.allCases.map(\.rawValue))
    }

    static func customInterviewStages() -> [String] {
        UserDefaults.standard.stringArray(forKey: customInterviewStageKey) ?? []
    }

    static func addCustomInterviewStage(_ value: String) {
        add(value, to: customInterviewStageKey, disallowing: InterviewStage.allCases.map(\.rawValue))
    }

    private static func add(_ value: String, to key: String, disallowing reserved: [String]) {
        let normalized = normalize(value)
        guard !normalized.isEmpty else { return }

        let reservedSet = Set(reserved.map { normalize($0).lowercased() })
        guard !reservedSet.contains(normalized.lowercased()) else { return }

        var existing = UserDefaults.standard.stringArray(forKey: key) ?? []
        let existingSet = Set(existing.map { normalize($0).lowercased() })
        guard !existingSet.contains(normalized.lowercased()) else { return }

        existing.insert(normalized, at: 0)
        UserDefaults.standard.set(existing, forKey: key)
    }

    private static func normalize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
