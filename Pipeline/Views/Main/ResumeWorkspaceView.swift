import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import WebKit
import PipelineKit
#if os(macOS)
import AppKit
#endif

struct ResumeWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var revisions: [ResumeMasterRevision] = []

    @State private var editorJSON: String = ""
    @State private var showingImporter = false
    @State private var showingHistory = false
    @State private var historySheetWidth: CGFloat = 980
    @State private var validationErrorMessage: String?
    @State private var actionError: String?

    @State private var exportingJSON = false
    @State private var jsonDocument = ResumeJSONFileDocument(text: "{}")

    @State private var exportingPDF = false
    @State private var pdfDocument = ResumePDFFileDocument(data: Data())

    private var currentRevision: ResumeMasterRevision? {
        revisions.first(where: { $0.isCurrent }) ?? revisions.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Resume")
                        .font(.title2)
                        .fontWeight(.semibold)

                    if let currentRevision {
                        Text("Current revision: \(currentRevision.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No master resume saved yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button("Import JSON") {
                    showingImporter = true
                }
                .buttonStyle(.bordered)

                Button("History") {
#if os(macOS)
                    historySheetWidth = preferredHistorySheetWidth()
#endif
                    showingHistory = true
                }
                .buttonStyle(.bordered)

                Button("Export JSON") {
                    exportCurrentJSON()
                }
                .buttonStyle(.bordered)
                .disabled(currentRevision == nil)

                Button("Export PDF") {
                    Task { await exportCurrentPDF() }
                }
                .buttonStyle(.bordered)
                .disabled(currentRevision == nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Master Resume JSON")
                    .font(.headline)

                JSONCodeEditor(text: $editorJSON)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.secondary.opacity(0.08))
                    )

                if let validationErrorMessage {
                    Label(validationErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                        .textSelection(.enabled)
                }

                if let revision = currentRevision,
                   !revision.unknownFieldPaths.isEmpty {
                    Label("Preserved in JSON, not rendered in PDF.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Button("Save as New Master Revision") {
                        saveCurrentEditorAsRevision()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accent)

                    Spacer()
                }
            }
            .padding(20)
        }
        .onAppear {
            loadMasterRevisions()
            editorJSON = currentRevision?.rawJSON ?? defaultResumePlaceholder
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer {
                    if access {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) else {
                    throw ResumeSchemaValidationError.invalidJSON
                }
                try importAndSaveMasterJSON(text)
            } catch {
                handleValidationError(error)
            }
        }
        .sheet(isPresented: $showingHistory) {
            ResumeMasterHistoryView(
                revisions: $revisions,
                refreshRevisions: {
                    loadMasterRevisions()
                }
            )
#if os(macOS)
            .frame(
                minWidth: historySheetWidth,
                idealWidth: historySheetWidth,
                maxWidth: historySheetWidth,
                minHeight: 620
            )
#endif
        }
        .fileExporter(
            isPresented: $exportingJSON,
            document: jsonDocument,
            contentType: .json,
            defaultFilename: "pipeline-resume"
        ) { _ in }
        .fileExporter(
            isPresented: $exportingPDF,
            document: pdfDocument,
            contentType: .pdf,
            defaultFilename: "pipeline-resume"
        ) { _ in }
        .alert("Resume Action Failed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "Unknown error")
        }
    }

    private func saveCurrentEditorAsRevision() {
        do {
            let validation = try ResumeSchemaValidator.validate(jsonText: editorJSON)
            _ = try ResumeStoreService.saveMasterRevision(
                rawJSON: validation.normalizedJSON,
                unknownFieldPaths: validation.unknownFieldPaths,
                in: modelContext
            )
            validationErrorMessage = nil
            loadMasterRevisions()
            editorJSON = validation.normalizedJSON
        } catch {
            handleValidationError(error)
        }
    }

    private func importAndSaveMasterJSON(_ jsonText: String) throws {
        let validation = try ResumeSchemaValidator.validate(jsonText: jsonText)
        _ = try ResumeStoreService.saveMasterRevision(
            rawJSON: validation.normalizedJSON,
            unknownFieldPaths: validation.unknownFieldPaths,
            in: modelContext
        )
        validationErrorMessage = nil
        loadMasterRevisions()
        editorJSON = validation.normalizedJSON
    }

    private func loadMasterRevisions() {
        do {
            revisions = try ResumeStoreService.masterRevisions(in: modelContext)
        } catch {
            actionError = error.localizedDescription
            revisions = []
        }
    }

    private func handleValidationError(_ error: Error) {
        if let validationError = error as? ResumeSchemaValidationError {
            validationErrorMessage = validationError.errorDescription ?? "Resume JSON failed validation."
            actionError = nil
            return
        }

        validationErrorMessage = nil
        actionError = error.localizedDescription
    }

    private func exportCurrentJSON() {
        guard let revision = currentRevision else { return }
        do {
            jsonDocument = try ResumeJSONExportService.makeDocument(json: revision.rawJSON)
            exportingJSON = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func exportCurrentPDF() async {
        guard let revision = currentRevision else { return }
        do {
            pdfDocument = try await ResumePDFExportService.makeDocument(json: revision.rawJSON)
            exportingPDF = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    private var defaultResumePlaceholder: String {
        """
        {
          "name": "",
          "contact": {
            "phone": "",
            "email": "",
            "linkedin": "",
            "github": ""
          },
          "education": [],
          "summary": "",
          "experience": [],
          "projects": [],
          "skills": {}
        }
        """
    }

#if os(macOS)
    private func preferredHistorySheetWidth() -> CGFloat {
        let windowWidth = NSApp.keyWindow?.frame.width ?? NSApp.mainWindow?.frame.width ?? 1220
        let targetWidth = windowWidth * 0.8
        return max(920, min(targetWidth, 1680))
    }
#endif
}

struct ResumeMasterHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Binding private var revisions: [ResumeMasterRevision]

    @State private var actionError: String?
    @State private var expandedRevisionIDs: Set<UUID> = []

    @State private var exportingJSON = false
    @State private var jsonDocument = ResumeJSONFileDocument(text: "{}")
    @State private var exportingPDF = false
    @State private var pdfDocument = ResumePDFFileDocument(data: Data())
    private let refreshRevisions: (() -> Void)?

    init(
        revisions: Binding<[ResumeMasterRevision]>,
        refreshRevisions: (() -> Void)? = nil
    ) {
        self._revisions = revisions
        self.refreshRevisions = refreshRevisions
    }

    var body: some View {
        NavigationStack {
            Group {
                if revisions.isEmpty {
                    ContentUnavailableView(
                        "No Master Revisions",
                        systemImage: "doc.text",
                        description: Text("Import JSON or save from the editor to create your first master revision.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(revisions.count) revision\(revisions.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ForEach(revisions, id: \.id) { revision in
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text(revision.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.headline)
                                            .fontWeight(.semibold)

                                        if revision.isCurrent {
                                            Text("Current")
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(Capsule().fill(DesignSystem.Colors.accent.opacity(0.2)))
                                        }

                                        Spacer()

                                        Button {
                                            toggleDiff(for: revision)
                                        } label: {
                                            Label(
                                                expandedRevisionIDs.contains(revision.id) ? "Hide Diff" : "Show Diff",
                                                systemImage: expandedRevisionIDs.contains(revision.id) ? "chevron.up.circle.fill" : "chevron.down.circle.fill"
                                            )
                                            .font(.subheadline.weight(.semibold))
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(DesignSystem.Colors.accent)
                                        .controlSize(.large)
                                    }

                                    if !revision.unknownFieldPaths.isEmpty {
                                        Label("\(revision.unknownFieldPaths.count) fields are preserved but not rendered in PDF", systemImage: "info.circle")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    HStack(spacing: 12) {
                                        Button("Restore") {
                                            restoreRevision(revision)
                                        }
                                        .buttonStyle(.bordered)

                                        Button("Export JSON") {
                                            exportJSON(revision)
                                        }
                                        .buttonStyle(.bordered)

                                        Button("Export PDF") {
                                            Task { await exportPDF(revision) }
                                        }
                                        .buttonStyle(.bordered)

                                        Spacer()

                                        Button("Delete", role: .destructive) {
                                            deleteRevision(revision)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    .controlSize(.large)

                                    if expandedRevisionIDs.contains(revision.id) {
                                        diffSection(for: revision)
                                    }
                                }
                                .padding(16)
                                .appCard(cornerRadius: 12, elevated: true, shadow: false)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Master Resume History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear {
            refreshRevisions?()
        }
        .fileExporter(
            isPresented: $exportingJSON,
            document: jsonDocument,
            contentType: .json,
            defaultFilename: "pipeline-resume"
        ) { _ in }
        .fileExporter(
            isPresented: $exportingPDF,
            document: pdfDocument,
            contentType: .pdf,
            defaultFilename: "pipeline-resume"
        ) { _ in }
        .alert("History Action Failed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "Unknown error")
        }
    }

    private func restoreRevision(_ revision: ResumeMasterRevision) {
        do {
            try ResumeStoreService.restoreMasterRevision(revision, in: modelContext)
            refreshRevisions?()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func deleteRevision(_ revision: ResumeMasterRevision) {
        do {
            try ResumeStoreService.deleteMasterRevision(revision, in: modelContext)
            refreshRevisions?()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func exportJSON(_ revision: ResumeMasterRevision) {
        do {
            jsonDocument = try ResumeJSONExportService.makeDocument(json: revision.rawJSON)
            exportingJSON = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func exportPDF(_ revision: ResumeMasterRevision) async {
        do {
            pdfDocument = try await ResumePDFExportService.makeDocument(json: revision.rawJSON)
            exportingPDF = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func toggleDiff(for revision: ResumeMasterRevision) {
        if expandedRevisionIDs.contains(revision.id) {
            expandedRevisionIDs.remove(revision.id)
        } else {
            expandedRevisionIDs.insert(revision.id)
        }
    }

    private func diffSection(for revision: ResumeMasterRevision) -> some View {
        Group {
            if let previous = previousRevision(for: revision) {
                let diff = ResumeRevisionDiffService.diff(from: previous.rawJSON, to: revision.rawJSON)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Diff vs \(previous.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("+\(diff.addedLineCount)  -\(diff.removedLineCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }

                    if diff.hasChanges {
                        ForEach(Array(diff.hunks.enumerated()), id: \.offset) { _, hunk in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(hunk.header)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.12))

                                ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                                    diffLineRow(line)
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                        }
                    } else {
                        Text("No content changes in this revision.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.07))
                )
            } else {
                Text("No previous revision to compare.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.08))
                    )
            }
        }
    }

    private func diffLineRow(_ line: ResumeDiffLine) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(line.oldLineNumber.map(String.init) ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .trailing)

            Text(line.newLineNumber.map(String.init) ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .trailing)

            Text("\(linePrefix(line.kind))\(line.content)")
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(lineBackgroundColor(line.kind))
    }

    private func linePrefix(_ kind: ResumeDiffLine.Kind) -> String {
        switch kind {
        case .added:
            return "+"
        case .removed:
            return "-"
        case .context:
            return " "
        }
    }

    private func lineBackgroundColor(_ kind: ResumeDiffLine.Kind) -> Color {
        switch kind {
        case .added:
            return Color.green.opacity(0.18)
        case .removed:
            return Color.red.opacity(0.18)
        case .context:
            return Color.clear
        }
    }

    private func previousRevision(for revision: ResumeMasterRevision) -> ResumeMasterRevision? {
        guard let index = revisions.firstIndex(where: { $0.id == revision.id }) else {
            return nil
        }

        let previousIndex = revisions.index(after: index)
        guard revisions.indices.contains(previousIndex) else {
            return nil
        }

        return revisions[previousIndex]
    }

}

struct ResumeTailoringView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var application: JobApplication

    @State private var settingsViewModel = SettingsViewModel()
    @State private var masterRevision: ResumeMasterRevision?
    @State private var preflightError: String?

    @State private var isGenerating = false
    @State private var patches: [ResumePatch] = []
    @State private var sectionGaps: [String] = []
    @State private var safetyRejections: [ResumePatchRejection] = []

    @State private var acceptedPatchIDs: Set<UUID> = []
    @State private var rejectedPatchIDs: Set<UUID> = []

    @State private var editedJSON = ""
    @State private var actionError: String?

    @State private var exportingJSON = false
    @State private var jsonDocument = ResumeJSONFileDocument(text: "{}")
    @State private var exportingPDF = false
    @State private var pdfDocument = ResumePDFFileDocument(data: Data())

    var body: some View {
        NavigationStack {
            Group {
                if let preflightError {
                    preflightErrorView(preflightError)
                } else {
                    contentView
                }
            }
            .navigationTitle("Tailor Resume")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear {
            runPreflight()
        }
        .fileExporter(
            isPresented: $exportingJSON,
            document: jsonDocument,
            contentType: .json,
            defaultFilename: "tailored-resume"
        ) { _ in }
        .fileExporter(
            isPresented: $exportingPDF,
            document: pdfDocument,
            contentType: .pdf,
            defaultFilename: "tailored-resume"
        ) { _ in }
        .alert("Tailoring Failed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "Unknown error")
        }
    }

    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Target: \(application.role) at \(application.companyName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button {
                        Task { await generateSuggestions() }
                    } label: {
                        if isGenerating {
                            ProgressView()
                        } else {
                            Label("Generate Suggestions", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accent)
                    .disabled(isGenerating)
                }

                if !sectionGaps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Coverage Gaps")
                            .font(.headline)
                        ForEach(sectionGaps, id: \.self) { gap in
                            Label(gap, systemImage: "exclamationmark.circle")
                                .font(.caption)
                        }
                    }
                    .padding(12)
                    .appCard(cornerRadius: 10, elevated: true, shadow: false)
                }

                if !safetyRejections.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Safety Rejections")
                            .font(.headline)
                        ForEach(Array(safetyRejections.enumerated()), id: \.offset) { _, rejection in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rejection.patch.path)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(rejection.reason)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .appCard(cornerRadius: 10, elevated: true, shadow: false)
                }

                ForEach(patches) { patch in
                    patchCard(patch)
                }

                if !patches.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Final Resume JSON")
                            .font(.headline)

                        JSONCodeEditor(text: $editedJSON)
                            .frame(minHeight: 220)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.secondary.opacity(0.08))
                            )

                        HStack(spacing: 10) {
                            Button("Export JSON") {
                                exportJSON()
                            }
                            .buttonStyle(.bordered)

                            Button("Export PDF") {
                                Task { await exportPDF() }
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button("Save Tailored Resume") {
                                saveSnapshot()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DesignSystem.Colors.accent)
                        }
                    }
                    .padding(12)
                    .appCard(cornerRadius: 10, elevated: true, shadow: false)
                }
            }
            .padding(16)
        }
    }

    private func preflightErrorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
        }
    }

    private func patchCard(_ patch: ResumePatch) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(patch.operation.rawValue.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.18)))

                Text(patch.path)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if patch.operation == .remove {
                    Label("Deletion", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }

                Spacer()
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Before")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(patch.beforeValue?.displayText ?? "<empty>")
                        .font(.caption)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("After")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(patch.afterValue?.displayText ?? "<removed>")
                        .font(.caption)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(patch.reason)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                Button {
                    acceptedPatchIDs.insert(patch.id)
                    rejectedPatchIDs.remove(patch.id)
                    refreshEditedJSON()
                } label: {
                    Label("Accept", systemImage: acceptedPatchIDs.contains(patch.id) ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.bordered)

                Button {
                    rejectedPatchIDs.insert(patch.id)
                    acceptedPatchIDs.remove(patch.id)
                    refreshEditedJSON()
                } label: {
                    Label("Reject", systemImage: rejectedPatchIDs.contains(patch.id) ? "xmark.circle.fill" : "circle")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(12)
        .appCard(cornerRadius: 10, elevated: true, shadow: false)
    }

    private func runPreflight() {
        do {
            masterRevision = try ResumeStoreService.currentMasterRevision(in: modelContext)
            guard masterRevision != nil else {
                preflightError = "Save a master resume in the Resume section before tailoring."
                return
            }
        } catch {
            preflightError = error.localizedDescription
            return
        }

        guard let jd = application.jobDescription,
              !jd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            preflightError = "This job is missing a job description. Add one in Edit Application before tailoring."
            return
        }

        let provider = settingsViewModel.selectedAIProvider
        let model = settingsViewModel.preferredModel(for: provider)

        if model.isEmpty {
            preflightError = "No compatible AI model configured. Please check Settings."
            return
        }

        do {
            let keys = try settingsViewModel.apiKeys(for: provider)
            if keys.isEmpty {
                preflightError = "No API key configured for \(provider.rawValue)."
                return
            }
        } catch {
            preflightError = "Could not read API key for \(provider.rawValue)."
            return
        }

        preflightError = nil
        editedJSON = masterRevision?.rawJSON ?? ""
    }

    @MainActor
    private func generateSuggestions() async {
        guard preflightError == nil,
              let masterRevision,
              let jobDescription = application.jobDescription
        else {
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            let provider = settingsViewModel.selectedAIProvider
            let model = settingsViewModel.preferredModel(for: provider)

            let result = try await settingsViewModel.withAPIKeyWaterfall(for: provider) { apiKey in
                try await ResumeTailoringService.generateSuggestions(
                    provider: provider,
                    apiKey: apiKey,
                    model: model,
                    resumeJSON: masterRevision.rawJSON,
                    company: application.companyName,
                    role: application.role,
                    jobDescription: jobDescription
                )
            }

            let validation = try ResumePatchSafetyValidator.validate(
                patches: result.patches,
                originalJSON: masterRevision.rawJSON
            )

            patches = validation.accepted
            safetyRejections = validation.rejected
            sectionGaps = result.sectionGaps

            acceptedPatchIDs = []
            rejectedPatchIDs = []
            refreshEditedJSON()
        } catch let keyError as SettingsViewModel.APIKeyValidationError {
            actionError = keyError.localizedDescription
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func refreshEditedJSON() {
        guard let masterRevision else { return }

        do {
            editedJSON = try ResumePatchApplier.apply(
                patches: patches,
                acceptedPatchIDs: acceptedPatchIDs,
                to: masterRevision.rawJSON
            )
        } catch {
            editedJSON = masterRevision.rawJSON
        }
    }

    private func saveSnapshot() {
        do {
            let validated = try ResumeSchemaValidator.validate(jsonText: editedJSON)
            _ = try ResumeStoreService.createJobSnapshot(
                for: application,
                rawJSON: validated.normalizedJSON,
                acceptedPatchIDs: Array(acceptedPatchIDs),
                rejectedPatchIDs: Array(rejectedPatchIDs),
                sectionGaps: sectionGaps,
                sourceMasterRevisionID: masterRevision?.id,
                in: modelContext
            )
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func exportJSON() {
        do {
            jsonDocument = try ResumeJSONExportService.makeDocument(json: editedJSON)
            exportingJSON = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func exportPDF() async {
        do {
            pdfDocument = try await ResumePDFExportService.makeDocument(json: editedJSON)
            exportingPDF = true
        } catch {
            actionError = error.localizedDescription
        }
    }
}

struct JobResumePanel: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var application: JobApplication

    @State private var showingTailor = false
    @State private var actionError: String?

    @State private var exportingJSON = false
    @State private var jsonDocument = ResumeJSONFileDocument(text: "{}")

    @State private var exportingPDF = false
    @State private var pdfDocument = ResumePDFFileDocument(data: Data())

    var body: some View {
        let snapshots = application.sortedResumeSnapshots

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Resume Versions", systemImage: "doc.text")
                    .font(.headline)

                Spacer()

                Button {
                    showingTailor = true
                } label: {
                    Label("Tailor Resume", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
            }

            if snapshots.isEmpty {
                Text("No tailored resumes attached to this job yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshots) { snapshot in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("Accepted: \(snapshot.acceptedPatchIDs.count)  Rejected: \(snapshot.rejectedPatchIDs.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("JSON") {
                                exportJSON(snapshot)
                            }
                            .buttonStyle(.bordered)

                            Button("PDF") {
                                Task { await exportPDF(snapshot) }
                            }
                            .buttonStyle(.bordered)

                            Button("Delete", role: .destructive) {
                                deleteSnapshot(snapshot)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(16)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
        .sheet(isPresented: $showingTailor) {
            ResumeTailoringView(application: application)
        }
        .fileExporter(
            isPresented: $exportingJSON,
            document: jsonDocument,
            contentType: .json,
            defaultFilename: "tailored-resume"
        ) { _ in }
        .fileExporter(
            isPresented: $exportingPDF,
            document: pdfDocument,
            contentType: .pdf,
            defaultFilename: "tailored-resume"
        ) { _ in }
        .alert("Resume Action Failed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "Unknown error")
        }
    }

    private func deleteSnapshot(_ snapshot: ResumeJobSnapshot) {
        do {
            try ResumeStoreService.deleteJobSnapshot(snapshot, in: modelContext)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func exportJSON(_ snapshot: ResumeJobSnapshot) {
        do {
            jsonDocument = try ResumeJSONExportService.makeDocument(json: snapshot.rawJSON)
            exportingJSON = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func exportPDF(_ snapshot: ResumeJobSnapshot) async {
        do {
            pdfDocument = try await ResumePDFExportService.makeDocument(json: snapshot.rawJSON)
            exportingPDF = true
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private struct JSONCodeEditor: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        JSONCodeEditorRepresentable(text: $text, isDarkMode: colorScheme == .dark)
    }
}

#if os(macOS)
private typealias JSONEditorPlatformRepresentable = NSViewRepresentable
#else
private typealias JSONEditorPlatformRepresentable = UIViewRepresentable
#endif

@MainActor
func prewarmJSONEditorIfNeeded() {
    JSONCodeEditorRepresentable.prewarmIfNeeded()
}

private struct JSONCodeEditorRepresentable: JSONEditorPlatformRepresentable {
    @Binding var text: String
    let isDarkMode: Bool

    private static let bridgeName = "pipelineJSONEditorChanged"
    private static let sharedPool = SharedWebViewPool()

    private static let editorHTML = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0" />
      <style>
        html, body, #editor {
          width: 100%;
          height: 100%;
          margin: 0;
          padding: 0;
          overflow: hidden;
          background: transparent;
        }
      </style>
    </head>
    <body>
      <div id="editor"></div>
      <script src="https://cdn.jsdelivr.net/npm/ace-builds@1.37.0/src-min-noconflict/ace.js"></script>
      <script src="https://cdn.jsdelivr.net/npm/ace-builds@1.37.0/src-min-noconflict/mode-json.js"></script>
      <script src="https://cdn.jsdelivr.net/npm/ace-builds@1.37.0/src-min-noconflict/theme-github_light_default.js"></script>
      <script src="https://cdn.jsdelivr.net/npm/ace-builds@1.37.0/src-min-noconflict/theme-github_dark.js"></script>
      <script>
        (function () {
          var bridgeName = "pipelineJSONEditorChanged";
          var editor = null;
          var fallbackTextarea = null;
          var applyingExternalValue = false;

          function postValue(value) {
            if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers[bridgeName]) {
              return;
            }
            window.webkit.messageHandlers[bridgeName].postMessage(value);
          }

          function setupFallbackEditor() {
            var textarea = document.createElement("textarea");
            textarea.style.width = "100%";
            textarea.style.height = "100%";
            textarea.style.border = "none";
            textarea.style.outline = "none";
            textarea.style.resize = "none";
            textarea.style.padding = "14px";
            textarea.style.fontFamily = "SF Mono, Menlo, Monaco, ui-monospace, monospace";
            textarea.style.fontSize = "14px";
            textarea.style.lineHeight = "1.45";
            textarea.style.boxSizing = "border-box";
            textarea.style.tabSize = "2";
            document.body.replaceChildren(textarea);
            fallbackTextarea = textarea;

            textarea.addEventListener("input", function () {
              postValue(textarea.value);
            });

            window.pipelineJSONEditor = {
              setText: function (value) { textarea.value = value || ""; },
              setTheme: function (isDarkMode) {
                if (!fallbackTextarea) {
                  return;
                }
                fallbackTextarea.style.color = isDarkMode ? "#d4d4d8" : "#1f2937";
                fallbackTextarea.style.background = isDarkMode ? "#111827" : "#ffffff";
              }
            };
          }

          function setupAceEditor() {
            editor = ace.edit("editor");
            editor.session.setMode("ace/mode/json");
            editor.session.setUseWorker(false);
            editor.session.setUseWrapMode(true);
            editor.session.setFoldStyle("markbeginend");
            editor.setShowFoldWidgets(true);
            editor.setOption("tabSize", 2);
            editor.setOption("useSoftTabs", true);
            editor.setOption("fontFamily", "SF Mono, Menlo, Monaco, ui-monospace, monospace");
            editor.setOption("fontSize", "14px");
            editor.setOption("showPrintMargin", false);
            editor.setOption("highlightActiveLine", true);
            editor.setOption("highlightGutterLine", true);
            editor.setOption("displayIndentGuides", true);
            editor.setOption("showLineNumbers", true);
            editor.setOption("behavioursEnabled", true);
            editor.setOption("scrollPastEnd", 0.25);
            editor.renderer.setScrollMargin(10, 10);

            editor.session.on("change", function () {
              if (applyingExternalValue) {
                return;
              }
              postValue(editor.getValue());
            });

            window.pipelineJSONEditor = {
              setText: function (value) {
                var incoming = value || "";
                if (editor.getValue() === incoming) {
                  return;
                }

                applyingExternalValue = true;
                var cursor = editor.getCursorPosition();
                var scrollTop = editor.session.getScrollTop();
                var scrollLeft = editor.session.getScrollLeft();
                editor.setValue(incoming, -1);
                editor.moveCursorToPosition(cursor);
                editor.session.setScrollTop(scrollTop);
                editor.session.setScrollLeft(scrollLeft);
                applyingExternalValue = false;
              },
              setTheme: function (isDarkMode) {
                editor.setTheme(isDarkMode ? "ace/theme/github_dark" : "ace/theme/github_light_default");
              }
            };
          }

          if (typeof ace === "undefined") {
            setupFallbackEditor();
          } else {
            setupAceEditor();
          }
        })();
      </script>
    </body>
    </html>
    """

    @MainActor
    static func prewarmIfNeeded() {
        sharedPool.prewarmIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isDarkMode: isDarkMode)
    }

#if os(macOS)
    func makeNSView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        updateWebView(webView, context: context)
    }
#else
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        updateWebView(webView, context: context)
    }
#endif

    private func makeWebView(context: Context) -> WKWebView {
        let (webView, isReady) = Self.sharedPool.acquireWebView(for: context.coordinator)
#if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
#else
        webView.isOpaque = false
        webView.backgroundColor = .clear
#endif
        context.coordinator.webView = webView
        if isReady {
            context.coordinator.markReadyFromPrewarm()
        }
        return webView
    }

    private func updateWebView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(text: text, isDarkMode: isDarkMode)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        @Binding private var text: String
        private var isDarkMode: Bool
        private var isReady = false
        private var lastSyncedText: String
        private var lastSyncedTheme: Bool?

        weak var webView: WKWebView?

        init(text: Binding<String>, isDarkMode: Bool) {
            _text = text
            self.isDarkMode = isDarkMode
            self.lastSyncedText = text.wrappedValue
            super.init()
        }

        deinit {
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: JSONCodeEditorRepresentable.bridgeName)
        }

        func update(text: String, isDarkMode: Bool) {
            self.isDarkMode = isDarkMode
            syncTextIfNeeded(text)
            syncThemeIfNeeded()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            JSONCodeEditorRepresentable.sharedPool.markLoaded(webView)
            syncTextIfNeeded(text)
            syncThemeIfNeeded(force: true)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == JSONCodeEditorRepresentable.bridgeName,
                  let updatedText = message.body as? String else {
                return
            }

            lastSyncedText = updatedText
            if updatedText != text {
                DispatchQueue.main.async { [weak self] in
                    self?.text = updatedText
                }
            }
        }

        private func syncTextIfNeeded(_ newText: String) {
            guard isReady, newText != lastSyncedText else { return }
            lastSyncedText = newText
            let js = "window.pipelineJSONEditor && window.pipelineJSONEditor.setText(\(Self.quotedJSString(newText)));"
            webView?.evaluateJavaScript(js)
        }

        private func syncThemeIfNeeded(force: Bool = false) {
            guard isReady else { return }
            guard force || lastSyncedTheme != isDarkMode else { return }
            lastSyncedTheme = isDarkMode
            let js = "window.pipelineJSONEditor && window.pipelineJSONEditor.setTheme(\(isDarkMode ? "true" : "false"));"
            webView?.evaluateJavaScript(js)
        }

        private static func quotedJSString(_ value: String) -> String {
            guard let encoded = try? JSONSerialization.data(withJSONObject: [value]),
                  var arrayLiteral = String(data: encoded, encoding: .utf8) else {
                return "\"\""
            }
            arrayLiteral.removeFirst()
            arrayLiteral.removeLast()
            return arrayLiteral
        }

        func markReadyFromPrewarm() {
            guard !isReady else { return }
            isReady = true
            syncTextIfNeeded(text)
            syncThemeIfNeeded(force: true)
        }
    }

    @MainActor
    private final class SharedWebViewPool: NSObject, WKNavigationDelegate {
        private final class NoopScriptMessageHandler: NSObject, WKScriptMessageHandler {
            func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}
        }

        private let noOpHandler = NoopScriptMessageHandler()
        private var prewarmedWebView: WKWebView?
        private var prewarmedWebViewReady = false

        func prewarmIfNeeded() {
            _ = ensurePrewarmedWebView()
        }

        func acquireWebView(for coordinator: Coordinator) -> (WKWebView, Bool) {
            let webView: WKWebView
            let isReady: Bool

            if let cachedWebView = prewarmedWebView, cachedWebView.superview == nil {
                webView = cachedWebView
                isReady = prewarmedWebViewReady
            } else {
                webView = makeEditorWebView(messageHandler: noOpHandler, navigationDelegate: self)
                isReady = false
            }

            let userContentController = webView.configuration.userContentController
            userContentController.removeScriptMessageHandler(forName: JSONCodeEditorRepresentable.bridgeName)
            userContentController.add(coordinator, name: JSONCodeEditorRepresentable.bridgeName)
            webView.navigationDelegate = coordinator

            return (webView, isReady)
        }

        func markLoaded(_ webView: WKWebView) {
            guard webView === prewarmedWebView else { return }
            prewarmedWebViewReady = true
        }

        private func ensurePrewarmedWebView() -> WKWebView {
            if let existing = prewarmedWebView {
                return existing
            }

            let webView = makeEditorWebView(messageHandler: noOpHandler, navigationDelegate: self)
            prewarmedWebView = webView
            return webView
        }

        private func makeEditorWebView(
            messageHandler: WKScriptMessageHandler,
            navigationDelegate: WKNavigationDelegate
        ) -> WKWebView {
            let userContentController = WKUserContentController()
            userContentController.add(messageHandler, name: JSONCodeEditorRepresentable.bridgeName)

            let configuration = WKWebViewConfiguration()
            configuration.userContentController = userContentController

            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = navigationDelegate
#if os(macOS)
            webView.setValue(false, forKey: "drawsBackground")
#else
            webView.isOpaque = false
            webView.backgroundColor = .clear
#endif

            let editorBaseURL = Bundle.main.resourceURL?
                .appendingPathComponent("JSONEditor", isDirectory: true)
            webView.loadHTMLString(
                JSONCodeEditorRepresentable.editorHTML,
                baseURL: editorBaseURL ?? Bundle.main.resourceURL ?? URL(string: "https://localhost/")
            )
            return webView
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard webView === prewarmedWebView else { return }
            prewarmedWebViewReady = true
        }
    }
}
