import Foundation
import SwiftUI

enum Constants {
    // MARK: - App Info

    enum App {
        static let name = "Pipeline"
        static let bundleID = "com.pipeline.app"
        static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    // MARK: - iCloud

    enum iCloud {
        static let containerID = "iCloud.com.pipeline.app"
    }

    // MARK: - UI Constants

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

    // MARK: - External URLs

    enum URLs {
        static let clearbitLogo = "https://logo.clearbit.com/"
        static let privacyPolicy = "https://github.com"
        static let termsOfService = "https://github.com"
        static let support = "https://github.com"

        // API Documentation
        static let openAIDocs = "https://platform.openai.com/docs"
        static let anthropicDocs = "https://docs.anthropic.com"
        static let geminiDocs = "https://ai.google.dev/docs"

        // API Key Pages
        static let openAIKeys = "https://platform.openai.com/api-keys"
        static let anthropicConsole = "https://console.anthropic.com/"
        static let geminiKeys = "https://makersuite.google.com/app/apikey"
    }

    // MARK: - UserDefaults Keys

    enum UserDefaultsKeys {
        static let appearanceMode = "appearanceMode"
        static let selectedAIProvider = "selectedAIProvider"
        static let selectedAIModel = "selectedAIModel"
        static let notificationsEnabled = "notificationsEnabled"
        static let reminderTiming = "reminderTiming"
        static let lastSyncDate = "lastSyncDate"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    // MARK: - Notification Identifiers

    enum Notifications {
        static let followUpReminderCategory = "FOLLOWUP_REMINDER"
        static let followUpIdentifierPrefix = "followup-"
    }

    // MARK: - Limits

    enum Limits {
        static let maxJobDescriptionLength = 50000
        static let maxNotesLength = 10000
        static let maxURLLength = 2048
        static let webContentMaxLength = 15000 // For AI parsing
    }
}

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
