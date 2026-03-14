import SwiftUI
import SwiftData
import UniformTypeIdentifiers

public struct GoogleCalendarWorkspaceView: View {
    public init() {}

    public var body: some View {
        IntegrationsWorkspaceView()
    }
}

public struct GoogleCalendarSettingsContentView: View {
    public init() {}

    public var body: some View {
        IntegrationsSettingsContentView()
    }
}

public struct IntegrationsWorkspaceView: View {
    public init() {}

    public var body: some View {
        IntegrationsHubView(showHeader: true)
    }
}

public struct IntegrationsSettingsContentView: View {
    public init() {}

    public var body: some View {
        IntegrationsHubView(showHeader: false)
    }
}

private struct IntegrationsHubView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GoogleCalendarAccount.updatedAt, order: .reverse) private var accounts: [GoogleCalendarAccount]
    @Query(sort: \GoogleCalendarSubscription.title) private var subscriptions: [GoogleCalendarSubscription]
    @Query(sort: \GoogleCalendarImportRecord.startDate) private var importRecords: [GoogleCalendarImportRecord]
    @Query(sort: \GoogleCalendarInterviewLink.updatedAt, order: .reverse) private var interviewLinks: [GoogleCalendarInterviewLink]
    @Query(sort: \NetworkImportBatch.importedAt, order: .reverse) private var networkImportBatches: [NetworkImportBatch]
    @Query(sort: \ImportedNetworkConnection.updatedAt, order: .reverse) private var importedConnections: [ImportedNetworkConnection]
    @Query(sort: \CompanyAlias.updatedAt, order: .reverse) private var companyAliases: [CompanyAlias]
    @Query(sort: \JobApplication.updatedAt, order: .reverse) private var applications: [JobApplication]

    let showHeader: Bool

    @State private var isBusy = false
    @State private var busyMessage: String?
    @State private var errorMessage: String?
    @State private var selectedProvider: IntegrationProviderID = .googleCalendar
    @State private var showingLinkedInImporter = false
    @State private var linkedInSearchText = ""
    @State private var aliasCanonicalName = ""
    @State private var aliasName = ""

    private var account: GoogleCalendarAccount? {
        accounts.first
    }

    private var connectedAccount: GoogleCalendarAccount? {
        guard let account, account.isConnected else { return nil }
        return account
    }

    private var reviewItems: [GoogleCalendarImportRecord] {
        importRecords.filter(\.needsReview)
    }

    private var selectedSubscriptions: [GoogleCalendarSubscription] {
        subscriptions.filter(\.isSelected)
    }

    private var writeTargetSubscription: GoogleCalendarSubscription? {
        subscriptions.first(where: \.isWriteTarget)
    }

    private var activeInterviewLinks: [GoogleCalendarInterviewLink] {
        interviewLinks.filter { $0.syncStatus == .active }
    }

    private var pendingReviewCount: Int {
        importRecords.filter { $0.state == .pendingReview }.count
    }

    private var updatePendingCount: Int {
        importRecords.filter { $0.state == .updatePending }.count
    }

    private var upstreamDeletedCount: Int {
        importRecords.filter { $0.state == .upstreamDeleted }.count
    }

    private var latestNetworkImportBatch: NetworkImportBatch? {
        networkImportBatches.first
    }

    private var activeImportedConnections: [ImportedNetworkConnection] {
        importedConnections.filter { $0.status != .ignored }
    }

    private var filteredImportedConnections: [ImportedNetworkConnection] {
        let query = linkedInSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return importedConnections }

        return importedConnections.filter { connection in
            connection.fullName.lowercased().contains(query) ||
            connection.displayCompanyName.lowercased().contains(query) ||
            (connection.email?.lowercased().contains(query) ?? false)
        }
    }

    private var potentialAliasSuggestions: [PotentialCompanyAliasSuggestion] {
        NetworkReferralMatchingService.potentialAliasSuggestions(
            applications: applications,
            connections: importedConnections,
            aliases: companyAliases
        )
    }

    private var connectionStateText: String {
        if !GoogleOAuthService.shared.isClientConfigured {
            return "Configuration Required"
        }
        if connectedAccount != nil {
            return "Connected"
        }
        return "Ready to Connect"
    }

    private var connectionStateTint: Color {
        if !GoogleOAuthService.shared.isClientConfigured {
            return .orange
        }
        if connectedAccount != nil {
            return .green
        }
        return .blue
    }

    private var overviewSummary: String {
        if !GoogleOAuthService.shared.isClientConfigured {
            return "Complete the Google OAuth client configuration so Pipeline can securely receive the calendar sign-in callback."
        }

        if let connectedAccount {
            if reviewItems.isEmpty {
                let writeSummary = writeTargetSubscription?.title ?? "No write target selected"
                return "Google Calendar is connected for \(connectedAccount.email). Pipeline is monitoring \(selectedSubscriptions.count) read calendar\(selectedSubscriptions.count == 1 ? "" : "s"), writing interviews to \(writeSummary), and tracking \(activeInterviewLinks.count) linked interview\(activeInterviewLinks.count == 1 ? "" : "s")."
            }

            return "Google Calendar is connected for \(connectedAccount.email). \(reviewItems.count) event\(reviewItems.count == 1 ? "" : "s") need review before Pipeline creates or updates interview activities."
        }

        return "Connect Google Calendar to import interview events, choose exactly which calendars Pipeline can read, assign one writable calendar for synced interview events, and keep external events behind a manual review queue."
    }

    private var lastSyncValue: String {
        if let lastSyncedAt = connectedAccount?.lastSyncedAt {
            return lastSyncedAt.integrationRelativeDescription
        }
        return "Not yet"
    }

    private var lastSyncDetail: String {
        if let lastSyncedAt = connectedAccount?.lastSyncedAt {
            return lastSyncedAt.formatted(date: .abbreviated, time: .shortened)
        }
        return connectedAccount != nil ? "Run an event refresh after connecting." : "Available after Google Calendar is connected."
    }

    private var calendarRefreshDetail: String {
        if let refreshedAt = connectedAccount?.lastCalendarListRefreshAt {
            return "Catalog refreshed \(refreshedAt.integrationRelativeDescription)"
        }
        if connectedAccount != nil {
            return "Refresh calendars to load available sources."
        }
        return "Connect first to load calendars."
    }

    private var googleCalendarProviderSummary: IntegrationProviderSummary {
        let status: IntegrationProviderStatus

        if !GoogleOAuthService.shared.isClientConfigured {
            status = .configurationRequired
        } else if connectedAccount != nil {
            status = .connected
        } else {
            status = .available
        }

        return IntegrationProviderSummary(
            id: .googleCalendar,
            title: "Google Calendar",
            category: "Calendar Sync",
            description: "Read selected calendars, write Pipeline-managed interview events to one calendar, and keep external changes visible through review and sync state.",
            status: status,
            accountLabel: connectedAccount?.email ?? "No account connected",
            sourceSummary: subscriptions.isEmpty
                ? "No calendars loaded"
                : "\(selectedSubscriptions.count) read • \(writeTargetSubscription?.title ?? "no write target")",
            queueSummary: reviewItems.isEmpty ? "Queue clear" : "\(reviewItems.count) events waiting",
            pendingReviewCount: reviewItems.count,
            enabledSourceCount: selectedSubscriptions.count,
            totalSourceCount: subscriptions.count,
            capabilities: [
                "Interview event sync",
                "Source-level controls",
                "Review queue",
                "Linked interview tracking"
            ],
            note: !GoogleOAuthService.shared.isClientConfigured
                ? "Finish the OAuth callback configuration before enabling this provider."
                    : connectedAccount != nil
                    ? "Manage authentication, read coverage, outbound write target, and interview sync decisions for this provider."
                    : "This provider is ready to connect and can be managed without redesigning the rest of the page."
        )
    }

    private var linkedInCSVProviderSummary: IntegrationProviderSummary {
        let status: IntegrationProviderStatus = importedConnections.isEmpty ? .available : .connected
        let latestLabel = latestNetworkImportBatch?.sourceFileName ?? "No CSV imported"
        let queueSummary = potentialAliasSuggestions.isEmpty
            ? "Alias review clear"
            : "\(potentialAliasSuggestions.count) alias suggestion\(potentialAliasSuggestions.count == 1 ? "" : "s")"

        return IntegrationProviderSummary(
            id: .linkedInCSV,
            title: "LinkedIn CSV",
            category: "Network Import",
            description: "Import your LinkedIn connections export, keep the raw network separate from your curated contact book, and surface referral opportunities when company matches appear.",
            status: status,
            accountLabel: latestLabel,
            sourceSummary: importedConnections.isEmpty
                ? "No connections imported"
                : "\(activeImportedConnections.count) active of \(importedConnections.count) imported",
            queueSummary: queueSummary,
            pendingReviewCount: potentialAliasSuggestions.count,
            enabledSourceCount: activeImportedConnections.count,
            totalSourceCount: importedConnections.count,
            capabilities: [
                "CSV import",
                "Referral matching",
                "Contact promotion"
            ],
            note: importedConnections.isEmpty
                ? "Import the official LinkedIn connections CSV to start building Pipeline's internal network layer."
                : "Review import health, confirm company aliases, and promote useful network rows into first-class contacts."
        )
    }

    private var providerSummaries: [IntegrationProviderSummary] {
        [googleCalendarProviderSummary, linkedInCSVProviderSummary]
    }

    private var selectedProviderSummary: IntegrationProviderSummary {
        providerSummaries.first(where: { $0.id == selectedProvider }) ?? googleCalendarProviderSummary
    }

    private var connectedProviderCount: Int {
        providerSummaries.filter(\.isConnected).count
    }

    private var providerAttentionCount: Int {
        providerSummaries.filter(\.needsAttention).count
    }

    private var enabledSourceCount: Int {
        providerSummaries.reduce(0) { $0 + $1.enabledSourceCount }
    }

    private var integrationQueueCount: Int {
        reviewItems.count + potentialAliasSuggestions.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if showHeader {
                    header
                }

                overviewSection
                providerDirectorySection
                providerDetailHeaderSection
                providerDetailContent
            }
            .padding(24)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            await GoogleCalendarImportCoordinator.shared.restoreSessionIfPossible(in: modelContext)
        }
        .alert("Integrations", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .fileImporter(
            isPresented: $showingLinkedInImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                runTask("Importing LinkedIn connections…") {
                    _ = try LinkedInCSVImportService.shared.importFile(at: url, into: modelContext)
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Integrations")
                .font(.largeTitle.weight(.bold))
            Text("Manage external systems from one workspace. Each provider keeps its own authentication state, permission scope, source coverage, and review workflow.")
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                IntegrationPill(text: "Provider directory", systemImage: "puzzlepiece.extension", tint: .blue)
                IntegrationPill(text: "Least-privilege access", systemImage: "lock.shield", tint: .green)
                IntegrationPill(text: "Operational review queues", systemImage: "checklist", tint: .orange)
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            IntegrationSurfaceCard(prominent: true) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(connectionStateTint.opacity(0.14))
                                .frame(width: 56, height: 56)

                            Image(systemName: providerAttentionCount == 0 ? "puzzlepiece.extension.fill" : "puzzlepiece.extension")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(connectionStateTint)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Text("Integration Hub")
                                    .font(.title3.weight(.semibold))
                                IntegrationPill(
                                    text: providerAttentionCount == 0 ? "Stable" : "\(providerAttentionCount) need attention",
                                    systemImage: providerAttentionCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                    tint: providerAttentionCount == 0 ? .green : .orange
                                )
                            }

                            Text("Review provider health, manage external access, and keep import workflows isolated by integration instead of letting one provider define the whole workspace.")
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                IntegrationPill(text: "\(providerSummaries.count) provider\(providerSummaries.count == 1 ? "" : "s") available", systemImage: "square.grid.2x2", tint: .blue)
                                IntegrationPill(text: "\(connectedProviderCount) connected", systemImage: "link.badge.plus", tint: .green)
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    if let busyMessage {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text(busyMessage)
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                IntegrationMetricCard(
                    title: "Available Providers",
                    value: "\(providerSummaries.count)",
                    detail: "The hub is structured so additional providers can plug into the same directory and detail flow.",
                    systemImage: "puzzlepiece.extension",
                    tint: .blue
                )

                IntegrationMetricCard(
                    title: "Connected Providers",
                    value: "\(connectedProviderCount)",
                    detail: connectedProviderCount == 0 ? "No external systems connected yet." : "Connected providers can keep their own refresh and review workflows.",
                    systemImage: "link.circle",
                    tint: connectedProviderCount == 0 ? .secondary : .green
                )

                IntegrationMetricCard(
                    title: "Monitored Sources",
                    value: "\(enabledSourceCount)",
                    detail: enabledSourceCount == 0 ? "No sources enabled yet." : "Enabled sources are scoped inside each provider rather than globally.",
                    systemImage: "slider.horizontal.3",
                    tint: .teal
                )

                IntegrationMetricCard(
                    title: "Review Queues",
                    value: "\(integrationQueueCount)",
                    detail: integrationQueueCount == 0
                        ? "No pending reviews across the current provider set."
                        : "\(pendingReviewCount) calendar events, \(potentialAliasSuggestions.count) alias suggestions.",
                    systemImage: "tray.full",
                    tint: integrationQueueCount == 0 ? .green : .orange
                )
            }
        }
    }

    private var providerDirectorySection: some View {
        IntegrationSurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    title: "Provider Directory",
                    subtitle: "Every integration gets the same top-level treatment here: status, scope, and a path into provider-specific operations.",
                    systemImage: "puzzlepiece.extension",
                    badge: "\(providerSummaries.count) Available",
                    badgeTint: .blue
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                    ForEach(providerSummaries) { provider in
                        IntegrationProviderCard(
                            summary: provider,
                            isSelected: selectedProvider == provider.id,
                            onSelect: {
                                selectedProvider = provider.id
                            }
                        )
                    }
                }
            }
        }
    }

    private var providerDetailHeaderSection: some View {
        IntegrationSurfaceCard(prominent: true) {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(
                    title: "\(selectedProviderSummary.title) Operations",
                    subtitle: selectedProviderSummary.note,
                    systemImage: selectedProviderSummary.status.icon,
                    badge: selectedProviderSummary.status.label,
                    badgeTint: selectedProviderSummary.status.tint
                )

                HStack(spacing: 8) {
                    IntegrationPill(text: selectedProviderSummary.category, systemImage: "square.stack.3d.up", tint: .blue)
                    ForEach(selectedProviderSummary.capabilities, id: \.self) { capability in
                        IntegrationPill(text: capability, tint: .secondary)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    IntegrationMetricCard(
                        title: "Account",
                        value: selectedProviderSummary.accountLabel,
                        detail: "Authentication state and provider identity.",
                        systemImage: "person.crop.circle",
                        tint: selectedProviderSummary.status.tint
                    )

                    IntegrationMetricCard(
                        title: "Source Scope",
                        value: selectedProviderSummary.sourceSummary,
                        detail: "Provider-level source coverage remains isolated from other integrations.",
                        systemImage: "slider.horizontal.3",
                        tint: .teal
                    )

                    IntegrationMetricCard(
                        title: "Operational Queue",
                        value: selectedProviderSummary.queueSummary,
                        detail: "Review and exception handling stay inside the provider detail area.",
                        systemImage: "tray.full",
                        tint: selectedProviderSummary.pendingReviewCount == 0 ? .green : .orange
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var providerDetailContent: some View {
        switch selectedProvider {
        case .googleCalendar:
            googleAccountSection
            googleCalendarCoverageSection
            googleReviewQueueSection
            googleLinkedInterviewsSection
        case .linkedInCSV:
            linkedInImportSection
            linkedInAliasSection
            linkedInConnectionsSection
        }
    }

    private var googleAccountSection: some View {
        IntegrationSurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    title: "Account Access",
                    subtitle: "Authenticate once, keep credentials in Keychain, and separate provider connection health from downstream import work.",
                    systemImage: "person.crop.circle.badge.checkmark",
                    badge: connectionStateText,
                    badgeTint: connectionStateTint
                )

                if !GoogleOAuthService.shared.isClientConfigured {
                    IntegrationEmptyState(
                        title: "Google Calendar is not configured for this build",
                        message: "Add `GOOGLE_CLIENT_ID` and `GOOGLE_REVERSED_CLIENT_ID` to the Pipeline app target so the callback URL scheme is registered before sign-in starts.",
                        systemImage: "wrench.and.screwdriver.fill",
                        tint: .orange
                    )
                } else if let connectedAccount {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .center, spacing: 14) {
                            IntegrationAvatarView(
                                name: connectedAccount.displayName ?? connectedAccount.email,
                                imageURLString: connectedAccount.avatarURLString
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(connectedAccount.displayName ?? connectedAccount.email)
                                    .font(.headline)
                                Text(connectedAccount.email)
                                    .foregroundStyle(.secondary)

                                if let refreshedAt = connectedAccount.lastCalendarListRefreshAt {
                                    Text("Calendar catalog refreshed \(refreshedAt.integrationRelativeDescription)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 6) {
                                IntegrationPill(text: "Read-only access", systemImage: "lock.shield", tint: .green)
                                if let lastSyncedAt = connectedAccount.lastSyncedAt {
                                    Text("Events synced \(lastSyncedAt.integrationRelativeDescription)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) {
                                refreshCalendarsButton
                                refreshEventsButton
                                disconnectButton
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                refreshCalendarsButton
                                refreshEventsButton
                                disconnectButton
                            }
                        }

                        Text("Pipeline reads selected calendars, writes Pipeline-managed interview events to one chosen calendar, and still holds unmatched external events in a review queue.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        IntegrationEmptyState(
                            title: "No Google account connected",
                            message: "Connect Google Calendar to start importing interview events. Pipeline reads only the calendars you select and holds each event in a review queue first.",
                            systemImage: "person.crop.circle.badge.plus",
                            tint: .blue
                        )

                        connectButton
                    }
                }
            }
        }
    }

    private var googleCalendarCoverageSection: some View {
        IntegrationSurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    title: "Calendar Coverage",
                    subtitle: "Choose which Google calendars Pipeline can scan for interview activity. Only selected calendars participate in sync.",
                    systemImage: "calendar",
                    badge: subscriptions.isEmpty ? "Not Loaded" : "\(selectedSubscriptions.count) Read • \(writeTargetSubscription == nil ? "No Write Target" : "Write Ready")",
                    badgeTint: subscriptions.isEmpty ? .secondary : .blue
                )

                if subscriptions.isEmpty {
                    IntegrationEmptyState(
                        title: connectedAccount != nil ? "No calendars loaded yet" : "Connect Google Calendar to load calendars",
                        message: connectedAccount != nil ? "Refresh calendars to discover the sources available under this Google account." : "Once connected, Pipeline will list each Google calendar here so you can explicitly control import coverage.",
                        systemImage: "calendar.badge.exclamationmark",
                        tint: connectedAccount != nil ? .blue : .secondary
                    )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("\(selectedSubscriptions.count) read calendar\(selectedSubscriptions.count == 1 ? "" : "s") selected")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(calendarRefreshDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(subscriptions) { subscription in
                            GoogleCalendarSubscriptionRow(
                                subscription: subscription,
                                isConnected: connectedAccount != nil,
                                isBusy: isBusy,
                                onSelectionChange: { isSelected in
                                    do {
                                        try GoogleCalendarImportCoordinator.shared.setCalendarSelection(
                                            subscription,
                                            isSelected: isSelected,
                                            in: modelContext
                                        )
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                },
                                onSetWriteTarget: {
                                    do {
                                        try GoogleCalendarImportCoordinator.shared.setWriteTarget(
                                            subscription,
                                            in: modelContext
                                        )
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var googleLinkedInterviewsSection: some View {
        IntegrationSurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    title: "Linked Interviews",
                    subtitle: "Track Pipeline-managed interview links separately from the external review queue so drift, deletions, and permission issues are visible.",
                    systemImage: "link",
                    badge: interviewLinks.isEmpty ? "None" : "\(interviewLinks.count) Linked",
                    badgeTint: interviewLinks.isEmpty ? .secondary : .blue
                )

                if interviewLinks.isEmpty {
                    IntegrationEmptyState(
                        title: "No managed interview links yet",
                        message: "Once Pipeline creates or accepts synced interview events, their link health will appear here.",
                        systemImage: "link.badge.plus",
                        tint: .secondary
                    )
                } else {
                    ForEach(interviewLinks.prefix(8)) { link in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: link.syncStatus.icon)
                                .foregroundStyle(link.syncStatus == .active ? .green : .orange)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(link.remoteCalendarName)
                                    .font(.subheadline.weight(.semibold))
                                Text(link.ownership.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            IntegrationPill(
                                text: link.syncStatus.displayName,
                                systemImage: link.syncStatus.icon,
                                tint: link.syncStatus == .active ? .green : .orange
                            )
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.secondary.opacity(0.07))
                        )
                    }
                }
            }
        }
    }

    private var googleReviewQueueSection: some View {
        IntegrationSurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    title: "Review Queue",
                    subtitle: "Every Google Calendar event is held here until you decide whether Pipeline should create, update, or ignore the corresponding application activity.",
                    systemImage: "tray.full",
                    badge: reviewItems.isEmpty ? "Clear" : "\(reviewItems.count) Waiting",
                    badgeTint: reviewItems.isEmpty ? .green : .orange
                )

                if reviewItems.isEmpty {
                    IntegrationEmptyState(
                        title: "No calendar events need review right now",
                        message: connectedAccount != nil ? "New imports, updates, or cancelled calendar events will appear here for approval." : "Once Google Calendar is connected and calendars are selected, pending interview events will appear here for review.",
                        systemImage: "checkmark.seal.fill",
                        tint: .green
                    )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            if pendingReviewCount > 0 {
                                IntegrationPill(text: "\(pendingReviewCount) new", systemImage: "tray.and.arrow.down", tint: .orange)
                            }
                            if updatePendingCount > 0 {
                                IntegrationPill(text: "\(updatePendingCount) updates", systemImage: "arrow.triangle.2.circlepath", tint: .blue)
                            }
                            if upstreamDeletedCount > 0 {
                                IntegrationPill(text: "\(upstreamDeletedCount) removed upstream", systemImage: "trash.slash", tint: .red)
                            }
                        }

                        ForEach(reviewItems) { record in
                            GoogleCalendarImportRecordRow(
                                record: record,
                                applications: applications,
                                onAccept: { application in
                                    runTask("Importing interview event…") {
                                        try await GoogleCalendarImportCoordinator.shared.acceptImport(
                                            record,
                                            into: application,
                                            in: modelContext
                                        )
                                    }
                                },
                                onIgnore: {
                                    do {
                                        try GoogleCalendarImportCoordinator.shared.ignoreImport(record, in: modelContext)
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var linkedInImportSection: some View {
        IntegrationSurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    title: "Import Connections",
                    subtitle: "Bring in the official LinkedIn connections CSV, preserve it as a separate network layer, and keep your contact book curated.",
                    systemImage: "square.and.arrow.down",
                    badge: importedConnections.isEmpty ? "Ready" : "\(importedConnections.count) Imported",
                    badgeTint: importedConnections.isEmpty ? .blue : .green
                )

                if let latestNetworkImportBatch {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(latestNetworkImportBatch.sourceFileName)
                                    .font(.headline)
                                Text("Imported \(latestNetworkImportBatch.importedAt.integrationRelativeDescription)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            IntegrationPill(text: latestNetworkImportBatch.provider.displayName, tint: .blue)
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                            IntegrationMetricCard(
                                title: "New Rows",
                                value: "\(latestNetworkImportBatch.importedCount)",
                                detail: "Fresh LinkedIn connections added during the last import.",
                                systemImage: "plus.circle",
                                tint: .green
                            )
                            IntegrationMetricCard(
                                title: "Updated Rows",
                                value: "\(latestNetworkImportBatch.updatedCount)",
                                detail: "Existing network rows refreshed from the latest file.",
                                systemImage: "arrow.triangle.2.circlepath",
                                tint: .blue
                            )
                            IntegrationMetricCard(
                                title: "Skipped Rows",
                                value: "\(latestNetworkImportBatch.skippedCount)",
                                detail: "Rows skipped because required identity data was missing.",
                                systemImage: "forward",
                                tint: .secondary
                            )
                        }

                        if let notes = latestNetworkImportBatch.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.primary.opacity(0.04))
                                )
                        }
                    }
                } else {
                    IntegrationEmptyState(
                        title: "No LinkedIn CSV imported yet",
                        message: "Export your first-degree connections from LinkedIn, then import the CSV here to let Pipeline suggest referral opportunities when company matches appear.",
                        systemImage: "tray.and.arrow.down",
                        tint: .blue
                    )
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        importLinkedInButton
                        clearLinkedInImportButton
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        importLinkedInButton
                        clearLinkedInImportButton
                    }
                }
            }
        }
    }

    private var linkedInAliasSection: some View {
        IntegrationSurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    title: "Company Aliases",
                    subtitle: "Use exact normalized matching by default, then confirm aliases when imported company names vary from the names used in your applications.",
                    systemImage: "arrow.left.arrow.right.square",
                    badge: potentialAliasSuggestions.isEmpty ? "No Suggestions" : "\(potentialAliasSuggestions.count) Suggested",
                    badgeTint: potentialAliasSuggestions.isEmpty ? .secondary : .orange
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Add Alias Manually")
                        .font(.subheadline.weight(.semibold))

                    TextField("Application company name", text: $aliasCanonicalName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Imported company alias", text: $aliasName)
                        .textFieldStyle(.roundedBorder)

                    Button("Add Alias") {
                        runTask("Saving company alias…") {
                            try await addCompanyAlias()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(aliasCanonicalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || aliasName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !potentialAliasSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Suggested Aliases")
                            .font(.subheadline.weight(.semibold))

                        ForEach(potentialAliasSuggestions) { suggestion in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(suggestion.canonicalName) ↔ \(suggestion.aliasName)")
                                        .font(.subheadline.weight(.semibold))
                                    Text(suggestion.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("Confirm") {
                                    runTask("Saving company alias…") {
                                        try NetworkReferralMatchingService.addAlias(
                                            canonicalName: suggestion.canonicalName,
                                            aliasName: suggestion.aliasName,
                                            in: modelContext
                                        )
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.secondary.opacity(0.07))
                            )
                        }
                    }
                }

                if !companyAliases.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Confirmed Aliases")
                            .font(.subheadline.weight(.semibold))

                        ForEach(companyAliases) { alias in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(alias.canonicalName)
                                        .font(.subheadline.weight(.semibold))
                                    Text(alias.aliasName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.secondary.opacity(0.07))
                            )
                        }
                    }
                }
            }
        }
    }

    private var linkedInConnectionsSection: some View {
        IntegrationSurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    title: "Imported Network",
                    subtitle: "Search the imported LinkedIn network, promote the right people into your contact book, and ignore rows that should stop influencing referral suggestions.",
                    systemImage: "person.3",
                    badge: filteredImportedConnections.isEmpty ? "Empty" : "\(filteredImportedConnections.count) Visible",
                    badgeTint: filteredImportedConnections.isEmpty ? .secondary : .blue
                )

                if importedConnections.isEmpty {
                    IntegrationEmptyState(
                        title: "Import a LinkedIn CSV to populate the network directory",
                        message: "Once imported, you can review individual rows here, promote useful people into saved contacts, and hide irrelevant matches.",
                        systemImage: "person.crop.circle.badge.plus",
                        tint: .secondary
                    )
                } else {
                    TextField("Search by name, company, or email", text: $linkedInSearchText)
                        .textFieldStyle(.roundedBorder)

                    ForEach(filteredImportedConnections) { connection in
                        LinkedInImportedConnectionRow(
                            connection: connection,
                            onPromote: {
                                runTask("Promoting contact…") {
                                    _ = try NetworkReferralMatchingService.promote(
                                        connection: connection,
                                        in: modelContext
                                    )
                                }
                            },
                            onToggleIgnored: {
                                runTask(connection.status == .ignored ? "Restoring network row…" : "Ignoring network row…") {
                                    try NetworkReferralMatchingService.setIgnored(
                                        connection.status != .ignored,
                                        for: connection,
                                        in: modelContext
                                    )
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private var connectButton: some View {
        Button("Connect Google Calendar") {
            runTask("Connecting Google Calendar…") {
                try await GoogleCalendarImportCoordinator.shared.connect(in: modelContext)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!GoogleOAuthService.shared.isClientConfigured || isBusy)
    }

    private var refreshCalendarsButton: some View {
        Button("Refresh Calendars") {
            runTask("Refreshing calendar list…") {
                try await GoogleCalendarImportCoordinator.shared.refreshCalendarList(in: modelContext)
            }
        }
        .buttonStyle(.bordered)
        .disabled(isBusy)
    }

    private var refreshEventsButton: some View {
        Button("Refresh Events") {
            runTask("Refreshing calendar events…") {
                try await GoogleCalendarImportCoordinator.shared.syncNow(in: modelContext)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isBusy)
    }

    private var disconnectButton: some View {
        Button("Disconnect", role: .destructive) {
            runTask("Disconnecting Google Calendar…") {
                await GoogleCalendarImportCoordinator.shared.disconnect(in: modelContext)
            }
        }
        .buttonStyle(.bordered)
        .disabled(isBusy)
    }

    private var importLinkedInButton: some View {
        Button("Import LinkedIn CSV") {
            showingLinkedInImporter = true
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isBusy)
    }

    private var clearLinkedInImportButton: some View {
        Button("Clear Imported Network", role: .destructive) {
            runTask("Removing imported LinkedIn data…") {
                try LinkedInCSVImportService.shared.clearImportedConnections(in: modelContext)
            }
        }
        .buttonStyle(.bordered)
        .disabled(isBusy || importedConnections.isEmpty)
    }

    @ViewBuilder
    private func sectionHeader(
        title: String,
        subtitle: String,
        systemImage: String,
        badge: String,
        badgeTint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            IntegrationPill(text: badge, tint: badgeTint)
        }
    }

    private func runTask(_ message: String, _ operation: @escaping () async throws -> Void) {
        guard !isBusy else { return }

        Task { @MainActor in
            isBusy = true
            busyMessage = message
            defer {
                isBusy = false
                busyMessage = nil
            }

            do {
                try await operation()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addCompanyAlias() async throws {
        try NetworkReferralMatchingService.addAlias(
            canonicalName: aliasCanonicalName,
            aliasName: aliasName,
            in: modelContext
        )
        aliasCanonicalName = ""
        aliasName = ""
    }
}

private enum IntegrationProviderID: String, Identifiable {
    case googleCalendar
    case linkedInCSV

    var id: String { rawValue }
}

private enum IntegrationProviderStatus: Equatable {
    case available
    case connected
    case configurationRequired

    var label: String {
        switch self {
        case .available:
            return "Available"
        case .connected:
            return "Connected"
        case .configurationRequired:
            return "Configuration Required"
        }
    }

    var tint: Color {
        switch self {
        case .available:
            return .blue
        case .connected:
            return .green
        case .configurationRequired:
            return .orange
        }
    }

    var icon: String {
        switch self {
        case .available:
            return "bolt.horizontal.circle"
        case .connected:
            return "checkmark.circle.fill"
        case .configurationRequired:
            return "wrench.and.screwdriver.fill"
        }
    }
}

private struct IntegrationProviderSummary: Identifiable {
    let id: IntegrationProviderID
    let title: String
    let category: String
    let description: String
    let status: IntegrationProviderStatus
    let accountLabel: String
    let sourceSummary: String
    let queueSummary: String
    let pendingReviewCount: Int
    let enabledSourceCount: Int
    let totalSourceCount: Int
    let capabilities: [String]
    let note: String

    var needsAttention: Bool {
        status == .configurationRequired || pendingReviewCount > 0
    }

    var isConnected: Bool {
        status == .connected
    }
}

private struct GoogleCalendarImportRecordRow: View {
    let record: GoogleCalendarImportRecord
    let applications: [JobApplication]
    let onAccept: (JobApplication) -> Void
    let onIgnore: () -> Void

    @State private var selectedApplicationID: UUID?

    private var suggestedApplication: JobApplication? {
        record.importedActivity?.application ??
        record.suggestedApplication ??
        applications.first(where: { $0.id == selectedApplicationID })
    }

    private var activeApplicationID: UUID? {
        selectedApplicationID ?? suggestedApplication?.id
    }

    private var stateTint: Color {
        switch record.state {
        case .pendingReview:
            return .orange
        case .imported:
            return .green
        case .ignored:
            return .secondary
        case .upstreamDeleted:
            return .red
        case .updatePending:
            return .blue
        }
    }

    private var targetApplication: JobApplication? {
        applications.first(where: { $0.id == activeApplicationID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(stateTint.opacity(0.14))
                        .frame(width: 42, height: 42)

                    Image(systemName: record.state.icon)
                        .font(.headline)
                        .foregroundStyle(stateTint)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(record.displayTitle)
                        .font(.headline)

                    HStack(spacing: 12) {
                        Label(record.scheduleSummary, systemImage: "calendar")
                        Label(record.remoteCalendarName, systemImage: "tray")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let suggestedApplication {
                        Label("\(suggestedApplication.companyName) · \(suggestedApplication.role)", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                IntegrationPill(text: record.state.displayName, systemImage: record.state.icon, tint: stateTint)
            }

            if let location = record.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let organizerEmail = record.organizerEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !organizerEmail.isEmpty {
                Label(organizerEmail, systemImage: "person.crop.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let details = record.details?.trimmingCharacters(in: .whitespacesAndNewlines), !details.isEmpty {
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
            }

            if record.state == .upstreamDeleted {
                callout(
                    text: "This event was removed or cancelled in Google Calendar. Keep the existing Pipeline activity only if it should remain in the application timeline.",
                    tint: .red
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Link to Application")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("Application", selection: Binding(
                        get: { activeApplicationID },
                        set: { selectedApplicationID = $0 }
                    )) {
                        ForEach(applications) { application in
                            Text("\(application.companyName) · \(application.role)").tag(Optional(application.id))
                        }
                    }
                    .pickerStyle(.menu)

                    if suggestedApplication != nil {
                        Text("Pipeline preselected the most likely matching application. You can change it before importing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    primaryActionButton
                    secondaryActionButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    primaryActionButton
                    secondaryActionButton
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06))
                )
        )
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if record.state != .upstreamDeleted, let targetApplication {
            Button(record.state == .updatePending ? "Apply Update" : "Import Activity") {
                onAccept(targetApplication)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var secondaryActionButton: some View {
        Button(record.state == .upstreamDeleted ? "Keep Local Activity" : "Ignore") {
            onIgnore()
        }
        .buttonStyle(.bordered)
    }

    private func callout(text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(tint)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }
}

private struct GoogleCalendarSubscriptionRow: View {
    let subscription: GoogleCalendarSubscription
    let isConnected: Bool
    let isBusy: Bool
    let onSelectionChange: (Bool) -> Void
    let onSetWriteTarget: () -> Void

    private var tint: Color {
        if let colorHex = subscription.colorHex, let parsed = Color(googleCalendarHex: colorHex) {
            return parsed
        }
        return subscription.isSelected ? .blue : .secondary
    }

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(subscription.title)
                        .font(.subheadline.weight(.semibold))

                    if subscription.isPrimary {
                        IntegrationPill(text: "Primary", tint: .secondary)
                    }
                }

                HStack(spacing: 12) {
                    Text(subscription.isSelected ? "Read enabled" : "Read disabled")
                    if subscription.isWriteTarget {
                        Text("Write target")
                    }
                    if let lastSyncedAt = subscription.lastSyncedAt {
                        Text("Last synced \(lastSyncedAt.integrationRelativeDescription)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                if subscription.isWriteTarget {
                    Button("Write Target") {
                        onSetWriteTarget()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isConnected || isBusy)
                } else {
                    Button("Use for Writes") {
                        onSetWriteTarget()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isConnected || isBusy)
                }

                Toggle("", isOn: Binding(
                    get: { subscription.isSelected },
                    set: onSelectionChange
                ))
                .labelsHidden()
                .disabled(!isConnected || isBusy)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(subscription.isSelected ? tint.opacity(0.35) : Color.primary.opacity(0.05))
                )
        )
    }
}

private struct LinkedInImportedConnectionRow: View {
    let connection: ImportedNetworkConnection
    let onPromote: () -> Void
    let onToggleIgnored: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill((connection.status == .ignored ? Color.secondary : Color.blue).opacity(0.14))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(initials)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(connection.status == .ignored ? Color.secondary : Color.blue)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(connection.fullName)
                            .font(.subheadline.weight(.semibold))

                        IntegrationPill(
                            text: connection.status.displayName,
                            systemImage: connection.status.icon,
                            tint: connection.status.color
                        )
                    }

                    Text(connection.displayCompanyName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let title = connection.title, !title.isEmpty {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            if let email = connection.email, !email.isEmpty {
                Label(email, systemImage: "envelope")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button(connection.linkedContact == nil ? "Promote to Contact" : "Refresh Contact") {
                    onPromote()
                }
                .buttonStyle(.bordered)

                Button(connection.status == .ignored ? "Restore" : "Ignore") {
                    onToggleIgnored()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(connection.status.color.opacity(0.25))
                )
        )
    }

    private var initials: String {
        let words = connection.fullName.split(whereSeparator: \.isWhitespace)
        let letters = words.prefix(2).compactMap { $0.first.map(String.init) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

private struct IntegrationProviderCard: View {
    let summary: IntegrationProviderSummary
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(summary.category.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(summary.title)
                            .font(.headline)

                        Text(summary.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    IntegrationPill(text: summary.status.label, systemImage: summary.status.icon, tint: summary.status.tint)
                }

                VStack(alignment: .leading, spacing: 10) {
                    providerFactRow("Account", value: summary.accountLabel)
                    providerFactRow("Sources", value: summary.sourceSummary)
                    providerFactRow("Queue", value: summary.queueSummary)
                }

                HStack(spacing: 8) {
                    ForEach(summary.capabilities, id: \.self) { capability in
                        IntegrationPill(text: capability, tint: .secondary)
                    }
                }

                HStack {
                    Text(isSelected ? "Selected" : "Manage Provider")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? summary.status.tint : Color.accentColor)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "arrow.right.circle")
                        .foregroundStyle(isSelected ? summary.status.tint : Color.accentColor)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.secondary.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isSelected ? summary.status.tint.opacity(0.45) : Color.primary.opacity(0.05))
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func providerFactRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }
}

private struct IntegrationSurfaceCard<Content: View>: View {
    let prominent: Bool
    let content: Content

    init(prominent: Bool = false, @ViewBuilder content: () -> Content) {
        self.prominent = prominent
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(prominent ? 0.07 : 0.05))
            )
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: prominent
                        ? [Color.accentColor.opacity(0.16), Color.secondary.opacity(0.08)]
                        : [Color.secondary.opacity(0.08), Color.secondary.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

private struct IntegrationMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Spacer()
            }

            Text(value)
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.05))
                )
        )
    }
}

private struct IntegrationPill: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
            }

            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }
}

private struct IntegrationEmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: systemImage)
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }
}

private struct IntegrationAvatarView: View {
    let name: String
    let imageURLString: String?

    var body: some View {
        Group {
            if let imageURLString, let url = URL(string: imageURLString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        avatarFallback
                    }
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
    }

    private var avatarFallback: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.16))
            Text(initials)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let prefix = parts.prefix(2).compactMap { $0.first }
        let value = String(prefix)
        return value.isEmpty ? "GC" : value.uppercased()
    }
}

private extension GoogleCalendarImportRecord {
    var scheduleSummary: String {
        if isAllDay {
            return "\(startDate.formatted(date: .abbreviated, time: .omitted)) · All day"
        }

        return "\(startDate.formatted(date: .abbreviated, time: .shortened)) to \(endDate.formatted(date: .omitted, time: .shortened))"
    }
}

private extension Date {
    var integrationRelativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: .now)
    }
}

private extension Color {
    init?(googleCalendarHex hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "#", with: "")

        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            return nil
        }

        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255

        self = Color(red: red, green: green, blue: blue)
    }
}
