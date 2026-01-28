import SwiftUI

struct SidebarView: View {
    @Binding var selectedFilter: SidebarFilter
    @Binding var showingAddApplication: Bool
    let statusCounts: [SidebarFilter: Int]

    var body: some View {
        VStack(spacing: 0) {
            // App Header
            VStack(spacing: 8) {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue.gradient)

                Text("Pipeline")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .padding(.vertical, 20)

            Divider()
                .padding(.horizontal)

            // New Application Button
            Button {
                showingAddApplication = true
            } label: {
                Label("New Application", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.top, 16)

            // Filter List
            List(selection: $selectedFilter) {
                Section {
                    ForEach(SidebarFilter.allCases) { filter in
                        SidebarFilterRow(
                            filter: filter,
                            count: statusCounts[filter] ?? 0,
                            isSelected: selectedFilter == filter
                        )
                        .tag(filter)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
                .padding(.horizontal)

            // Settings Link
            #if os(macOS)
            SettingsLink {
                Label("Settings", systemImage: "gear")
                    .padding(.vertical, 8)
                    .padding(.horizontal)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
            #else
            NavigationLink {
                SettingsView()
            } label: {
                Label("Settings", systemImage: "gear")
                    .padding(.vertical, 8)
                    .padding(.horizontal)
            }
            .padding(.bottom, 16)
            #endif
        }
    }
}

struct SidebarFilterRow: View {
    let filter: SidebarFilter
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: filter.icon)
                .foregroundColor(isSelected ? .white : filter.color)
                .frame(width: 20)

            Text(filter.displayName)
                .foregroundColor(isSelected ? .white : .primary)

            Spacer()

            Text("\(count)")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.1))
                )
                .foregroundColor(isSelected ? .white : .secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview {
    SidebarView(
        selectedFilter: .constant(.all),
        showingAddApplication: .constant(false),
        statusCounts: [
            .all: 25,
            .saved: 5,
            .applied: 10,
            .interviewing: 4,
            .offered: 2,
            .rejected: 3,
            .archived: 1
        ]
    )
    .frame(width: 250)
}
