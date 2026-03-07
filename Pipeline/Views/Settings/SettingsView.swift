import SwiftUI
import SwiftData
import UserNotifications
import PipelineKit

#if os(macOS)
private enum SettingsCategory: String, CaseIterable, Identifiable {
    case appearance
    case aiProvider
    case allApplications
    case analytics
    case notifications
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
        case .security: return "lock.shield.fill"
        case .sync: return "icloud.fill"
        case .about: return "info.circle.fill"
        }
    }
}
#endif

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    var isPresentedInSheet: Bool = false
    @Environment(\.dismiss) private var dismiss

    #if os(macOS)
    @State private var selectedCategory: SettingsCategory = .appearance
    @Environment(\.colorScheme) private var colorScheme
    #endif

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
            .navigationTitle("Settings")
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
        case .security:
            SecuritySettingsContent(viewModel: viewModel)
        case .sync:
            SyncSettingsContent(viewModel: viewModel)
        case .about:
            AboutSettingsContent()
        }
    }
    #endif
}

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
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    await NotificationService.shared.syncReminderState(
                        for: applications,
                        notificationsEnabled: true,
                        timing: timing
                    )
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

    @MainActor
    private func refreshPermissionStatusAndSyncIfNeeded() async {
        permissionStatus = await NotificationService.shared.checkPermissionStatus()

        guard viewModel.notificationsEnabled else { return }
        await NotificationService.shared.syncReminderState(
            for: applications,
            notificationsEnabled: true,
            timing: viewModel.reminderTiming
        )
    }

    @MainActor
    private func requestPermissionFromAction() async {
        let updatedStatus = await NotificationService.shared.authorizationStatusAfterPromptIfNeeded()
        permissionStatus = updatedStatus

        if NotificationService.shared.isPermissionGranted(updatedStatus) {
            await NotificationService.shared.syncReminderState(
                for: applications,
                notificationsEnabled: true,
                timing: viewModel.reminderTiming
            )
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

            await NotificationService.shared.syncReminderState(
                for: applications,
                notificationsEnabled: true,
                timing: viewModel.reminderTiming
            )
        } else {
            NotificationService.shared.removeAllNotifications()
            permissionStatus = await NotificationService.shared.checkPermissionStatus()
        }
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
    }
}

struct NotificationSettingsContent: View {
    @Bindable var viewModel: SettingsViewModel
    @Query private var applications: [JobApplication]
    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined
    @State private var showPermissionDeniedAlert = false

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
                    await NotificationService.shared.syncReminderState(
                        for: applications,
                        notificationsEnabled: true,
                        timing: timing
                    )
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
        VStack(alignment: .leading, spacing: 14) {
            SettingsFormSectionCard(
                title: "Notifications",
                subtitle: "Get reminders for follow-up dates and task due dates you set on job applications.",
                icon: "bell.badge.fill"
            ) {
                Toggle("Enable Notifications", isOn: $viewModel.notificationsEnabled)
                    .tint(DesignSystem.Colors.accent)
            }

            if viewModel.notificationsEnabled {
                reminderTimingContent
                permissionContent
            }
        }
    }

    private var reminderTimingContent: some View {
        SettingsFormSectionCard(
            title: "Reminder Timing",
            subtitle: "Choose when reminders should arrive before a follow-up date.",
            icon: "clock.fill"
        ) {
            Picker("When to Remind", selection: $viewModel.reminderTiming) {
                ForEach(ReminderTiming.allCases) { timing in
                    Text(timing.rawValue).tag(timing)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var permissionContent: some View {
        SettingsFormSectionCard(
            title: "Notification Permission",
            subtitle: notificationPermissionFooterText,
            icon: "checkmark.shield.fill"
        ) {
            Label(permissionStatusText, systemImage: permissionStatusIcon)
                .foregroundColor(permissionStatusColor)

            if permissionStatus == .denied {
                Button("Open System Settings") {
                    Task { @MainActor in
                        NotificationService.shared.openNotificationSettings()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
            } else if permissionStatus == .notDetermined {
                Button("Allow Notifications") {
                    Task {
                        await requestPermissionFromAction()
                    }
                }
                .buttonStyle(.bordered)
            }
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
            return "Get reminders for follow-up dates and task due dates you set on job applications."
        @unknown default:
            return "Check your system settings if reminders are not arriving."
        }
    }

    @MainActor
    private func refreshPermissionStatusAndSyncIfNeeded() async {
        permissionStatus = await NotificationService.shared.checkPermissionStatus()

        guard viewModel.notificationsEnabled else { return }
        await NotificationService.shared.syncReminderState(
            for: applications,
            notificationsEnabled: true,
            timing: viewModel.reminderTiming
        )
    }

    @MainActor
    private func requestPermissionFromAction() async {
        let updatedStatus = await NotificationService.shared.authorizationStatusAfterPromptIfNeeded()
        permissionStatus = updatedStatus

        if NotificationService.shared.isPermissionGranted(updatedStatus) {
            await NotificationService.shared.syncReminderState(
                for: applications,
                notificationsEnabled: true,
                timing: viewModel.reminderTiming
            )
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

            await NotificationService.shared.syncReminderState(
                for: applications,
                notificationsEnabled: true,
                timing: viewModel.reminderTiming
            )
        } else {
            NotificationService.shared.removeAllNotifications()
            permissionStatus = await NotificationService.shared.checkPermissionStatus()
        }
    }
}

#Preview {
    let settingsViewModel = SettingsViewModel()
    SettingsView(viewModel: settingsViewModel)
        .environment(AppLockCoordinator(settingsViewModel: settingsViewModel))
}
