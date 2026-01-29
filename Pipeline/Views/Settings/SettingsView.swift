import SwiftUI

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        #if os(macOS)
        ScrollView {
            VStack(spacing: 24) {
                // Appearance Section
                SettingsSection(title: "Appearance", icon: "paintbrush") {
                    AppearanceSettingsContent(viewModel: viewModel)
                }

                // AI Provider Section
                SettingsSection(title: "AI Provider", icon: "brain") {
                    AIProviderSettingsContent(viewModel: viewModel)
                }

                // Notifications Section
                SettingsSection(title: "Notifications", icon: "bell") {
                    NotificationSettingsContent(viewModel: viewModel)
                }

                // About Section
                SettingsSection(title: "About", icon: "info.circle") {
                    AboutSettingsContent()
                }
            }
            .padding(24)
        }
        .frame(width: 500, height: 600)
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
                }

                Section {
                    Link(destination: URL(string: "https://github.com")!) {
                        Label("Report an Issue", systemImage: "exclamationmark.bubble")
                    }

                    Link(destination: URL(string: "https://github.com")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
        #endif
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let content: () -> Content

    init(title: String, icon: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content
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

            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 16, elevated: true, shadow: false)
    }
}

struct AboutSettingsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Link(destination: URL(string: "https://github.com")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.bubble")
                        Text("Report an Issue")
                    }
                    .font(.subheadline)
                }

                Spacer()

                Link(destination: URL(string: "https://github.com")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.raised")
                        Text("Privacy Policy")
                    }
                    .font(.subheadline)
                }
            }

            Divider()

            HStack {
                Text("Version")
                    .foregroundColor(.secondary)
                Spacer()
                Text("1.0.0")
                    .font(.subheadline)
            }
        }
    }
}

struct NotificationSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Enable Notifications", isOn: $viewModel.notificationsEnabled)
            } footer: {
                Text("Get reminders for follow-up dates you set on job applications.")
            }

            if viewModel.notificationsEnabled {
                Section("Reminder Timing") {
                    Picker("When to Remind", selection: $viewModel.reminderTiming) {
                        ForEach(ReminderTiming.allCases) { timing in
                            Text(timing.rawValue).tag(timing)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section {
                    Button("Request Permission") {
                        Task {
                            await NotificationService.shared.requestPermission()
                        }
                    }
                } footer: {
                    Text("If notifications aren't working, tap here to request permission again.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Notifications")
    }
}

struct NotificationSettingsContent: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Enable Notifications", isOn: $viewModel.notificationsEnabled)

            if viewModel.notificationsEnabled {
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

                Button("Request Permission") {
                    Task {
                        await NotificationService.shared.requestPermission()
                    }
                }
                .font(.subheadline)
            }

            Text("Get reminders for follow-up dates you set on job applications.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    SettingsView()
}
