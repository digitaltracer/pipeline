import SwiftUI
import PipelineKit

#if os(macOS)
import AppKit

struct SidebarView: View {
    @Binding var selectedDestination: MainDestination
    @Binding var showingAddApplication: Bool
    @Binding var showingAddContact: Bool
    @Binding var showingSettings: Bool
    let statusCounts: [SidebarFilter: Int]
    let upcomingCount: Int
    @Bindable var settingsViewModel: SettingsViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DesignSystem.Colors.accent)
                        .frame(width: 44, height: 44)

                    Image(systemName: selectedDestination == .contacts ? "person.2.fill" : "building.2.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Pipeline")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(selectedDestination == .contacts ? "Manage your people" : "Track your applications")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)

            Button {
                switch selectedDestination {
                case .contacts:
                    showingAddContact = true
                default:
                    showingAddApplication = true
                }
            } label: {
                HStack {
                    Image(systemName: selectedDestination == .contacts ? "person.badge.plus" : "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text(selectedDestination == .contacts ? "New Contact" : "New Application")
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

            List {
                Section {
                    destinationButton(
                        title: "Dashboard",
                        icon: "chart.bar.xaxis",
                        isSelected: selectedDestination == .dashboard,
                        accentColor: .indigo
                    ) {
                        selectedDestination = .dashboard
                    }

                    destinationButton(
                        title: "Weekly Digest",
                        icon: "chart.line.text.clipboard",
                        isSelected: selectedDestination == .weeklyDigest,
                        accentColor: .blue
                    ) {
                        selectedDestination = .weeklyDigest
                    }

                    destinationButton(
                        title: "Upcoming",
                        icon: "calendar.badge.clock",
                        isSelected: selectedDestination == .upcoming,
                        accentColor: .orange,
                        count: upcomingCount
                    ) {
                        selectedDestination = .upcoming
                    }
                }

                Section {
                    ForEach(SidebarFilter.allCases) { filter in
                        Button {
                            selectedDestination = .applications(filter)
                        } label: {
                            SidebarFilterRow(
                                filter: filter,
                                count: statusCounts[filter] ?? 0,
                                isSelected: selectedDestination == .applications(filter)
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
                destinationUtilityRow(
                    title: "Contacts",
                    icon: "person.2",
                    isSelected: selectedDestination == .contacts,
                    accentColor: .cyan
                ) {
                    selectedDestination = .contacts
                }

                destinationUtilityRow(
                    title: "Resume",
                    icon: "doc.text",
                    isSelected: selectedDestination == .resume,
                    accentColor: .teal
                ) {
                    selectedDestination = .resume
                }

                destinationUtilityRow(
                    title: "Cost Center",
                    icon: "dollarsign.arrow.circlepath",
                    isSelected: selectedDestination == .costCenter,
                    accentColor: .mint
                ) {
                    selectedDestination = .costCenter
                }

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

    private func destinationButton(
        title: String,
        icon: String,
        isSelected: Bool,
        accentColor: Color,
        count: Int? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            utilityRow(
                title: title,
                icon: icon,
                isSelected: isSelected,
                accentColor: accentColor,
                count: count
            )
        }
        .buttonStyle(.plain)
        .sidebarHandCursor()
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func destinationUtilityRow(
        title: String,
        icon: String,
        isSelected: Bool,
        accentColor: Color,
        count: Int? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            utilityRow(
                title: title,
                icon: icon,
                isSelected: isSelected,
                accentColor: accentColor,
                count: count
            )
        }
        .buttonStyle(.plain)
        .sidebarHandCursor()
    }

    private func utilityRow(
        title: String,
        icon: String,
        isSelected: Bool,
        accentColor: Color,
        count: Int? = nil
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

            if let count, count > 0 {
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
        selectedDestination: .constant(.applications(.all)),
        showingAddApplication: .constant(false),
        showingAddContact: .constant(false),
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
        upcomingCount: 6,
        settingsViewModel: SettingsViewModel()
    )
    .frame(width: 250)
}
#else
struct SidebarView: View {
    @Binding var selectedDestination: MainDestination
    @Binding var showingAddApplication: Bool
    @Binding var showingAddContact: Bool
    @Binding var showingSettings: Bool
    let statusCounts: [SidebarFilter: Int]
    let upcomingCount: Int
    @Bindable var settingsViewModel: SettingsViewModel

    var body: some View {
        EmptyView()
    }
}
#endif
