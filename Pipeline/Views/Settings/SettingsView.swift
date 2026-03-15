import SwiftUI
import SwiftData
import UserNotifications
import PipelineKit

enum SettingsEntryPoint: Hashable {
    case root
    case aiProvider
    case integrations
    case about
}

#if os(macOS)
private enum SettingsCategory: String, CaseIterable, Identifiable {
    case appearance
    case aiProvider
    case allApplications
    case analytics
    case notifications
    case integrations
    case security
    case sync
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .aiProvider: return "AI Provider"
        case .allApplications: return "All Applications"
        case .analytics: return "Analytics"
        case .notifications: return "Notifications"
        case .integrations: return "Integrations"
        case .security: return "Security"
        case .sync: return "iCloud Sync"
        case .about: return "About"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance:
            return "Theme and display preferences"
        case .aiProvider:
            return "Provider, model, and API key"
        case .allApplications:
            return "Choose which status types appear in All Applications"
        case .analytics:
            return "Dashboard currency and planning preferences"
        case .notifications:
            return "Follow-up reminder behavior"
        case .integrations:
            return "Connected tools, permissions, and import workflows"
        case .security:
            return "App lock and privacy policy"
        case .sync:
            return "Choose local-only or iCloud-backed storage"
        case .about:
            return "Support links and app details"
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintbrush.fill"
        case .aiProvider: return "brain.head.profile"
        case .allApplications: return "line.3.horizontal.decrease.circle.fill"
        case .analytics: return "chart.xyaxis.line"
        case .notifications: return "bell.badge.fill"
        case .integrations: return "puzzlepiece.extension.fill"
        case .security: return "lock.shield.fill"
        case .sync: return "icloud.fill"
        case .about: return "info.circle.fill"
        }
    }
}

private extension SettingsCategory {
    init(entryPoint: SettingsEntryPoint) {
        switch entryPoint {
        case .aiProvider:
            self = .aiProvider
        case .integrations:
            self = .integrations
        case .about:
            self = .about
        case .root:
            self = .appearance
        }
    }
}
#endif

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    var isPresentedInSheet: Bool = false
    var entryPoint: SettingsEntryPoint = .root
    var onReplayOnboarding: (() -> Void)? = nil
    var onboardingGuidanceMuted: Binding<Bool>? = nil
    @Environment(\.dismiss) private var dismiss

    #if os(macOS)
    @State private var selectedCategory: SettingsCategory
    @Environment(\.colorScheme) private var colorScheme
    #endif

    init(
        viewModel: SettingsViewModel,
        isPresentedInSheet: Bool = false,
        entryPoint: SettingsEntryPoint = .root,
        onReplayOnboarding: (() -> Void)? = nil,
        onboardingGuidanceMuted: Binding<Bool>? = nil
    ) {
        self.viewModel = viewModel
        self.isPresentedInSheet = isPresentedInSheet
        self.entryPoint = entryPoint
        self.onReplayOnboarding = onReplayOnboarding
        self.onboardingGuidanceMuted = onboardingGuidanceMuted
        #if os(macOS)
        _selectedCategory = State(initialValue: SettingsCategory(entryPoint: entryPoint))
        #endif
    }

    var body: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            settingsNavigationRail

            Divider()
                .overlay(DesignSystem.Colors.divider(colorScheme))

            settingsDetailPanel
        }
        .frame(minWidth: 980, minHeight: 700)
        .appWindowBackground()
        #else
        NavigationStack {
            Group {
                if entryPoint == .root {
                    iOSRootList
                } else {
                    directEntryPointContent
                }
            }
            .navigationTitle(iOSNavigationTitle)
            .toolbar {
                if isPresentedInSheet {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }
        #endif
    }

    #if os(macOS)
    private var settingsNavigationRail: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.accent)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.26 : 0.12))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Personalize Pipeline for a focused workflow.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 6)

            VStack(spacing: 8) {
                ForEach(SettingsCategory.allCases) { category in
                    SettingsCategoryRow(
                        category: category,
                        isSelected: selectedCategory == category
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = category
                        }
                    }
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text("Pipeline")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Version \(Constants.App.version) (\(Constants.App.build))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard(cornerRadius: 12, elevated: true, shadow: false)
        }
        .padding(22)
        .frame(width: 280, alignment: .topLeading)
        .background(DesignSystem.Colors.sidebarBackground(colorScheme))
    }

    private var settingsDetailPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if selectedCategory == .notifications {
                    NotificationSettingsContent(
                        viewModel: viewModel,
                        isPresentedInSheet: isPresentedInSheet
                    )
                } else {
                    HStack(alignment: .top) {
                        HStack(spacing: 12) {
                            Image(systemName: selectedCategory.icon)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.accent)
                                .frame(width: 34, height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.24 : 0.12))
                                )

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Preferences")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                    .tracking(0.8)

                                Text(selectedCategory.title)
                                    .font(.title3)
                                    .fontWeight(.semibold)

                                Text(selectedCategory.subtitle)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        if isPresentedInSheet {
                            Button("Done") {
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(DesignSystem.Colors.accent)
                        }
                    }
                    .padding(20)
                    .appCard(cornerRadius: 16, elevated: true, shadow: false)

                    SettingsPanelCard(
                        title: selectedCategory.title,
                        subtitle: selectedCategory.subtitle,
                        icon: selectedCategory.icon
                    ) {
                        selectedCategoryContent
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.contentBackground(colorScheme))
    }

    @ViewBuilder
    private var selectedCategoryContent: some View {
        switch selectedCategory {
        case .appearance:
            AppearanceSettingsContent(viewModel: viewModel)
        case .aiProvider:
            AIProviderSettingsContent(viewModel: viewModel)
        case .allApplications:
            AllApplicationsSettingsContent(viewModel: viewModel)
        case .analytics:
            AnalyticsSettingsContent(viewModel: viewModel)
        case .notifications:
            NotificationSettingsContent(viewModel: viewModel)
        case .integrations:
            IntegrationsSettingsContentView()
        case .security:
            SecuritySettingsContent(viewModel: viewModel)
        case .sync:
            SyncSettingsContent(viewModel: viewModel)
        case .about:
            AboutSettingsContent(
                onReplayOnboarding: onReplayOnboarding,
                onboardingGuidanceMuted: onboardingGuidanceMuted
            )
        }
    }
    #endif
}

#if !os(macOS)
private extension SettingsView {
    var iOSNavigationTitle: String {
        switch entryPoint {
        case .root:
            return "Settings"
        case .aiProvider:
            return "AI Provider"
        case .integrations:
            return "Integrations"
        case .about:
            return "About"
        }
    }

    var iOSRootList: some View {
        List {
            Section {
                NavigationLink {
                    AppearanceSettingsView(viewModel: viewModel)
                } label: {
                    Label("Appearance", systemImage: "paintbrush")
                }

                NavigationLink {
                    AIProviderSettingsView(viewModel: viewModel)
                } label: {
                    Label("AI Provider", systemImage: "brain")
                }

                NavigationLink {
                    AllApplicationsSettingsView(viewModel: viewModel)
                } label: {
                    Label("All Applications", systemImage: "line.3.horizontal.decrease.circle")
                }

                NavigationLink {
                    AnalyticsSettingsView(viewModel: viewModel)
                } label: {
                    Label("Analytics", systemImage: "chart.xyaxis.line")
                }

                NavigationLink {
                    NotificationSettingsView(viewModel: viewModel)
                } label: {
                    Label("Notifications", systemImage: "bell")
                }

                NavigationLink {
                    IntegrationsSettingsContentView()
                        .navigationTitle("Integrations")
                } label: {
                    Label("Integrations", systemImage: "puzzlepiece.extension")
                }

                NavigationLink {
                    SecuritySettingsView(viewModel: viewModel)
                } label: {
                    Label("Security", systemImage: "lock.shield")
                }

                NavigationLink {
                    SyncSettingsView(viewModel: viewModel)
                } label: {
                    Label("iCloud Sync", systemImage: "icloud")
                }
            }

            onboardingSection

            Section {
                if let supportURL = URL(string: Constants.URLs.support) {
                    Link(destination: supportURL) {
                        Label("Report an Issue", systemImage: "exclamationmark.bubble")
                    }
                }
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Constants.App.version)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    var directEntryPointContent: some View {
        switch entryPoint {
        case .root:
            iOSRootList
        case .aiProvider:
            AIProviderSettingsView(viewModel: viewModel)
        case .integrations:
            IntegrationsSettingsContentView()
        case .about:
            List {
                onboardingSection
                Section {
                    if let supportURL = URL(string: Constants.URLs.support) {
                        Link(destination: supportURL) {
                            Label("Report an Issue", systemImage: "exclamationmark.bubble")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    var onboardingSection: some View {
        if onReplayOnboarding != nil || onboardingGuidanceMuted != nil {
            Section("Getting Started") {
                if let onReplayOnboarding {
                    Button {
                        onReplayOnboarding()
                        dismiss()
                    } label: {
                        Label("Replay Guided Tour", systemImage: "play.rectangle")
                    }
                }

                if let onboardingGuidanceMuted {
                    Toggle("Hide setup guidance", isOn: onboardingGuidanceMuted)
                }
            }
        }
    }
}
#endif

#if os(macOS)
private struct SettingsCategoryRow: View {
    let category: SettingsCategory
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: category.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)
                    .foregroundColor(isSelected ? DesignSystem.Colors.accent : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(.primary)

                    Text(category.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.24 : 0.14)
                            : Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected
                            ? DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.5 : 0.24)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsPanelCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let icon: String
    let content: Content

    init(title: String, subtitle: String? = nil, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.accent)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(DesignSystem.Colors.accent.opacity(0.1))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()
                .overlay(.secondary.opacity(0.12))

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 16, elevated: true, shadow: false)
    }
}
#endif

struct SettingsFormSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let icon: String?
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.accent)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(DesignSystem.Colors.accent.opacity(0.1))
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 14, elevated: false, shadow: false)
    }
}

struct AboutSettingsContent: View {
    var onReplayOnboarding: (() -> Void)? = nil
    var onboardingGuidanceMuted: Binding<Bool>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let onReplayOnboarding {
                Button(action: onReplayOnboarding) {
                    SettingsLinkRow(
                        title: "Replay Guided Tour",
                        subtitle: "Reopen the onboarding walkthrough and demo screens.",
                        icon: "play.rectangle"
                    )
                }
                .buttonStyle(.plain)
            }

            if let onboardingGuidanceMuted {
                Toggle(isOn: onboardingGuidanceMuted) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide setup guidance")
                        Text("Mute contextual onboarding cards until you turn them back on.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if onReplayOnboarding != nil {
                    Divider()
                }
            }

            if let supportURL = URL(string: Constants.URLs.support) {
                Link(destination: supportURL) {
                    SettingsLinkRow(
                        title: "Report an Issue",
                        subtitle: "Share bugs or feedback to improve Pipeline.",
                        icon: "exclamationmark.bubble"
                    )
                }
                .buttonStyle(.plain)
            }

            Divider()

            SettingsInfoRow(label: "Version", value: Constants.App.version)
            SettingsInfoRow(label: "Build", value: Constants.App.build)
        }
    }
}

private struct SettingsLinkRow: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "arrow.up.right.square")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 12, elevated: true, shadow: false)
        .contentShape(Rectangle())
    }
}

private struct SettingsInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
    }
}

struct AllApplicationsSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    private var statusOptions: [ApplicationStatus] {
        viewModel.allApplicationsStatusOptions()
    }

    private var visibleStatusCount: Int {
        statusOptions.filter { viewModel.isStatusVisibleInAllApplications($0) }.count
    }

    var body: some View {
        Form {
            Section {
                ForEach(statusOptions) { status in
                    Toggle(isOn: visibilityBinding(for: status)) {
                        Label(status.displayName, systemImage: status.icon)
                    }
                }
            } header: {
                Text("Show Status Types")
            } footer: {
                Text("These settings only affect the All Applications view.")
            }

            Section {
                Button("Show All Types") {
                    viewModel.resetAllApplicationsVisibilityToDefault()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("All Applications")
    }

    private func visibilityBinding(for status: ApplicationStatus) -> Binding<Bool> {
        Binding(
            get: {
                viewModel.isStatusVisibleInAllApplications(status)
            },
            set: { isVisible in
                let currentlyVisible = viewModel.isStatusVisibleInAllApplications(status)
                if !isVisible && currentlyVisible && visibleStatusCount <= 1 {
                    return
                }
                viewModel.setStatus(status, visibleInAllApplications: isVisible)
            }
        )
    }
}

struct AllApplicationsSettingsContent: View {
    @Bindable var viewModel: SettingsViewModel

    private var statusOptions: [ApplicationStatus] {
        viewModel.allApplicationsStatusOptions()
    }

    private var visibleStatusCount: Int {
        statusOptions.filter { viewModel.isStatusVisibleInAllApplications($0) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsFormSectionCard(
                title: "Visible Status Types",
                subtitle: "Choose which application status types appear when All Applications is selected.",
                icon: "line.3.horizontal.decrease.circle.fill"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(statusOptions) { status in
                        Toggle(isOn: visibilityBinding(for: status)) {
                            HStack {
                                Label(status.displayName, systemImage: status.icon)
                                Spacer()
                                if viewModel.isStatusVisibleInAllApplications(status) {
                                    Text("Shown")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .tint(DesignSystem.Colors.accent)
                    }
                }

                if visibleStatusCount <= 1 {
                    Text("At least one status type must remain visible.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            SettingsFormSectionCard(
                title: "Quick Action",
                subtitle: "Restore default behavior and show all status types.",
                icon: "arrow.counterclockwise.circle.fill"
            ) {
                Button("Show All Types") {
                    viewModel.resetAllApplicationsVisibilityToDefault()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func visibilityBinding(for status: ApplicationStatus) -> Binding<Bool> {
        Binding(
            get: {
                viewModel.isStatusVisibleInAllApplications(status)
            },
            set: { isVisible in
                let currentlyVisible = viewModel.isStatusVisibleInAllApplications(status)
                if !isVisible && currentlyVisible && visibleStatusCount <= 1 {
                    return
                }
                viewModel.setStatus(status, visibleInAllApplications: isVisible)
            }
        )
    }
}

struct SyncSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Enable iCloud Sync", isOn: $viewModel.cloudSyncEnabled)
                    .disabled(!viewModel.cloudSyncSupported)
            } footer: {
                if viewModel.cloudSyncSupported {
                    Text("When enabled, Pipeline syncs application data using your iCloud account.")
                } else {
                    Text("iCloud Sync is unavailable in this build configuration.")
                }
            }

            Section {
                Label(
                    viewModel.cloudSyncEnabledAtLaunch
                        ? "Current mode: iCloud sync is active."
                        : "Current mode: local-only storage.",
                    systemImage: viewModel.cloudSyncEnabledAtLaunch ? "checkmark.icloud.fill" : "internaldrive.fill"
                )
                .font(.subheadline)
            }

            if viewModel.cloudSyncFailedToStartAtLaunch,
               let cloudSyncStartupError = viewModel.cloudSyncStartupError {
                Section {
                    Label(
                        "Pipeline could not start iCloud sync on this launch.",
                        systemImage: "exclamationmark.icloud.fill"
                    )
                    .foregroundColor(.secondary)

                    Text(cloudSyncStartupError)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                } footer: {
                    Text(
                        "Pipeline kept your sync preference enabled, but this build is still running local-only storage. Check your iCloud capability, CloudKit container, signing profile, and iCloud account, then restart."
                    )
                }
            }

            if viewModel.cloudSyncNeedsRestart {
                Section {
                    Label(
                        "Restart Pipeline to apply this sync setting change.",
                        systemImage: "arrow.clockwise.circle.fill"
                    )
                    .foregroundColor(.secondary)
                } footer: {
                    Text(
                        viewModel.cloudSyncEnabled
                            ? "Sync will be enabled after restart."
                            : "Sync will be disabled after restart. Existing data is not deleted."
                    )
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("iCloud Sync")
    }
}

struct SyncSettingsContent: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsFormSectionCard(
                title: "Sync Source",
                subtitle: "Choose where Pipeline stores and syncs your data.",
                icon: "icloud"
            ) {
                Toggle("Enable iCloud Sync", isOn: $viewModel.cloudSyncEnabled)
                    .disabled(!viewModel.cloudSyncSupported)
                    .tint(DesignSystem.Colors.accent)

                if viewModel.cloudSyncSupported {
                    Text("When enabled, Pipeline syncs application data using your iCloud account.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("iCloud Sync is unavailable in this build configuration.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            SettingsFormSectionCard(
                title: "Current Mode",
                icon: viewModel.cloudSyncEnabledAtLaunch ? "checkmark.icloud.fill" : "internaldrive.fill"
            ) {
                Label(
                    viewModel.cloudSyncEnabledAtLaunch
                        ? "iCloud sync is currently active."
                        : "Local-only storage is currently active.",
                    systemImage: viewModel.cloudSyncEnabledAtLaunch ? "checkmark.circle.fill" : "internaldrive.fill"
                )
                .font(.subheadline)
            }

            if viewModel.cloudSyncFailedToStartAtLaunch,
               let cloudSyncStartupError = viewModel.cloudSyncStartupError {
                SettingsFormSectionCard(
                    title: "Sync Unavailable",
                    subtitle: "Pipeline kept your sync preference enabled, but CloudKit could not start on this launch.",
                    icon: "exclamationmark.icloud.fill"
                ) {
                    Text(cloudSyncStartupError)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)

                    Text(
                        "Check your iCloud capability, CloudKit container, signing profile, and iCloud account, then restart Pipeline."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            if viewModel.cloudSyncNeedsRestart {
                SettingsFormSectionCard(
                    title: "Restart Required",
                    subtitle: viewModel.cloudSyncEnabled
                        ? "Sync will be enabled after restart."
                        : "Sync will be disabled after restart. Existing data is not deleted.",
                    icon: "arrow.clockwise.circle.fill"
                ) {
                    Label(
                        "Restart Pipeline to apply this sync setting change.",
                        systemImage: "arrow.clockwise.circle.fill"
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct NotificationSettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @Query private var applications: [JobApplication]
    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined
    @State private var showPermissionDeniedAlert = false

    var body: some View {
        settingsForm
            .formStyle(.grouped)
            .navigationTitle("Notifications")
            .task {
                await refreshPermissionStatusAndSyncIfNeeded()
            }
            .onChange(of: viewModel.notificationsEnabled) { _, isEnabled in
                Task {
                    await handleNotificationsEnabledChange(isEnabled)
                }
            }
            .onChange(of: viewModel.reminderTiming) { _, timing in
                guard viewModel.notificationsEnabled else { return }
                Task {
                    await syncNotificationPreferences(reminderTiming: timing)
                }
            }
            .alert("Notifications Are Disabled", isPresented: $showPermissionDeniedAlert) {
                Button("Open System Settings") {
                    Task { @MainActor in
                        NotificationService.shared.openNotificationSettings()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Allow notifications for Pipeline in system settings to receive follow-up and task reminders.")
            }
    }

    private var settingsForm: some View {
        Form {
            notificationToggleSection

            if viewModel.notificationsEnabled {
                reminderTimingSection
                applyQueueSection
                permissionSection
            }
        }
    }

    private var notificationToggleSection: some View {
        Section {
            Toggle("Enable Notifications", isOn: $viewModel.notificationsEnabled)
        } footer: {
            Text("Get reminders for follow-up dates and task due dates you set on job applications.")
        }
    }

    private var reminderTimingSection: some View {
        Section("Reminder Timing") {
            Picker("When to Remind", selection: $viewModel.reminderTiming) {
                ForEach(ReminderTiming.allCases) { timing in
                    Text(timing.rawValue).tag(timing)
                }
            }
            .pickerStyle(.inline)
        }
    }

    private var applyQueueSection: some View {
        Section {
            Stepper(value: $viewModel.applyQueueDailyTarget, in: 1...12) {
                Text("Daily target: \(viewModel.applyQueueDailyTarget) jobs")
            }

            DatePicker(
                "Morning Queue Time",
                selection: applyQueueTimeBindingCompact,
                displayedComponents: .hourAndMinute
            )
        } header: {
            Text("Apply Queue")
        } footer: {
            Text("Pipeline recommends 3-5 applications per day. These settings control your morning apply-queue reminder.")
        }
    }

    private var permissionSection: some View {
        Section {
            Label(permissionStatusText, systemImage: permissionStatusIcon)
                .foregroundColor(permissionStatusColor)

            if permissionStatus == .denied {
                Button("Open System Settings") {
                    Task { @MainActor in
                        NotificationService.shared.openNotificationSettings()
                    }
                }
            } else if permissionStatus == .notDetermined {
                Button("Allow Notifications") {
                    Task {
                        await requestPermissionFromAction()
                    }
                }
            }
        } header: {
            Text("Notification Permission")
        } footer: {
            Text(notificationPermissionFooterText)
        }
    }

    private var permissionStatusText: String {
        switch permissionStatus {
        case .authorized, .provisional, .ephemeral:
            return "Permission granted"
        case .denied:
            return "Permission denied in system settings"
        case .notDetermined:
            return "Permission not requested yet"
        @unknown default:
            return "Permission status unavailable"
        }
    }

    private var permissionStatusIcon: String {
        switch permissionStatus {
        case .authorized, .provisional, .ephemeral:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        case .notDetermined:
            return "questionmark.circle.fill"
        @unknown default:
            return "exclamationmark.triangle.fill"
        }
    }

    private var permissionStatusColor: Color {
        switch permissionStatus {
        case .authorized, .provisional, .ephemeral:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .secondary
        @unknown default:
            return .secondary
        }
    }

    private var notificationPermissionFooterText: String {
        switch permissionStatus {
        case .authorized, .provisional, .ephemeral:
            return "Pipeline can send reminders for follow-up dates and task due dates."
        case .denied:
            return "Notifications are blocked. Open system settings to enable them for Pipeline."
        case .notDetermined:
            return "Pipeline will ask for notification permission when you enable reminders."
        @unknown default:
            return "Check your system settings if reminders are not arriving."
        }
    }

    private var applyQueueTimeBindingCompact: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = viewModel.applyQueueNotificationHour
                components.minute = viewModel.applyQueueNotificationMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                viewModel.applyQueueNotificationHour = Calendar.current.component(.hour, from: newValue)
                viewModel.applyQueueNotificationMinute = Calendar.current.component(.minute, from: newValue)
            }
        )
    }

    @MainActor
    private func refreshPermissionStatusAndSyncIfNeeded() async {
        permissionStatus = await NotificationService.shared.checkPermissionStatus()

        guard viewModel.notificationsEnabled else { return }
        await syncNotificationPreferences(reminderTiming: viewModel.reminderTiming)
    }

    @MainActor
    private func requestPermissionFromAction() async {
        let updatedStatus = await NotificationService.shared.authorizationStatusAfterPromptIfNeeded()
        permissionStatus = updatedStatus

        if NotificationService.shared.isPermissionGranted(updatedStatus) {
            await syncNotificationPreferences(reminderTiming: viewModel.reminderTiming)
        } else {
            showPermissionDeniedAlert = true
        }
    }

    @MainActor
    private func handleNotificationsEnabledChange(_ isEnabled: Bool) async {
        if isEnabled {
            let updatedStatus = await NotificationService.shared.authorizationStatusAfterPromptIfNeeded()
            permissionStatus = updatedStatus

            guard NotificationService.shared.isPermissionGranted(updatedStatus) else {
                viewModel.notificationsEnabled = false
                NotificationService.shared.removeAllNotifications()
                showPermissionDeniedAlert = true
                return
            }

            await syncNotificationPreferences(reminderTiming: viewModel.reminderTiming)
        } else {
            NotificationService.shared.removeAllNotifications()
            permissionStatus = await NotificationService.shared.checkPermissionStatus()
        }
    }

    @MainActor
    private func syncNotificationPreferences(reminderTiming: ReminderTiming) async {
        await NotificationService.shared.syncReminderState(
            for: applications,
            notificationsEnabled: true,
            timing: reminderTiming
        )
        await NotificationService.shared.syncWeeklyDigestReminder(
            schedule: viewModel.weeklyDigestSchedule,
            notificationsEnabled: viewModel.notificationsEnabled,
            digestNotificationsEnabled: viewModel.weeklyDigestNotificationsEnabled
        )
    }
}

struct AnalyticsSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Picker("Base Currency", selection: $viewModel.analyticsBaseCurrency) {
                    ForEach(Currency.allCases) { currency in
                        Text("\(currency.displayName) (\(currency.symbol))").tag(currency)
                    }
                }
            } header: {
                Text("Dashboard")
            } footer: {
                Text("Salary analytics convert compensation into this currency using cached Frankfurter exchange rates.")
            }

            Section {
                Picker("Preference Currency", selection: $viewModel.jobMatchPreferredCurrency) {
                    ForEach(Currency.allCases) { currency in
                        Text("\(currency.displayName) (\(currency.symbol))").tag(currency)
                    }
                }

                TextField("Preferred base min", text: $viewModel.jobMatchPreferredSalaryMinText)

                TextField("Preferred base max", text: $viewModel.jobMatchPreferredSalaryMaxText)

                ForEach(JobMatchWorkMode.allCases) { mode in
                    Toggle(mode.displayName, isOn: Binding(
                        get: { viewModel.isJobMatchWorkModeAllowed(mode) },
                        set: { viewModel.setJobMatchWorkMode(mode, allowed: $0) }
                    ))
                }

                TextField("Preferred locations (comma separated)", text: $viewModel.jobMatchPreferredLocationsText, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("Job Match Preferences")
            } footer: {
                Text("These preferences power salary and location alignment in Job Match scoring. Per-application expected compensation overrides the global salary target.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Analytics")
    }
}

struct AnalyticsSettingsContent: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        SettingsFormSectionCard(
            title: "Dashboard Currency",
            subtitle: "Salary analytics convert compensation into this currency using cached Frankfurter exchange rates.",
            icon: "chart.xyaxis.line"
        ) {
            Picker("Base Currency", selection: $viewModel.analyticsBaseCurrency) {
                ForEach(Currency.allCases) { currency in
                    Text("\(currency.displayName) (\(currency.symbol))").tag(currency)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        SettingsFormSectionCard(
            title: "Job Match Preferences",
            subtitle: "Set the salary and location guardrails used by AI Job Match scoring.",
            icon: "bolt.badge.checkmark"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Preference Currency", selection: $viewModel.jobMatchPreferredCurrency) {
                    ForEach(Currency.allCases) { currency in
                        Text("\(currency.displayName) (\(currency.symbol))").tag(currency)
                    }
                }
                .pickerStyle(.menu)

                HStack(spacing: 10) {
                    TextField("Preferred base min", text: $viewModel.jobMatchPreferredSalaryMinText)
                        .textFieldStyle(.roundedBorder)

                    TextField("Preferred base max", text: $viewModel.jobMatchPreferredSalaryMaxText)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Allowed Work Modes")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        ForEach(JobMatchWorkMode.allCases) { mode in
                            Toggle(mode.displayName, isOn: Binding(
                                get: { viewModel.isJobMatchWorkModeAllowed(mode) },
                                set: { viewModel.setJobMatchWorkMode(mode, allowed: $0) }
                            ))
                            .toggleStyle(.button)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Preferred Locations")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    TextField("Remote, New York, Bengaluru", text: $viewModel.jobMatchPreferredLocationsText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }
            }
        }
    }
}

struct NotificationSettingsContent: View {
    @Bindable var viewModel: SettingsViewModel
    var isPresentedInSheet: Bool = false
    @Query private var applications: [JobApplication]
    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined
    @State private var showPermissionDeniedAlert = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        settingsContent
            .task {
                await refreshPermissionStatusAndSyncIfNeeded()
            }
            .onChange(of: viewModel.notificationsEnabled) { _, isEnabled in
                Task {
                    await handleNotificationsEnabledChange(isEnabled)
                }
            }
            .onChange(of: viewModel.reminderTiming) { _, timing in
                guard viewModel.notificationsEnabled else { return }
                Task {
                    await syncNotificationPreferences(reminderTiming: timing)
                }
            }
            .onChange(of: viewModel.weeklyDigestNotificationsEnabled) { _, _ in
                Task {
                    await syncWeeklyDigestReminder()
                }
            }
            .onChange(of: viewModel.weeklyDigestWeekday) { _, _ in
                Task {
                    await syncWeeklyDigestReminder()
                }
            }
            .onChange(of: viewModel.weeklyDigestHour) { _, _ in
                Task {
                    await syncWeeklyDigestReminder()
                }
            }
            .onChange(of: viewModel.weeklyDigestMinute) { _, _ in
                Task {
                    await syncWeeklyDigestReminder()
                }
            }
            .alert("Notifications Are Disabled", isPresented: $showPermissionDeniedAlert) {
                Button("Open System Settings") {
                    Task { @MainActor in
                        NotificationService.shared.openNotificationSettings()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Allow notifications for Pipeline in system settings to receive follow-up and task reminders.")
            }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            heroContent

            if viewModel.notificationsEnabled {
                reminderTimingContent
                weeklyDigestContent
                applyQueueContent
            } else {
                inactiveStateContent
            }

            permissionContent
        }
    }

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.accent.gradient)
                        .frame(width: 46, height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.20 : 0.10))
                        )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Preferences")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.8)

                        Text("Notifications")
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text("Manage reminders for follow-ups, task due dates, and your optional weekly digest.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 16)

                HStack(spacing: 12) {
                    if isPresentedInSheet {
                        Button("Done") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(DesignSystem.Colors.accent)
                    }

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(viewModel.notificationsEnabled ? "Notifications On" : "Notifications Off")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Toggle("", isOn: $viewModel.notificationsEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(DesignSystem.Colors.accent)
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    summaryBadges
                }

                VStack(alignment: .leading, spacing: 8) {
                    summaryBadges
                }
            }

            if let heroActionTitle {
                Divider()
                    .overlay(.secondary.opacity(0.12))

                HStack(alignment: .center, spacing: 12) {
                    Label(heroActionMessage, systemImage: permissionStatusIcon)
                        .font(.subheadline)
                        .foregroundColor(permissionStatusColor)

                    Spacer(minLength: 12)

                    Button(heroActionTitle) {
                        Task {
                            await performHeroAction()
                        }
                    }
                    .tint(heroActionIsProminent ? DesignSystem.Colors.accent : permissionStatusColor)
                    .modifier(NotificationHeroActionButtonStyle(isProminent: heroActionIsProminent))
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    viewModel.notificationsEnabled
                        ? DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.34 : 0.18)
                        : DesignSystem.Colors.stroke(colorScheme),
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private var summaryBadges: some View {
        NotificationStatusChip(
            icon: permissionStatusIcon,
            title: permissionBadgeTitle,
            tint: permissionStatusColor
        )

        NotificationStatusChip(
            icon: "clock.fill",
            title: viewModel.notificationsEnabled ? reminderCompactSummary : "Reminders paused",
            tint: DesignSystem.Colors.accent
        )

        NotificationStatusChip(
            icon: "chart.line.text.clipboard",
            title: viewModel.weeklyDigestNotificationsEnabled ? weeklyDigestCompactSummary : "Digest off",
            tint: viewModel.weeklyDigestNotificationsEnabled ? DesignSystem.Colors.accent : .secondary
        )

        NotificationStatusChip(
            icon: "bookmark.circle",
            title: "Queue at \(formattedTime(hour: viewModel.applyQueueNotificationHour, minute: viewModel.applyQueueNotificationMinute))",
            tint: DesignSystem.Colors.accent
        )
    }

    private var reminderTimingContent: some View {
        NotificationSettingsSectionCard(
            title: "Reminders",
            subtitle: "Choose when Pipeline should nudge you before a follow-up date or task deadline."
        ) {
            HStack(spacing: 10) {
                ForEach(ReminderTiming.allCases) { timing in
                    NotificationTimingButton(
                        title: reminderTimingTitle(for: timing),
                        subtitle: reminderTimingSubtitle(for: timing),
                        isSelected: viewModel.reminderTiming == timing
                    ) {
                        viewModel.reminderTiming = timing
                    }
                }
            }

            Label(reminderPreviewText, systemImage: "sparkles")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var weeklyDigestContent: some View {
        NotificationSettingsSectionCard(
            title: "Weekly Digest",
            subtitle: "Send a single weekly summary notification when you want a lightweight review of your search."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $viewModel.weeklyDigestNotificationsEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Send Weekly Digest Notification")
                            .font(.subheadline.weight(.semibold))

                        Text(
                            viewModel.weeklyDigestNotificationsEnabled
                                ? weeklyDigestScheduleText
                                : "Disabled. Turn this on to choose a delivery day and time."
                        )
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(DesignSystem.Colors.accent)

                if viewModel.weeklyDigestNotificationsEnabled {
                    HStack(alignment: .top, spacing: 14) {
                        NotificationField(label: "Day") {
                            Picker("Day", selection: $viewModel.weeklyDigestWeekday) {
                                ForEach(weekdayOptions, id: \.value) { option in
                                    Text(option.label).tag(option.value)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        NotificationField(label: "Time") {
                            DatePicker(
                                "Time",
                                selection: weeklyDigestTimeBinding,
                                displayedComponents: .hourAndMinute
                            )
                            #if os(macOS)
                            .datePickerStyle(.field)
                            #endif
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Label(weeklyDigestScheduleText, systemImage: "calendar.badge.clock")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var applyQueueContent: some View {
        NotificationSettingsSectionCard(
            title: "Apply Queue",
            subtitle: "Choose how many jobs Pipeline should line up each day and when to send the morning queue summary."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Stepper(value: $viewModel.applyQueueDailyTarget, in: 1...12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Daily target: \(viewModel.applyQueueDailyTarget) jobs")
                            .font(.subheadline.weight(.semibold))
                        Text("Recommended range: 3-5 jobs per day.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                NotificationField(label: "Morning Reminder") {
                    DatePicker(
                        "Morning Reminder",
                        selection: applyQueueTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                    #if os(macOS)
                    .datePickerStyle(.field)
                    #endif
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var inactiveStateContent: some View {
        NotificationPermissionBanner(
            icon: "bell.slash.fill",
            title: "Notifications are currently off",
            message: "Turn them on to configure reminder timing and optionally deliver a weekly digest notification.",
            tint: .secondary
        )
    }

    private var permissionContent: some View {
        NotificationSettingsSectionCard(
            title: "Permission",
            subtitle: "Keep this visible so you can quickly diagnose why reminders are or are not arriving."
        ) {
            NotificationPermissionBanner(
                icon: permissionStatusIcon,
                title: permissionStatusText,
                message: notificationPermissionFooterText,
                tint: permissionStatusColor
            )
        }
    }

    private var permissionBadgeTitle: String {
        switch permissionStatus {
        case .authorized, .provisional, .ephemeral:
            return "Permission granted"
        case .denied:
            return "Permission blocked"
        case .notDetermined:
            return "Permission pending"
        @unknown default:
            return "Permission unknown"
        }
    }

    private var permissionStatusText: String {
        switch permissionStatus {
        case .authorized, .provisional, .ephemeral:
            return "Notifications are allowed"
        case .denied:
            return "Notifications are blocked in System Settings"
        case .notDetermined:
            return "Notification permission has not been requested yet"
        @unknown default:
            return "Permission status unavailable"
        }
    }

    private var permissionStatusIcon: String {
        switch permissionStatus {
        case .authorized, .provisional, .ephemeral:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        case .notDetermined:
            return "questionmark.circle.fill"
        @unknown default:
            return "exclamationmark.triangle.fill"
        }
    }

    private var permissionStatusColor: Color {
        switch permissionStatus {
        case .authorized, .provisional, .ephemeral:
            return .pipelineGreen
        case .denied:
            return .pipelineOrange
        case .notDetermined:
            return .secondary
        @unknown default:
            return .secondary
        }
    }

    private var notificationPermissionFooterText: String {
        switch permissionStatus {
        case .authorized, .provisional, .ephemeral:
            return "Pipeline can send reminders and weekly digest notifications."
        case .denied:
            return "Reminders are blocked until you allow notifications for Pipeline in System Settings."
        case .notDetermined:
            return "Allow notifications when prompted to receive reminders and the optional weekly digest."
        @unknown default:
            return "Check your system settings if reminders are not arriving."
        }
    }

    private var reminderCompactSummary: String {
        switch viewModel.reminderTiming {
        case .dayBefore:
            return "Day before"
        case .morningOf:
            return "9:00 AM same day"
        case .both:
            return "Day before + 9:00 AM"
        }
    }

    private var reminderPreviewText: String {
        switch viewModel.reminderTiming {
        case .dayBefore:
            return "Pipeline will remind you one day before each follow-up date and task deadline."
        case .morningOf:
            return "Pipeline will remind you at 9:00 AM on the day each follow-up date or task is due."
        case .both:
            return "Pipeline will send a reminder the day before and again at 9:00 AM on the due date."
        }
    }

    private var weeklyDigestCompactSummary: String {
        "\(weekdayLabel(for: viewModel.weeklyDigestWeekday)) at \(formattedTime(hour: viewModel.weeklyDigestHour, minute: viewModel.weeklyDigestMinute))"
    }

    private var weeklyDigestScheduleText: String {
        "Every \(weeklyDigestCompactSummary)"
    }

    private var heroActionTitle: String? {
        switch permissionStatus {
        case .denied:
            return "Open System Settings"
        case .notDetermined:
            return "Allow Notifications"
        default:
            return nil
        }
    }

    private var heroActionMessage: String {
        switch permissionStatus {
        case .denied:
            return "Pipeline cannot deliver reminders until notifications are enabled in System Settings."
        case .notDetermined:
            return "Allow notifications now so reminders can be delivered when you turn them on."
        default:
            return ""
        }
    }

    private var heroActionIsProminent: Bool {
        permissionStatus == .denied
    }

    private var weekdayOptions: [(value: Int, label: String)] {
        Calendar.current.weekdaySymbols.enumerated().map { index, label in
            (index + 1, label)
        }
    }

    private var weeklyDigestTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = viewModel.weeklyDigestHour
                components.minute = viewModel.weeklyDigestMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                viewModel.weeklyDigestHour = Calendar.current.component(.hour, from: newValue)
                viewModel.weeklyDigestMinute = Calendar.current.component(.minute, from: newValue)
            }
        )
    }

    private var applyQueueTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = viewModel.applyQueueNotificationHour
                components.minute = viewModel.applyQueueNotificationMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                viewModel.applyQueueNotificationHour = Calendar.current.component(.hour, from: newValue)
                viewModel.applyQueueNotificationMinute = Calendar.current.component(.minute, from: newValue)
            }
        )
    }

    @MainActor
    private func refreshPermissionStatusAndSyncIfNeeded() async {
        permissionStatus = await NotificationService.shared.checkPermissionStatus()

        guard viewModel.notificationsEnabled else { return }
        await syncNotificationPreferences(reminderTiming: viewModel.reminderTiming)
    }

    @MainActor
    private func requestPermissionFromAction() async {
        let updatedStatus = await NotificationService.shared.authorizationStatusAfterPromptIfNeeded()
        permissionStatus = updatedStatus

        if NotificationService.shared.isPermissionGranted(updatedStatus) {
            await syncNotificationPreferences(reminderTiming: viewModel.reminderTiming)
        } else {
            showPermissionDeniedAlert = true
        }
    }

    @MainActor
    private func handleNotificationsEnabledChange(_ isEnabled: Bool) async {
        if isEnabled {
            let updatedStatus = await NotificationService.shared.authorizationStatusAfterPromptIfNeeded()
            permissionStatus = updatedStatus

            guard NotificationService.shared.isPermissionGranted(updatedStatus) else {
                viewModel.notificationsEnabled = false
                NotificationService.shared.removeAllNotifications()
                showPermissionDeniedAlert = true
                return
            }

            await syncNotificationPreferences(reminderTiming: viewModel.reminderTiming)
        } else {
            NotificationService.shared.removeAllNotifications()
            permissionStatus = await NotificationService.shared.checkPermissionStatus()
        }
    }

    @MainActor
    private func performHeroAction() async {
        switch permissionStatus {
        case .denied:
            NotificationService.shared.openNotificationSettings()
        case .notDetermined:
            await requestPermissionFromAction()
        default:
            break
        }
    }

    @MainActor
    private func syncNotificationPreferences(reminderTiming: ReminderTiming) async {
        await NotificationService.shared.syncReminderState(
            for: applications,
            notificationsEnabled: true,
            timing: reminderTiming
        )
        await syncWeeklyDigestReminder()
    }

    @MainActor
    private func syncWeeklyDigestReminder() async {
        await NotificationService.shared.syncWeeklyDigestReminder(
            schedule: viewModel.weeklyDigestSchedule,
            notificationsEnabled: viewModel.notificationsEnabled,
            digestNotificationsEnabled: viewModel.weeklyDigestNotificationsEnabled
        )
    }

    private func reminderTimingTitle(for timing: ReminderTiming) -> String {
        switch timing {
        case .dayBefore:
            return "Day Before"
        case .morningOf:
            return "Morning Of"
        case .both:
            return "Both"
        }
    }

    private func reminderTimingSubtitle(for timing: ReminderTiming) -> String {
        switch timing {
        case .dayBefore:
            return "24 hours earlier"
        case .morningOf:
            return "9:00 AM same day"
        case .both:
            return "Early + same-day"
        }
    }

    private func weekdayLabel(for weekday: Int) -> String {
        weekdayOptions.first(where: { $0.value == weekday })?.label ?? "Sunday"
    }

    private func formattedTime(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct NotificationSettingsSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DesignSystem.Colors.surface(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }
}

private struct NotificationStatusChip: View {
    let icon: String
    let title: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))

            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(tint.opacity(colorScheme == .dark ? 0.14 : 0.08))
        )
        .overlay(
            Capsule()
                .stroke(tint.opacity(colorScheme == .dark ? 0.28 : 0.16), lineWidth: 1)
        )
    }
}

private struct NotificationHeroActionButtonStyle: ViewModifier {
    let isProminent: Bool

    func body(content: Content) -> some View {
        Group {
            if isProminent {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
        }
    }
}

private struct NotificationTimingButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isSelected
                            ? DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.24 : 0.12)
                            : DesignSystem.Colors.inputBackground(colorScheme)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected
                            ? DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.60 : 0.24)
                            : DesignSystem.Colors.stroke(colorScheme),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct NotificationField<Content: View>: View {
    let label: String
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            content
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DesignSystem.Colors.inputBackground(colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NotificationPermissionBanner: View {
    let icon: String
    let title: String
    let message: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(colorScheme == .dark ? 0.14 : 0.08))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? 0.10 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(colorScheme == .dark ? 0.24 : 0.14), lineWidth: 1)
        )
    }
}

#Preview {
    let settingsViewModel = SettingsViewModel()
    SettingsView(viewModel: settingsViewModel)
        .environment(AppLockCoordinator(settingsViewModel: settingsViewModel))
}
