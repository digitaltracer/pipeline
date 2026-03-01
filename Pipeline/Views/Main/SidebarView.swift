import SwiftUI
import PipelineKit

#if os(macOS)
import AppKit

struct SidebarView: View {
    @Binding var selectedFilter: SidebarFilter
    @Binding var showingAddApplication: Bool
    @Binding var showingSettings: Bool
    @Binding var showingDashboard: Bool
    @Binding var showingResume: Bool
    @Binding var showingCostCenter: Bool
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
                Spacer(minLength: 0)
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
            .sidebarHandCursor()
            .tint(DesignSystem.Colors.accent)
            .controlSize(.large)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            // Filter List
            List {
                Section {
                    // Dashboard item
                    Button {
                        showingDashboard = true
                        showingResume = false
                        showingCostCenter = false
                    } label: {
                        HStack {
                            Image(systemName: "chart.bar.xaxis")
                                .foregroundColor(showingDashboard ? .white : .indigo)
                                .frame(width: 20)

                            Text("Dashboard")
                                .foregroundColor(showingDashboard ? .white : .primary)

                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(showingDashboard ? DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.85 : 1.0) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .sidebarHandCursor()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    ForEach(SidebarFilter.allCases) { filter in
                        Button {
                            showingDashboard = false
                            showingResume = false
                            showingCostCenter = false
                            selectedFilter = filter
                        } label: {
                            SidebarFilterRow(
                                filter: filter,
                                count: statusCounts[filter] ?? 0,
                                isSelected: !showingDashboard && !showingResume && !showingCostCenter && selectedFilter == filter
                            )
                        }
                        .buttonStyle(.plain)
                        .sidebarHandCursor()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
                .padding(.horizontal)

            VStack(spacing: 4) {
                Button {
                    showingDashboard = false
                    showingResume = true
                    showingCostCenter = false
                } label: {
                    utilityRow(
                        title: "Resume",
                        icon: "doc.text",
                        isSelected: showingResume,
                        accentColor: .teal
                    )
                }
                .buttonStyle(.plain)
                .sidebarHandCursor()

                Button {
                    showingDashboard = false
                    showingResume = false
                    showingCostCenter = true
                } label: {
                    utilityRow(
                        title: "Cost Center",
                        icon: "dollarsign.arrow.circlepath",
                        isSelected: showingCostCenter,
                        accentColor: .mint
                    )
                }
                .buttonStyle(.plain)
                .sidebarHandCursor()

                Button {
                    showingSettings = true
                } label: {
                    utilityRow(
                        title: "Settings",
                        icon: "gearshape",
                        isSelected: false,
                        accentColor: .secondary
                    )
                }
                .buttonStyle(.plain)
                .sidebarHandCursor()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(DesignSystem.Colors.sidebarBackground(colorScheme))
    }

    private func utilityRow(
        title: String,
        icon: String,
        isSelected: Bool,
        accentColor: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isSelected ? .white : accentColor)
                .frame(width: 20, height: 20)

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(isSelected ? .white : .primary)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.85 : 1.0) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

private extension View {
    func sidebarHandCursor() -> some View {
        onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
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
        showingDashboard: .constant(false),
        showingResume: .constant(false),
        showingCostCenter: .constant(false),
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
    @Binding var showingDashboard: Bool
    @Binding var showingResume: Bool
    @Binding var showingCostCenter: Bool
    let statusCounts: [SidebarFilter: Int]
    @Bindable var settingsViewModel: SettingsViewModel

    var body: some View {
        EmptyView()
    }
}
#endif
