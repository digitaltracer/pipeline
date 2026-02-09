import SwiftUI

#if os(macOS)
struct SidebarView: View {
    @Binding var selectedFilter: SidebarFilter
    @Binding var showingAddApplication: Bool
    @Binding var showingSettings: Bool
    let statusCounts: [SidebarFilter: Int]
    @Bindable var settingsViewModel: SettingsViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // App Header
            HStack(spacing: 12) {
                // Blue briefcase icon in rounded square
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DesignSystem.Colors.accent)
                        .frame(width: 44, height: 44)

                    Image(systemName: "building.2.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Pipeline")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Track your applications")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Theme toggle icon
                Button {
                    withAnimation {
                        cycleTheme()
                    }
                } label: {
                    Image(systemName: settingsViewModel.appearanceMode.icon)
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .background(DesignSystem.Colors.surfaceElevated(colorScheme))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)

            // New Application Button
            Button {
                showingAddApplication = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("New Application")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accent)
            .controlSize(.large)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            // Filter List
            List {
                Section {
                    ForEach(SidebarFilter.allCases) { filter in
                        Button {
                            selectedFilter = filter
                        } label: {
                            SidebarFilterRow(
                                filter: filter,
                                count: statusCounts[filter] ?? 0,
                                isSelected: selectedFilter == filter
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
                .padding(.horizontal)

            Button {
                showingSettings = true
            } label: {
                ZStack {
                    Text("Settings")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    HStack {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DesignSystem.Colors.sidebarBackground(colorScheme))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(DesignSystem.Colors.sidebarBackground(colorScheme))
    }

    private func cycleTheme() {
        switch settingsViewModel.appearanceMode {
        case .system:
            settingsViewModel.appearanceMode = .light
        case .light:
            settingsViewModel.appearanceMode = .dark
        case .dark:
            settingsViewModel.appearanceMode = .system
        }
    }
}

struct SidebarFilterRow: View {
    let filter: SidebarFilter
    let count: Int
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            Image(systemName: filter.icon)
                .foregroundColor(isSelected ? .white : filter.color)
                .frame(width: 20)

            Text(filter.displayName)
                .foregroundColor(isSelected ? .white : .primary)

            Spacer()

            Text("\(count)")
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white.opacity(0.18) : DesignSystem.Colors.surfaceElevated(colorScheme))
                )
                .foregroundColor(isSelected ? .white : .secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.85 : 1.0) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

#Preview {
    SidebarView(
        selectedFilter: .constant(.all),
        showingAddApplication: .constant(false),
        showingSettings: .constant(false),
        statusCounts: [
            .all: 25,
            .saved: 5,
            .applied: 10,
            .interviewing: 4,
            .offered: 2,
            .rejected: 3,
            .archived: 1
        ],
        settingsViewModel: SettingsViewModel()
    )
    .frame(width: 250)
}
#else
// iOS does not use the macOS sidebar layout (it uses a NavigationStack entry point),
// but the type must exist for the shared target to compile.
struct SidebarView: View {
    @Binding var selectedFilter: SidebarFilter
    @Binding var showingAddApplication: Bool
    @Binding var showingSettings: Bool
    let statusCounts: [SidebarFilter: Int]
    @Bindable var settingsViewModel: SettingsViewModel

    var body: some View {
        EmptyView()
    }
}
#endif
