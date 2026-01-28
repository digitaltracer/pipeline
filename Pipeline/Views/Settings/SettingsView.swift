import SwiftUI

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        #if os(macOS)
        TabView {
            AppearanceSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            AIProviderSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("AI Provider", systemImage: "brain")
                }

            NotificationSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
        }
        .frame(width: 450, height: 350)
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

#Preview {
    SettingsView()
}
