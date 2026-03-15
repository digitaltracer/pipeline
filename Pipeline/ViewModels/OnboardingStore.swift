import Foundation
import Observation
import PipelineKit

enum OnboardingAction: Hashable {
    case addApplication
    case openAISettings
    case openResumeWorkspace
    case openIntegrations
    case openDashboard
    case replayTour
}

enum OnboardingStep: String, CaseIterable, Identifiable {
    case welcome
    case pipeline
    case focus
    case ai
    case googleCalendar
    case linkedInImport
    case launch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .pipeline:
            return "Track Everything"
        case .focus:
            return "See Momentum"
        case .ai:
            return "Use AI Deliberately"
        case .googleCalendar:
            return "Sync Interview Timing"
        case .linkedInImport:
            return "Unlock Referrals"
        case .launch:
            return "Launch Your Workspace"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            return "Understand the workflow before adding your first record."
        case .pipeline:
            return "Capture job applications, keep statuses clean, and prioritize what matters."
        case .focus:
            return "Move between dashboard, kanban, and follow-up views without losing context."
        case .ai:
            return "Parse jobs, tailor resumes, and compare offers after configuring a provider."
        case .googleCalendar:
            return "On macOS, connect Google Calendar when you want interview events and review flows in one place."
        case .linkedInImport:
            return "Import your LinkedIn connections export to surface referral opportunities without cluttering contacts."
        case .launch:
            return "Set up the few things that unlock the rest of the app."
        }
    }

    var systemImage: String {
        switch self {
        case .welcome:
            return "sparkles.rectangle.stack"
        case .pipeline:
            return "square.grid.2x2"
        case .focus:
            return "chart.xyaxis.line"
        case .ai:
            return "wand.and.stars"
        case .googleCalendar:
            return "calendar.badge.clock"
        case .linkedInImport:
            return "person.3.sequence.fill"
        case .launch:
            return "checklist"
        }
    }
}

struct OnboardingChecklistItem: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let action: OnboardingAction
    let isComplete: Bool
    let isRequired: Bool
}

struct OnboardingProgress: Hashable {
    let applicationCount: Int
    let hasApplication: Bool
    let hasConfiguredAI: Bool
    let hasSavedResume: Bool
    let guidanceMuted: Bool
    let hasCompletedIntro: Bool

    var isSetupComplete: Bool {
        hasApplication && hasConfiguredAI && hasSavedResume
    }

    var shouldShowSetupGuidance: Bool {
        !guidanceMuted && !isSetupComplete
    }

    var completedRequiredCount: Int {
        requiredItems.filter(\.isComplete).count
    }

    var totalRequiredCount: Int {
        requiredItems.count
    }

    var progressLabel: String {
        "\(completedRequiredCount)/\(totalRequiredCount) complete"
    }

    var summary: String {
        if isSetupComplete {
            return "Core setup is complete. Replay the tour any time from Settings or the sidebar."
        }

        if hasApplication {
            return "You have live data now. Finish AI and resume setup to unlock the strongest workflows."
        }

        return "Start with one real application, then wire up AI and your master resume when you are ready."
    }

    var requiredItems: [OnboardingChecklistItem] {
        [
            OnboardingChecklistItem(
                id: "application",
                title: hasApplication ? "First application added" : "Add your first application",
                detail: hasApplication
                    ? "\(applicationCount) application\(applicationCount == 1 ? "" : "s") in the workspace."
                    : "Create one real application to activate the grid, kanban, dashboard, and follow-up views.",
                action: .addApplication,
                isComplete: hasApplication,
                isRequired: true
            ),
            OnboardingChecklistItem(
                id: "ai",
                title: hasConfiguredAI ? "AI provider configured" : "Configure AI parsing",
                detail: hasConfiguredAI
                    ? "Job parsing, resume tailoring, and offer analysis can use your configured provider."
                    : "Add at least one provider API key so Pipeline can parse jobs and power AI workflows.",
                action: .openAISettings,
                isComplete: hasConfiguredAI,
                isRequired: true
            ),
            OnboardingChecklistItem(
                id: "resume",
                title: hasSavedResume ? "Master resume saved" : "Import or draft your master resume",
                detail: hasSavedResume
                    ? "Resume tailoring can work from your saved master revision."
                    : "Save one master resume revision so tailoring and ATS checks have a base document.",
                action: .openResumeWorkspace,
                isComplete: hasSavedResume,
                isRequired: true
            )
        ]
    }

    var optionalItems: [OnboardingChecklistItem] {
        [
            OnboardingChecklistItem(
                id: "integrations",
                title: "Review integrations and browser tools",
                detail: "Connect the extension and workflow integrations when you want faster capture and richer automation.",
                action: .openIntegrations,
                isComplete: false,
                isRequired: false
            )
        ]
    }

    var nextRecommendedAction: OnboardingAction {
        requiredItems.first(where: { !$0.isComplete })?.action ?? .openDashboard
    }

    static let preview = OnboardingProgress(
        applicationCount: 0,
        hasApplication: false,
        hasConfiguredAI: false,
        hasSavedResume: false,
        guidanceMuted: false,
        hasCompletedIntro: false
    )
}

@Observable
final class OnboardingStore {
    var isPresentingIntro = false
    var guidanceMuted: Bool {
        didSet {
            defaults.set(guidanceMuted, forKey: Constants.UserDefaultsKeys.onboardingGuidanceMuted)
        }
    }

    var hasCompletedIntro: Bool {
        didSet {
            defaults.set(hasCompletedIntro, forKey: Constants.UserDefaultsKeys.hasCompletedOnboarding)
        }
    }

    var lastSeenVersion: String {
        didSet {
            defaults.set(lastSeenVersion, forKey: Constants.UserDefaultsKeys.onboardingLastSeenVersion)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.guidanceMuted = defaults.bool(forKey: Constants.UserDefaultsKeys.onboardingGuidanceMuted)
        self.hasCompletedIntro = defaults.bool(forKey: Constants.UserDefaultsKeys.hasCompletedOnboarding)
        self.lastSeenVersion = defaults.string(forKey: Constants.UserDefaultsKeys.onboardingLastSeenVersion) ?? ""
    }

    func presentIntroIfNeeded() {
        guard !hasCompletedIntro, !isPresentingIntro else { return }
        isPresentingIntro = true
    }

    func presentIntro(force: Bool = false) {
        guard force || !hasCompletedIntro else { return }
        lastSeenVersion = Constants.App.version
        isPresentingIntro = true
    }

    func completeIntro() {
        hasCompletedIntro = true
        lastSeenVersion = Constants.App.version
        isPresentingIntro = false
    }

    func skipIntro() {
        completeIntro()
    }

    func muteGuidance() {
        guidanceMuted = true
    }

    func restoreGuidance() {
        guidanceMuted = false
    }
}
