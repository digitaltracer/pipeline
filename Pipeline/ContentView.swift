import SwiftUI
import SwiftData
import PipelineKit

struct ContentView: View {
    @Query(sort: \JobApplication.updatedAt, order: .reverse) private var applications: [JobApplication]
    @Query(sort: \Contact.updatedAt, order: .reverse) private var contacts: [Contact]
    @State private var selectedDestination: MainDestination = .applications(.all)
    @State private var selectedApplication: JobApplication?
    @State private var selectedContact: Contact?
    @State private var showingAddApplication = false
    @State private var showingAddContact = false
    @State private var searchText = ""
    @Bindable var settingsViewModel: SettingsViewModel

    private var filteredApplications: [JobApplication] {
        let visibleApplications: [JobApplication]
        if let filter = selectedDestination.applicationFilter, filter != .all, let status = filter.status {
            visibleApplications = applications.filter { $0.status == status }
        } else {
            visibleApplications = applications.filter(settingsViewModel.shouldIncludeInAllApplications)
        }

        guard !searchText.isEmpty else { return visibleApplications }
        let lowercasedSearch = searchText.lowercased()
        return visibleApplications.filter { app in
            app.companyName.lowercased().contains(lowercasedSearch) ||
            app.role.lowercased().contains(lowercasedSearch) ||
            app.location.lowercased().contains(lowercasedSearch)
        }
    }

    private var filteredContacts: [Contact] {
        guard !searchText.isEmpty else { return contacts }
        let lowercasedSearch = searchText.lowercased()
        return contacts.filter { contact in
            contact.fullName.lowercased().contains(lowercasedSearch) ||
            (contact.companyName?.lowercased().contains(lowercasedSearch) ?? false) ||
            (contact.email?.lowercased().contains(lowercasedSearch) ?? false)
        }
    }

    var body: some View {
        #if os(macOS)
        MainView(
            selectedDestination: $selectedDestination,
            selectedApplication: $selectedApplication,
            selectedContact: $selectedContact,
            showingAddApplication: $showingAddApplication,
            showingAddContact: $showingAddContact,
            searchText: $searchText,
            settingsViewModel: settingsViewModel
        )
        .preferredColorScheme(settingsViewModel.getColorScheme())
        .appWindowBackground()
        .task {
            prewarmJSONEditorIfNeeded()
        }
        #else
        NavigationStack {
            Group {
                switch selectedDestination {
                case .dashboard:
                    DashboardView(settingsViewModel: settingsViewModel)
                case .contacts:
                    ContactsListView(
                        contacts: filteredContacts,
                        selectedContact: $selectedContact,
                        searchText: $searchText,
                        onAddContact: {
                            showingAddContact = true
                        }
                    )
                case .resume:
                    ResumeWorkspaceView()
                case .costCenter:
                    CostCenterView()
                case .applications:
                    ApplicationListView(
                        applications: filteredApplications,
                        selectedApplication: $selectedApplication,
                        searchText: $searchText
                    )
                }
            }
            .navigationTitle(selectedDestination.title)
            .searchable(text: $searchText)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Dashboard") { selectedDestination = .dashboard }
                        Divider()
                        ForEach(SidebarFilter.allCases) { filter in
                            Button(filter.displayName) {
                                selectedDestination = .applications(filter)
                            }
                        }
                        Divider()
                        Button("Contacts") { selectedDestination = .contacts }
                        Button("Resume") { selectedDestination = .resume }
                        Button("Cost Center") { selectedDestination = .costCenter }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            if selectedDestination == .contacts {
                                showingAddContact = true
                            } else if selectedDestination.applicationFilter != nil {
                                showingAddApplication = true
                            } else {
                                selectedDestination = .applications(.all)
                            }
                        } label: {
                            Image(systemName: selectedDestination == .contacts ? "person.badge.plus" : "plus")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddApplication) {
            AddApplicationView(settingsViewModel: settingsViewModel)
        }
        .sheet(isPresented: $showingAddContact) {
            ContactEditorView()
        }
        .sheet(item: $selectedApplication) { application in
            NavigationStack {
                JobDetailView(
                    application: application,
                    onSelectContact: { contact in
                        selectedDestination = .contacts
                        selectedContact = contact
                    }
                )
            }
        }
        .sheet(item: $selectedContact) { contact in
            NavigationStack {
                ContactDetailView(contact: contact)
            }
        }
        .task {
            prewarmJSONEditorIfNeeded()
        }
        #endif
    }
}

#Preview {
    ContentView(settingsViewModel: SettingsViewModel())
        .modelContainer(
            for: [
                JobApplication.self,
                JobSearchCycle.self,
                SearchGoal.self,
                InterviewLog.self,
                Contact.self,
                ApplicationContactLink.self,
                ApplicationActivity.self,
                ApplicationAttachment.self,
                ResumeMasterRevision.self,
                ResumeJobSnapshot.self,
                AIUsageRecord.self,
                AIModelRate.self
            ],
            inMemory: true
        )
}
