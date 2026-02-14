import SwiftUI
import SwiftData
import UserNotifications

#if os(macOS)
private enum SettingsCategory: String, CaseIterable, Identifiable {
    case appearance
    case aiProvider
    case notifications
    case sync
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .aiProvider: return "AI Provider"
        case .notifications: return "Notifications"
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
        case .notifications:
            return "Follow-up reminder behavior"
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
        case .notifications: return "bell.badge.fill"
        case .sync: return "icloud.fill"
        case .about: return "info.circle.fill"
        }
    }
}
#endif

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    var isPresentedInSheet: Bool = false

    #if os(macOS)
    @State private var selectedCategory: SettingsCategory = .appearance
    @Environment(\.dismiss) private var dismiss
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
        .frame(minWidth: 920, minHeight: 640)
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
                        NotificationSettingsView(viewModel: viewModel)
                    } label: {
                        Label("Notifications", systemImage: "bell")
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

                    if let privacyURL = URL(string: Constants.URLs.privacyPolicy) {
                        Link(destination: privacyURL) {
                            Label("Privacy Policy", systemImage: "hand.raised")
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
        }
        #endif
    }

    #if os(macOS)
    private var settingsNavigationRail: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Customize Pipeline for your workflow.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 8)

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
        .padding(20)
        .frame(width: 260, alignment: .topLeading)
        .background(DesignSystem.Colors.sidebarBackground(colorScheme))
    }

    private var settingsDetailPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(selectedCategory.title, systemImage: selectedCategory.icon)
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text(selectedCategory.subtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if isPresentedInSheet {
                        Button("Done") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accent)
                    }
                }
                .padding(20)
                .appCard(cornerRadius: 16, elevated: true, shadow: false)

                SettingsPanelCard(title: selectedCategory.title, icon: selectedCategory.icon) {
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
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose how the app looks while you track applications.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                AppearanceSettingsContent(viewModel: viewModel)
            }
        case .aiProvider:
            VStack(alignment: .leading, spacing: 12) {
                Text("Select your provider, model, and secure API key.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                AIProviderSettingsContent(viewModel: viewModel)
            }
        case .notifications:
            VStack(alignment: .leading, spacing: 12) {
                Text("Control reminders for follow-ups and interviews.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                NotificationSettingsContent(viewModel: viewModel)
            }
        case .sync:
            VStack(alignment: .leading, spacing: 12) {
                Text("Control whether application data syncs through your iCloud account.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                SyncSettingsContent(viewModel: viewModel)
            }
        case .about:
            VStack(alignment: .leading, spacing: 12) {
                Text("Need help or want to share feedback?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                AboutSettingsContent()
            }
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
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.22 : 0.14)
                            : Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected
                            ? DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.45 : 0.25)
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
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.accent)
                Text(title)
                    .font(.headline)
            }

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 16, elevated: true, shadow: false)
    }
}
#endif

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

            if let privacyURL = URL(string: Constants.URLs.privacyPolicy) {
                Link(destination: privacyURL) {
                    SettingsLinkRow(
                        title: "Privacy Policy",
                        subtitle: "Review how your data is handled.",
                        icon: "hand.raised"
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
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Enable iCloud Sync", isOn: $viewModel.cloudSyncEnabled)
                .disabled(!viewModel.cloudSyncSupported)

            if viewModel.cloudSyncSupported {
                Text("When enabled, Pipeline syncs application data using your iCloud account.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("iCloud Sync is unavailable in this build configuration.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Label(
                viewModel.cloudSyncEnabledAtLaunch
                    ? "Current mode: iCloud sync is active."
                    : "Current mode: local-only storage.",
                systemImage: viewModel.cloudSyncEnabledAtLaunch ? "checkmark.icloud.fill" : "internaldrive.fill"
            )
            .font(.subheadline)

            if viewModel.cloudSyncNeedsRestart {
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
                    await NotificationService.shared.syncFollowUpReminders(
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
                Text("Allow notifications for Pipeline in system settings to receive follow-up reminders.")
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
            Text("Get reminders for follow-up dates you set on job applications.")
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
            return "Pipeline can send reminders for follow-up dates."
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
        await NotificationService.shared.syncFollowUpReminders(
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
            await NotificationService.shared.syncFollowUpReminders(
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

            await NotificationService.shared.syncFollowUpReminders(
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
                    await NotificationService.shared.syncFollowUpReminders(
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
                Text("Allow notifications for Pipeline in system settings to receive follow-up reminders.")
            }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Enable Notifications", isOn: $viewModel.notificationsEnabled)

            if viewModel.notificationsEnabled {
                reminderTimingContent
                permissionContent
            }

            Text(notificationPermissionFooterText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var reminderTimingContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reminder Timing")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Picker("When to Remind", selection: $viewModel.reminderTiming) {
                ForEach(ReminderTiming.allCases) { timing in
                    Text(timing.rawValue).tag(timing)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var permissionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(permissionStatusText, systemImage: permissionStatusIcon)
                .foregroundColor(permissionStatusColor)

            if permissionStatus == .denied {
                Button("Open System Settings") {
                    Task { @MainActor in
                        NotificationService.shared.openNotificationSettings()
                    }
                }
                .font(.subheadline)
            } else if permissionStatus == .notDetermined {
                Button("Allow Notifications") {
                    Task {
                        await requestPermissionFromAction()
                    }
                }
                .font(.subheadline)
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
            return "Pipeline can send reminders for follow-up dates."
        case .denied:
            return "Notifications are blocked. Open system settings to enable them for Pipeline."
        case .notDetermined:
            return "Get reminders for follow-up dates you set on job applications."
        @unknown default:
            return "Check your system settings if reminders are not arriving."
        }
    }

    @MainActor
    private func refreshPermissionStatusAndSyncIfNeeded() async {
        permissionStatus = await NotificationService.shared.checkPermissionStatus()

        guard viewModel.notificationsEnabled else { return }
        await NotificationService.shared.syncFollowUpReminders(
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
            await NotificationService.shared.syncFollowUpReminders(
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

            await NotificationService.shared.syncFollowUpReminders(
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
    SettingsView(viewModel: SettingsViewModel())
}
