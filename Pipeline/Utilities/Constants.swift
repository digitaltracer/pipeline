import Foundation
import SwiftUI
import PipelineKit
#if os(macOS)
import AppKit
#endif

// MARK: - Color Extensions

extension Color {
    static let pipelineBlue = Color(red: 0.15, green: 0.383, blue: 0.85)      // HSL(220, 70%, 50%)
    static let pipelineGreen = Color(red: 0.131, green: 0.77, blue: 0.365)    // HSL(142, 71%, 45%)
    static let pipelineOrange = Color(red: 0.96, green: 0.622, blue: 0.04)    // HSL(38, 92%, 50%)
    static let pipelineRed = Color(red: 0.863, green: 0.157, blue: 0.157)     // HSL(0, 72%, 51%)
}

// MARK: - Design System

enum DesignSystem {
    enum Radius {
        static let card: CGFloat = 12       // rounded-lg, cards & modals
        static let cardSmall: CGFloat = 10  // rounded-md, compact panels
        static let input: CGFloat = 10      // rounded-md, buttons & inputs
        static let badge: CGFloat = 8       // rounded-sm, badges & small elements
        static let pill: CGFloat = 999      // rounded-full, capsules
    }

    enum Spacing {
        static let xs: CGFloat = 4    // tight inline spacing
        static let sm: CGFloat = 8    // badge spacing, compact rows
        static let md: CGFloat = 16   // card padding, section gaps
        static let lg: CGFloat = 24   // major section spacing
        static let xl: CGFloat = 32   // page margins, modal padding
    }

    enum Colors {
        // MARK: Accent / Primary
        static let accent = Color.pipelineBlue

        static func primary(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0.236, green: 0.515, blue: 0.964)  // HSL(217, 91%, 60%)
                : Color(red: 0.15, green: 0.383, blue: 0.85)     // HSL(220, 70%, 50%)
        }

        // MARK: Surfaces
        static func windowGradient(_ scheme: ColorScheme) -> LinearGradient {
            if scheme == .dark {
                return LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.093, blue: 0.12),   // --background dark
                        Color(red: 0.064, green: 0.075, blue: 0.096)  // sidebar-background dark
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            return LinearGradient(
                colors: [
                    Color(red: 0.954, green: 0.958, blue: 0.966),  // --background light
                    Color(red: 0.932, green: 0.937, blue: 0.948)   // --accent light
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        static func sidebarBackground(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0.064, green: 0.075, blue: 0.096)  // HSL(220, 20%, 8%)
                : Color(red: 0.98, green: 0.98, blue: 0.98)     // HSL(0, 0%, 98%)
        }

        static func contentBackground(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0.08, green: 0.093, blue: 0.12)    // HSL(220, 20%, 10%)
                : Color(red: 0.954, green: 0.958, blue: 0.966)  // HSL(220, 14%, 96%)
        }

        static func surface(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0.115, green: 0.132, blue: 0.165)  // HSL(220, 18%, 14%)
                : .white
        }

        static func surfaceElevated(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0.164, green: 0.188, blue: 0.236)  // HSL(220, 18%, 20%)
                : Color(red: 0.909, green: 0.916, blue: 0.931)  // HSL(220, 14%, 92%)
        }

        static func inputBackground(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0.148, green: 0.169, blue: 0.212)  // HSL(220, 18%, 18%)
                : Color(red: 0.886, green: 0.895, blue: 0.914)  // HSL(220, 14%, 90%)
        }

        // MARK: Utility
        static func stroke(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0.180, green: 0.207, blue: 0.259)  // HSL(220, 18%, 22%)
                : Color(red: 0.863, green: 0.874, blue: 0.897)  // HSL(220, 14%, 88%)
        }

        static func divider(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0.180, green: 0.207, blue: 0.259)  // HSL(220, 18%, 22%)
                : Color(red: 0.863, green: 0.874, blue: 0.897)  // HSL(220, 14%, 88%)
        }

        static func shadow(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color.black.opacity(0.3)
                : Color(red: 0.08, green: 0.093, blue: 0.12).opacity(0.08)
        }

        static func placeholder(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0.505, green: 0.535, blue: 0.595)  // HSL(220, 10%, 55%)
                : Color(red: 0.405, green: 0.435, blue: 0.495)  // HSL(220, 10%, 45%)
        }

        // MARK: Destructive
        static func destructive(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0.81, green: 0.19, blue: 0.19)     // HSL(0, 62%, 50%)
                : Color(red: 0.863, green: 0.157, blue: 0.157)  // HSL(0, 72%, 51%)
        }

        // MARK: Glass Effect
        static func glassBackground(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0.115, green: 0.132, blue: 0.165).opacity(0.7)
                : Color.white.opacity(0.7)
        }

        static func glassBorder(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color.white.opacity(0.1)
                : Color.white.opacity(0.3)
        }

        static func glassShadow(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color.black.opacity(0.3)
                : Color(red: 0.08, green: 0.093, blue: 0.12).opacity(0.08)
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
        static let animationNormal: Double = 0.2
        static let animationSlow: Double = 0.3
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

    // MARK: - Detail Column

    enum Detail {
        static let minWidth: CGFloat = 432
        static let idealWidth: CGFloat = 552
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
    let showStroke: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(elevated ? DesignSystem.Colors.surfaceElevated(colorScheme) : DesignSystem.Colors.surface(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(showStroke ? DesignSystem.Colors.stroke(colorScheme) : .clear, lineWidth: showStroke ? 1 : 0)
            )
            .shadow(
                color: showShadow ? DesignSystem.Colors.shadow(colorScheme) : .clear,
                radius: showShadow ? 6 : 0,
                y: showShadow ? 2 : 0
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

private struct AppGlassModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DesignSystem.Colors.glassBorder(colorScheme), lineWidth: 1)
            )
            .shadow(
                color: DesignSystem.Colors.glassShadow(colorScheme),
                radius: 12,
                y: 4
            )
    }
}

private struct FastTooltipModifier: ViewModifier {
    let text: String
    let delay: Double

    @State private var isHovering = false
    @State private var showTooltip = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                hoverTask?.cancel()
                if hovering {
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(delay))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeIn(duration: 0.15)) {
                            showTooltip = true
                        }
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.1)) {
                        showTooltip = false
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if showTooltip {
                    Text(text)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.regularMaterial)
                                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        )
                        .fixedSize()
                        .offset(y: 32)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .zIndex(999)
                }
            }
            .accessibilityLabel(text)
    }
}

extension View {
    func appWindowBackground() -> some View {
        modifier(WindowBackgroundModifier())
    }

    func appCard(cornerRadius: CGFloat = DesignSystem.Radius.card, elevated: Bool = false, shadow: Bool = false, stroke: Bool = true) -> some View {
        modifier(AppCardModifier(cornerRadius: cornerRadius, elevated: elevated, showShadow: shadow, showStroke: stroke))
    }

    func appInput() -> some View {
        modifier(AppInputModifier())
    }

    func appGlass(cornerRadius: CGFloat = DesignSystem.Radius.card) -> some View {
        modifier(AppGlassModifier(cornerRadius: cornerRadius))
    }

    /// Fast tooltip that appears after a short delay (default 0.4s) instead of the system ~2s delay.
    func fastTooltip(_ text: String, delay: Double = 0.4) -> some View {
        modifier(FastTooltipModifier(text: text, delay: delay))
    }

#if os(macOS)
    func interactiveHandCursor() -> some View {
        onContinuousHover { phase in
            switch phase {
            case .active:
                NSCursor.pointingHand.set()
            case .ended:
                NSCursor.arrow.set()
            }
        }
    }
#else
    func interactiveHandCursor() -> some View { self }
#endif
}

#if os(macOS)
@MainActor
final class CursorCoordinator {
    static let shared = CursorCoordinator()

    private static let interactiveAccessibilityRoles: Set<NSAccessibility.Role> = [
        .button,
        .link,
        .menuButton,
        .disclosureTriangle,
        .popUpButton,
        .radioButton,
        .checkBox,
        .tabGroup,
        .menuItem
    ]

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
        guard let hitView = hitView(in: window, locationInWindow: event.locationInWindow) else {
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

    private func hitView(in window: NSWindow, locationInWindow: NSPoint) -> NSView? {
        guard let contentView = window.contentView else { return nil }

        if let hitView = hitTest(in: contentView, locationInWindow: locationInWindow) {
            return hitView
        }

        // Toolbar/titlebar controls live outside the content view in the frame view.
        if let frameView = contentView.superview,
           let hitView = hitTest(in: frameView, locationInWindow: locationInWindow) {
            return hitView
        }

        return nil
    }

    private func hitTest(in rootView: NSView, locationInWindow: NSPoint) -> NSView? {
        let locationInView = rootView.convert(locationInWindow, from: nil)
        guard rootView.bounds.contains(locationInView) else { return nil }
        return rootView.hitTest(locationInView)
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

            if hasInteractiveAccessibilityRole(candidate) {
                return true
            }

            let className = NSStringFromClass(type(of: candidate))
            if className.contains("Button")
                || className.contains("ToolbarItem")
                || className.contains("ToolbarButton")
                || className.contains("TitlebarButton")
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

    private func hasInteractiveAccessibilityRole(_ view: NSView) -> Bool {
        guard let role = view.accessibilityRole() else { return false }
        return Self.interactiveAccessibilityRoles.contains(role)
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
