import SwiftUI
import SwiftData
import PipelineKit

struct OfferComparisonWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \JobApplication.updatedAt, order: .reverse) private var applications: [JobApplication]
    @Query(sort: \OfferComparisonWorksheet.updatedAt, order: .reverse) private var worksheets: [OfferComparisonWorksheet]

    @Bindable var settingsViewModel: SettingsViewModel

    @State private var isLoadingWorksheet = false
    @State private var isGeneratingAI = false
    @State private var errorMessage: String?
    @State private var showingAddFactorAlert = false
    @State private var customFactorTitle = ""
#if os(macOS)
    @State private var isExportingPDF = false
    @State private var showingPDFExporter = false
    @State private var pdfDocument = ResumePDFFileDocument(data: Data())
#endif

    private let worksheetService = OfferComparisonWorksheetService()
    private let scoringService = OfferComparisonScoringService()

    private var offeredApplications: [JobApplication] {
        applications.filter { $0.status == .offered }
    }

    private var worksheet: OfferComparisonWorksheet? {
        worksheets.first
    }

    private var offeredSignature: String {
        offeredApplications.map { "\($0.id.uuidString)-\($0.updatedAt.timeIntervalSinceReferenceDate)" }
            .joined(separator: "|")
    }

    private var aiProvider: AIProvider {
        settingsViewModel.selectedAIProvider
    }

    private var aiModel: String {
        settingsViewModel.preferredModel(for: aiProvider)
    }

    private var aiReady: Bool {
        guard !aiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard AICompletionClient.supportsWebSearch(provider: aiProvider, model: aiModel) else { return false }
        return (try? settingsViewModel.apiKeys(for: aiProvider).isEmpty == false) ?? false
    }

    private var knownApplications: [JobApplication] {
        guard let worksheet else { return offeredApplications }
        let applicationsByID = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, $0) })
        return worksheet.knownApplicationIDs.compactMap { applicationsByID[$0] }
    }

    private var selectedApplications: [JobApplication] {
        guard let worksheet else { return [] }
        return scoringService.selectedApplications(for: worksheet, from: applications)
    }

    private var evaluation: OfferComparisonEvaluation? {
        guard let worksheet else { return nil }
        return scoringService.evaluate(worksheet: worksheet, applications: applications)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if offeredApplications.count < 2 {
                    emptyStateCard(
                        title: "Need at least two offered applications",
                        message: "Move two or more applications into Offered status to unlock native offer comparison."
                    )
                } else if !aiReady {
                    emptyStateCard(
                        title: "AI setup required",
                        message: "Configure an AI provider with web-search support in Settings to enable the offer comparison worksheet."
                    )
                } else if isLoadingWorksheet && worksheet == nil {
                    ProgressView("Loading offer comparison…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else if let worksheet {
                    selectionCard(worksheet)
                    worksheetCard(worksheet)
                    recommendationCard(worksheet)
                    aiAnalysisCard(worksheet)
                    negotiationCard(worksheet)
                }
            }
            .padding(20)
        }
        .background(DesignSystem.Colors.contentBackground(colorScheme))
        .task(id: offeredSignature) {
            await loadWorksheetIfNeeded()
        }
        .alert("Offer Comparison", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .alert("Add Custom Factor", isPresented: $showingAddFactorAlert) {
            TextField("Factor name", text: $customFactorTitle)
            Button("Cancel", role: .cancel) {
                customFactorTitle = ""
            }
            Button("Add") {
                addCustomFactor()
            }
        } message: {
            Text("Add a factor like commute, visa sponsorship, or learning opportunities.")
        }
#if os(macOS)
        .fileExporter(
            isPresented: $showingPDFExporter,
            document: pdfDocument,
            contentType: .pdf,
            defaultFilename: "Offer Comparison"
        ) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
#endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Compare Offers")
                        .font(.title2.weight(.semibold))
                    Text("Evaluate current offers side by side with weighted scoring, AI analysis, and negotiation support.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    Button("Add Custom Factor") {
                        showingAddFactorAlert = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(worksheet == nil)

                    Button(isGeneratingAI ? "Generating…" : "Refresh AI Analysis") {
                        Task { await runAIAnalysis() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accent)
                    .disabled(worksheet == nil || isGeneratingAI || !aiReady)

#if os(macOS)
                    Button(isExportingPDF ? "Exporting…" : "Export PDF") {
                        exportPDF()
                    }
                    .buttonStyle(.bordered)
                    .disabled(worksheet == nil || selectedApplications.isEmpty || isExportingPDF)
#endif
                }
            }

            if let evaluation {
                HStack(spacing: 16) {
                    metricPill(title: "Selected Offers", value: "\(selectedApplications.count)")
                    metricPill(title: "Active Factors", value: "\(evaluation.activeFactorCount)")
                    metricPill(title: "Missing Scores", value: "\(evaluation.missingScoreCount)")
                }
            }

#if os(iOS)
            Text("PDF export is available on macOS.")
                .font(.caption)
                .foregroundColor(.secondary)
#endif
        }
    }

    private func selectionCard(_ worksheet: OfferComparisonWorksheet) -> some View {
        card(title: "Offer Scope", subtitle: "Start from all offered applications, then remove or re-add offers as needed.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(knownApplications) { application in
                    Toggle(isOn: selectionBinding(for: application, worksheet: worksheet)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(application.companyName)
                                .font(.subheadline.weight(.semibold))
                            Text(application.role)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(application.status.displayName)
                                .font(.caption2)
                                .foregroundColor(application.status == .offered ? .green : .secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.switch)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
                    )
                }
            }
        }
    }

    private func worksheetCard(_ worksheet: OfferComparisonWorksheet) -> some View {
        card(
            title: "Worksheet",
            subtitle: "Values are shown side by side. Compensation rows use manual scores; PTO, remote policy, and qualitative factors can be adjusted inline."
        ) {
            ScrollView(.horizontal) {
                Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 14) {
                    GridRow {
                        tableHeaderCell("Factor")
                        ForEach(selectedApplications) { application in
                            tableHeaderCell(application.companyName)
                        }
                    }

                    ForEach(worksheet.sortedFactors) { factor in
                        if factor.isEnabled {
                            GridRow {
                                factorHeaderCell(factor)
                                ForEach(selectedApplications) { application in
                                    factorValueCell(factor: factor, application: application)
                                }
                            }
                            Divider()
                                .gridCellColumns(selectedApplications.count + 1)
                        }
                    }
                }
            }
        }
    }

    private func recommendationCard(_ worksheet: OfferComparisonWorksheet) -> some View {
        card(
            title: "Calculated Recommendation",
            subtitle: "Deterministic weighted scoring based on the factors and scores in this worksheet."
        ) {
            if let evaluation {
                if evaluation.isComplete, let top = evaluation.results.first {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(top.companyName) ranks highest overall.")
                            .font(.headline)
                        Text("\(top.role) scored \(String(format: "%.2f", top.weightedAverage))/5 based on your current weights.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        ForEach(evaluation.results) { result in
                            HStack {
                                Text(result.companyName)
                                Spacer()
                                Text(String(format: "%.2f / 5", result.weightedAverage))
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } else {
                    Text("Complete every active score cell before Pipeline calculates a final recommendation.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func aiAnalysisCard(_ worksheet: OfferComparisonWorksheet) -> some View {
        card(
            title: "AI Recommendation",
            subtitle: "Uses your current worksheet priorities to explain the strongest option and the main tradeoffs."
        ) {
            if isGeneratingAI && (worksheet.recommendationText == nil) {
                ProgressView("Generating recommendation…")
            } else {
                Text(worksheet.recommendationText ?? "Run AI analysis to generate a recommendation summary.")
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func negotiationCard(_ worksheet: OfferComparisonWorksheet) -> some View {
        card(
            title: "Negotiation Helper",
            subtitle: "Grounded web research plus your worksheet data to suggest negotiation angles and scripts."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if isGeneratingAI && (worksheet.negotiationText == nil) {
                    ProgressView("Generating negotiation guidance…")
                } else {
                    Text(worksheet.negotiationText ?? "Run AI analysis to generate negotiation guidance.")
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !worksheet.negotiationCitations.isEmpty {
                    Divider()
                    Text("Citations")
                        .font(.subheadline.weight(.semibold))

                    ForEach(Array(worksheet.negotiationCitations.enumerated()), id: \.offset) { _, citation in
                        Link(destination: URL(string: citation.urlString) ?? URL(string: "https://example.com")!) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(citation.title)
                                    .font(.subheadline.weight(.medium))
                                Text(citation.urlString)
                                    .font(.caption)
                                    .foregroundColor(DesignSystem.Colors.accent)
                                if let snippet = citation.snippet {
                                    Text(snippet)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func factorHeaderCell(_ factor: OfferComparisonFactor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if factor.kind == .custom {
                TextField("Factor", text: factorTitleBinding(factor))
                    .textFieldStyle(.roundedBorder)
            } else {
                Text(factor.title)
                    .font(.subheadline.weight(.semibold))
            }

            Stepper(value: factorWeightBinding(factor), in: 1...10) {
                Text("Weight \(factor.weight)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if factor.kind == .custom {
                Button("Delete", role: .destructive) {
                    deleteCustomFactor(factor)
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
        }
        .frame(width: 220, alignment: .leading)
    }

    private func factorValueCell(
        factor: OfferComparisonFactor,
        application: JobApplication
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch factor.kind {
            case .baseSalary, .equity4Year, .signingBonus, .totalCompYear1:
                let display = scoringService.displayValue(for: factor, application: application)
                Text(display.text)
                    .font(.subheadline)
                StarRating(rating: factorScoreBinding(factor, application: application), minRating: 0, size: 16)
            case .pto:
                TextField("PTO", text: offerPTOTextBinding(for: application))
                    .textFieldStyle(.roundedBorder)
                StarRating(rating: offerPTOScoreBinding(for: application), minRating: 0, size: 16)
            case .remotePolicy:
                TextField("Remote", text: offerRemotePolicyTextBinding(for: application))
                    .textFieldStyle(.roundedBorder)
                StarRating(rating: offerRemotePolicyScoreBinding(for: application), minRating: 0, size: 16)
            case .growthScore:
                StarRating(rating: offerGrowthScoreBinding(for: application), minRating: 0, size: 16)
                Text(scoringService.starText(for: application.offerGrowthScore))
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .teamCultureFit:
                StarRating(rating: offerTeamCultureFitBinding(for: application), minRating: 0, size: 16)
                Text(scoringService.starText(for: application.offerTeamCultureFitScore))
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .custom:
                TextField("Value", text: customValueTextBinding(factor: factor, application: application))
                    .textFieldStyle(.roundedBorder)
                StarRating(rating: factorScoreBinding(factor, application: application), minRating: 0, size: 16)
            }
        }
        .frame(width: 220, alignment: .leading)
    }

    private func card<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            content()
        }
        .padding(18)
        .appCard(cornerRadius: 16, elevated: true, shadow: false)
    }

    private func emptyStateCard(title: String, message: String) -> some View {
        card(title: title, subtitle: "") {
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
        )
    }

    private func tableHeaderCell(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .frame(width: 220, alignment: .leading)
    }

    private func loadWorksheetIfNeeded() async {
        guard aiReady, offeredApplications.count >= 2 else { return }
        isLoadingWorksheet = true
        defer { isLoadingWorksheet = false }

        do {
            _ = try worksheetService.loadOrCreateWorksheet(
                in: modelContext,
                offeredApplications: offeredApplications
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runAIAnalysis() async {
        guard aiReady, let worksheet else { return }
        isGeneratingAI = true
        defer { isGeneratingAI = false }

        do {
            let output = try await settingsViewModel.withAPIKeyWaterfall(for: aiProvider) { apiKey in
                try await OfferComparisonAnalysisService.generate(
                    provider: aiProvider,
                    apiKey: apiKey,
                    model: aiModel,
                    worksheet: worksheet,
                    applications: selectedApplications,
                    scoringService: scoringService
                )
            }

            worksheet.setRecommendationOutput(
                text: output.recommendationText,
                provider: aiProvider.rawValue,
                model: aiModel,
                citations: output.recommendationCitations
            )
            worksheet.setNegotiationOutput(
                text: output.negotiationText,
                provider: aiProvider.rawValue,
                model: aiModel,
                citations: output.negotiationCitations
            )
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

#if os(macOS)
    private func exportPDF() {
        guard let worksheet, let evaluation else { return }

        do {
            isExportingPDF = true
            defer { isExportingPDF = false }
            pdfDocument = try OfferComparisonPDFExportService.makeDocument(
                worksheet: worksheet,
                applications: applications,
                evaluation: evaluation,
                scoringService: scoringService
            )
            showingPDFExporter = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
#endif

    private func addCustomFactor() {
        guard let worksheet else { return }
        let title = customFactorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        do {
            _ = try worksheetService.addCustomFactor(titled: title, to: worksheet, context: modelContext)
            customFactorTitle = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCustomFactor(_ factor: OfferComparisonFactor) {
        do {
            try worksheetService.deleteCustomFactor(factor, context: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectionBinding(
        for application: JobApplication,
        worksheet: OfferComparisonWorksheet
    ) -> Binding<Bool> {
        Binding<Bool>(
            get: { worksheet.selectedApplicationIDs.contains(application.id) },
            set: { isSelected in
                do {
                    try worksheetService.setSelection(
                        applicationID: application.id,
                        isSelected: isSelected,
                        on: worksheet,
                        context: modelContext
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        )
    }

    private func factorWeightBinding(_ factor: OfferComparisonFactor) -> Binding<Int> {
        Binding<Int>(
            get: { factor.weight },
            set: { newValue in
                factor.setWeight(newValue)
                saveContext()
            }
        )
    }

    private func factorTitleBinding(_ factor: OfferComparisonFactor) -> Binding<String> {
        Binding<String>(
            get: { factor.title },
            set: { newValue in
                factor.rename(newValue)
                saveContext()
            }
        )
    }

    private func factorScoreBinding(
        _ factor: OfferComparisonFactor,
        application: JobApplication
    ) -> Binding<Int> {
        Binding<Int>(
            get: { scoringService.score(for: factor, application: application) ?? 0 },
            set: { newValue in
                do {
                    try worksheetService.upsertValue(
                        for: factor,
                        applicationID: application.id,
                        displayText: factor.value(for: application.id)?.displayText,
                        score: newValue == 0 ? nil : newValue,
                        context: modelContext
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        )
    }

    private func customValueTextBinding(
        factor: OfferComparisonFactor,
        application: JobApplication
    ) -> Binding<String> {
        Binding<String>(
            get: { factor.value(for: application.id)?.displayText ?? "" },
            set: { newValue in
                do {
                    try worksheetService.upsertValue(
                        for: factor,
                        applicationID: application.id,
                        displayText: newValue,
                        score: factor.value(for: application.id)?.score,
                        context: modelContext
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        )
    }

    private func offerPTOTextBinding(for application: JobApplication) -> Binding<String> {
        Binding<String>(
            get: { application.offerPTOText ?? "" },
            set: { newValue in
                application.setOfferPTO(text: newValue, score: application.offerPTOScore)
                saveContext()
            }
        )
    }

    private func offerPTOScoreBinding(for application: JobApplication) -> Binding<Int> {
        Binding<Int>(
            get: { application.offerPTOScore ?? 0 },
            set: { newValue in
                application.setOfferPTO(text: application.offerPTOText, score: newValue == 0 ? nil : newValue)
                saveContext()
            }
        )
    }

    private func offerRemotePolicyTextBinding(for application: JobApplication) -> Binding<String> {
        Binding<String>(
            get: { application.offerRemotePolicyText ?? "" },
            set: { newValue in
                application.setOfferRemotePolicy(text: newValue, score: application.offerRemotePolicyScore)
                saveContext()
            }
        )
    }

    private func offerRemotePolicyScoreBinding(for application: JobApplication) -> Binding<Int> {
        Binding<Int>(
            get: { application.offerRemotePolicyScore ?? 0 },
            set: { newValue in
                application.setOfferRemotePolicy(text: application.offerRemotePolicyText, score: newValue == 0 ? nil : newValue)
                saveContext()
            }
        )
    }

    private func offerGrowthScoreBinding(for application: JobApplication) -> Binding<Int> {
        Binding<Int>(
            get: { application.offerGrowthScore ?? 0 },
            set: { newValue in
                application.setOfferGrowthScore(newValue == 0 ? nil : newValue)
                saveContext()
            }
        )
    }

    private func offerTeamCultureFitBinding(for application: JobApplication) -> Binding<Int> {
        Binding<Int>(
            get: { application.offerTeamCultureFitScore ?? 0 },
            set: { newValue in
                application.setOfferTeamCultureFitScore(newValue == 0 ? nil : newValue)
                saveContext()
            }
        )
    }
}
