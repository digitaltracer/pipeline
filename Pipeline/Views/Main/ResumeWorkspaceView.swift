import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import WebKit
import PipelineKit
#if os(macOS)
import AppKit
#endif

private enum ResumeExportFormat {
    case json
    case pdf
}

private enum ResumeExportFilename {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MM-yy"
        return formatter
    }()

    static func make(companyName: String?) -> String {
        let company = sanitizeCompanyName(companyName)
        let date = dateFormatter.string(from: Date())
        return "\(company)-resume-\(date)"
    }

    private static func sanitizeCompanyName(_ companyName: String?) -> String {
        let trimmed = (companyName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "master" }

        var sanitized = ""
        var previousWasHyphen = false
        for scalar in trimmed.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                sanitized.unicodeScalars.append(scalar)
                previousWasHyphen = false
            } else if !previousWasHyphen {
                sanitized.append("-")
                previousWasHyphen = true
            }
        }

        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? "master" : sanitized
    }
}

private extension View {
    @ViewBuilder
    func resumeFileExporter(
        isPresented: Binding<Bool>,
        format: ResumeExportFormat,
        jsonDocument: ResumeJSONFileDocument,
        pdfDocument: ResumePDFFileDocument,
        defaultFilename: String
    ) -> some View {
        switch format {
        case .json:
            fileExporter(
                isPresented: isPresented,
                document: jsonDocument,
                contentType: .json,
                defaultFilename: defaultFilename
            ) { _ in }
        case .pdf:
            fileExporter(
                isPresented: isPresented,
                document: pdfDocument,
                contentType: .pdf,
                defaultFilename: defaultFilename
            ) { _ in }
        }
    }
}

struct ResumeWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var revisions: [ResumeMasterRevision] = []

    @State private var editorJSON: String = ""
    @State private var showingImporter = false
    @State private var showingHistory = false
    @State private var historySheetWidth: CGFloat = 980
    @State private var validationErrorMessage: String?
    @State private var actionError: String?

    @State private var isExportingFile = false
    @State private var exportFormat: ResumeExportFormat = .json
    @State private var jsonDocument = ResumeJSONFileDocument(text: "{}")
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
        .resumeFileExporter(
            isPresented: $isExportingFile,
            format: exportFormat,
            jsonDocument: jsonDocument,
            pdfDocument: pdfDocument,
            defaultFilename: ResumeExportFilename.make(companyName: nil)
        )
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
            exportFormat = .json
            isExportingFile = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func exportCurrentPDF() async {
        guard let revision = currentRevision else { return }
        do {
            pdfDocument = try await ResumePDFExportService.makeDocument(json: revision.rawJSON)
            exportFormat = .pdf
            isExportingFile = true
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

    @State private var isExportingFile = false
    @State private var exportFormat: ResumeExportFormat = .json
    @State private var jsonDocument = ResumeJSONFileDocument(text: "{}")
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
        .resumeFileExporter(
            isPresented: $isExportingFile,
            format: exportFormat,
            jsonDocument: jsonDocument,
            pdfDocument: pdfDocument,
            defaultFilename: ResumeExportFilename.make(companyName: nil)
        )
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
            exportFormat = .json
            isExportingFile = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func exportPDF(_ revision: ResumeMasterRevision) async {
        do {
            pdfDocument = try await ResumePDFExportService.makeDocument(json: revision.rawJSON)
            exportFormat = .pdf
            isExportingFile = true
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
    @Environment(\.colorScheme) private var colorScheme

    @Bindable var application: JobApplication
    private let onClose: (() -> Void)?
    private let onUnsavedChangesChanged: ((Bool) -> Void)?

    @State private var settingsViewModel = SettingsViewModel()
    @State private var masterRevision: ResumeMasterRevision?
    @State private var preflightError: String?

    @State private var isGenerating = false
    @State private var patches: [ResumePatch] = []
    @State private var sectionGaps: [String] = []
    @State private var safetyRejections: [ResumePatchRejection] = []
    @State private var collapsedPatchIDs: Set<UUID> = []

    @State private var acceptedPatchIDs: Set<UUID> = []
    @State private var rejectedPatchIDs: Set<UUID> = []

    @State private var editedJSON = ""
    @State private var actionError: String?
    @State private var decisionToast: DecisionToast?
    @State private var lastDecisionSnapshot: DecisionSnapshot?
    @State private var toastDismissTask: Task<Void, Never>?

    @State private var isExportingFile = false
    @State private var exportFormat: ResumeExportFormat = .json
    @State private var jsonDocument = ResumeJSONFileDocument(text: "{}")
    @State private var pdfDocument = ResumePDFFileDocument(data: Data())
    @State private var hasTriggeredInitialGeneration = false
    @State private var lastPersistedJSON = ""
    @State private var lastPersistedAcceptedPatchIDs: Set<UUID> = []
    @State private var lastPersistedRejectedPatchIDs: Set<UUID> = []
    @State private var showingDiscardChangesConfirmation = false

    init(
        application: JobApplication,
        onClose: (() -> Void)? = nil,
        onUnsavedChangesChanged: ((Bool) -> Void)? = nil
    ) {
        self.application = application
        self.onClose = onClose
        self.onUnsavedChangesChanged = onUnsavedChangesChanged
    }

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
#if !os(macOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { requestClose() }
                        .keyboardShortcut(.cancelAction)
                }
#endif
            }
        }
#if os(macOS)
        .frame(minWidth: 1220, idealWidth: 1320, minHeight: 760, idealHeight: 880)
#endif
        .onAppear {
            runPreflight()
            triggerInitialGenerationIfNeeded()
            publishUnsavedChangesState()
        }
        .onChange(of: editedJSON) { _, _ in
            publishUnsavedChangesState()
        }
        .onChange(of: acceptedPatchIDs) { _, _ in
            publishUnsavedChangesState()
        }
        .onChange(of: rejectedPatchIDs) { _, _ in
            publishUnsavedChangesState()
        }
        .resumeFileExporter(
            isPresented: $isExportingFile,
            format: exportFormat,
            jsonDocument: jsonDocument,
            pdfDocument: pdfDocument,
            defaultFilename: ResumeExportFilename.make(companyName: application.companyName)
        )
        .alert("Tailoring Failed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "Unknown error")
        }
        .alert("Discard unsaved changes?", isPresented: $showingDiscardChangesConfirmation) {
            Button("Discard Changes", role: .destructive) {
                closeTailoringView()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsaved changes. Close without saving?")
        }
        .safeAreaInset(edge: .bottom) {
            if preflightError == nil, !patches.isEmpty {
                draftSummaryBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            }
        }
        .overlay(alignment: .bottom) {
            if let decisionToast {
                decisionToastView(decisionToast)
                    .padding(.horizontal, 16)
                    .padding(.bottom, patches.isEmpty ? 16 : 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onDisappear {
            toastDismissTask?.cancel()
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
                }

                if isGenerating {
                    generationInProgressCard
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

    private var generationInProgressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.22 : 0.14))
                        .frame(width: 34, height: 34)
                    Image(systemName: "sparkles")
                        .foregroundStyle(DesignSystem.Colors.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Generating Tailored Suggestions")
                        .font(.headline)
                    Text("Analyzing the job description, mapping your experience, and producing safe resume patches.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView()
                .progressViewStyle(.linear)
                .tint(DesignSystem.Colors.accent)

            HStack(spacing: 8) {
                statusChip("Extracting role requirements")
                statusChip("Matching resume evidence")
                statusChip("Validating safe edits")
            }
        }
        .padding(14)
        .appCard(cornerRadius: 12, elevated: true, shadow: false)
    }

    private func patchCard(_ patch: ResumePatch) -> some View {
        let isCollapsed = collapsedPatchIDs.contains(patch.id)
        let beforeText = patch.beforeValue?.displayText ?? ""
        let afterText = patch.afterValue?.displayText ?? ""
        let diffRows = ResumePatchSplitDiff.makeRows(before: beforeText, after: afterText)

        return VStack(alignment: .leading, spacing: 12) {
            patchHeaderRow(for: patch, isCollapsed: isCollapsed)

            if !isCollapsed {
                patchComparisonSection(rows: diffRows)
                reasonBox(reason: patch.reason)
                decisionRow(for: patch)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? Color(red: 0.12, green: 0.15, blue: 0.21) : Color(red: 0.93, green: 0.94, blue: 0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.09), lineWidth: 1)
        )
    }

    private func patchHeaderRow(for patch: ResumePatch, isCollapsed: Bool) -> some View {
        HStack(spacing: 10) {
            Text(patch.operation.rawValue.uppercased())
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.26 : 0.16)))
                .foregroundStyle(colorScheme == .dark ? Color.blue.opacity(0.92) : Color.blue.opacity(0.9))

            Text(patch.path)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            if let entryState = entryStateBadge(for: patch) {
                entryState
            }

            if let status = decisionStatus(for: patch) {
                decisionStatusBadge(status)
            }

            Spacer()

            Button {
                if isCollapsed {
                    collapsedPatchIDs.remove(patch.id)
                } else {
                    collapsedPatchIDs.insert(patch.id)
                }
            } label: {
                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func entryStateBadge(for patch: ResumePatch) -> AnyView? {
        switch patch.operation {
        case .add:
            return AnyView(
                Text("New entry")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(Color.green.opacity(colorScheme == .dark ? 0.95 : 0.9))
                    .background(Capsule().fill(Color.green.opacity(colorScheme == .dark ? 0.22 : 0.14)))
                    .overlay(
                        Capsule()
                            .stroke(Color.green.opacity(0.4), lineWidth: 1)
                    )
            )
        case .remove:
            return AnyView(
                Text("Removed entry")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(Color.red.opacity(colorScheme == .dark ? 0.95 : 0.85))
                    .background(Capsule().fill(Color.red.opacity(colorScheme == .dark ? 0.2 : 0.12)))
                    .overlay(
                        Capsule()
                            .stroke(Color.red.opacity(0.35), lineWidth: 1)
                    )
            )
        case .replace:
            return nil
        }
    }

    private func patchComparisonSection(rows: [ResumePatchSplitDiff.Row]) -> some View {
        VStack(spacing: 0) {
            githubSplitHeaderRow
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                githubSplitRow(row)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colorScheme == .dark ? Color(red: 0.09, green: 0.11, blue: 0.16) : Color(red: 0.96, green: 0.97, blue: 0.99))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var githubSplitHeaderRow: some View {
        HStack(spacing: 0) {
            Text("Old")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 58)
            Divider()
            Text("New")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 58)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            colorScheme == .dark
                ? Color.white.opacity(0.06)
                : Color.black.opacity(0.04)
        )
    }

    private func githubSplitRow(_ row: ResumePatchSplitDiff.Row) -> some View {
        HStack(spacing: 0) {
            githubSplitCell(
                lineNumber: row.oldLine,
                tokens: row.oldTokens,
                side: .old
            )

            Divider()

            githubSplitCell(
                lineNumber: row.newLine,
                tokens: row.newTokens,
                side: .new
            )
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.04))
                .frame(height: 0.5)
        }
    }

    private enum SplitSide {
        case old
        case new
    }

    private func githubSplitCell(
        lineNumber: Int?,
        tokens: [ResumePatchSplitDiff.Token],
        side: SplitSide
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(lineNumber.map(String.init) ?? "")
                .frame(width: 48, alignment: .trailing)
                .foregroundStyle(.secondary)
                .padding(.trailing, 8)

            Text(makeSplitDiffAttributedText(tokens: tokens, side: side))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .font(.system(size: 12, weight: .regular, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(splitCellBackgroundColor(tokens: tokens, side: side))
    }

    private func splitCellBackgroundColor(tokens: [ResumePatchSplitDiff.Token], side: SplitSide) -> Color {
        switch side {
        case .old:
            let hasRemoved = tokens.contains { $0.kind == .removed }
            return hasRemoved
                ? (colorScheme == .dark ? Color.red.opacity(0.12) : Color.red.opacity(0.07))
                : .clear
        case .new:
            let hasAdded = tokens.contains { $0.kind == .added }
            return hasAdded
                ? (colorScheme == .dark ? Color.green.opacity(0.12) : Color.green.opacity(0.07))
                : .clear
        }
    }

    private func makeSplitDiffAttributedText(
        tokens: [ResumePatchSplitDiff.Token],
        side: SplitSide
    ) -> AttributedString {
        guard !tokens.isEmpty else { return AttributedString() }

        var attributed = AttributedString()
        let values = tokens.map(\.value)

        for index in values.indices {
            let token = tokens[index]
            var segment = AttributedString(token.value)
            segment.foregroundColor = colorScheme == .dark ? Color.white.opacity(0.86) : Color.black.opacity(0.78)

            if token.kind == .removed, side == .old {
                segment.foregroundColor = colorScheme == .dark ? Color.red.opacity(0.9) : Color.red.opacity(0.84)
                segment.backgroundColor = colorScheme == .dark ? Color.red.opacity(0.22) : Color.red.opacity(0.18)
                segment.strikethroughStyle = .single
            } else if token.kind == .added, side == .new {
                segment.foregroundColor = colorScheme == .dark ? Color.green.opacity(0.92) : Color.green.opacity(0.84)
                segment.backgroundColor = colorScheme == .dark ? Color.green.opacity(0.2) : Color.green.opacity(0.16)
            }

            attributed += segment
            if index < values.count - 1 {
                attributed += AttributedString(" ")
            }
        }

        return attributed
    }

    private func reasonBox(reason: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("Why:")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.blue.opacity(colorScheme == .dark ? 0.9 : 0.84))
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colorScheme == .dark ? Color.blue.opacity(0.12) : Color.blue.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(colorScheme == .dark ? Color.blue.opacity(0.25) : Color.blue.opacity(0.2), lineWidth: 1)
        )
    }

    private func decisionRow(for patch: ResumePatch) -> some View {
        HStack(spacing: 10) {
            tailoringDecisionButton(
                title: "Accept",
                icon: "checkmark",
                isActive: acceptedPatchIDs.contains(patch.id),
                tint: Color.green,
                action: {
                    applyPatchDecision(.accept, for: patch)
                }
            )

            tailoringDecisionButton(
                title: "Reject",
                icon: "xmark",
                isActive: rejectedPatchIDs.contains(patch.id),
                tint: Color.gray,
                action: {
                    applyPatchDecision(.reject, for: patch)
                }
            )

            Spacer()
        }
    }

    private func decisionStatusBadge(_ status: PatchDecisionStatus) -> some View {
        Label(status.title, systemImage: status.icon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(status.foregroundColor)
            .background(Capsule().fill(status.fillColor.opacity(colorScheme == .dark ? 0.24 : 0.16)))
            .overlay(
                Capsule()
                    .stroke(status.fillColor.opacity(0.38), lineWidth: 1)
            )
    }

    private func tailoringDecisionButton(
        title: String,
        icon: String,
        isActive: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isActive ? tint.opacity(colorScheme == .dark ? 0.28 : 0.2) : Color.secondary.opacity(colorScheme == .dark ? 0.14 : 0.12))
                )
                .overlay(
                    Capsule()
                        .stroke(isActive ? tint.opacity(0.55) : Color.secondary.opacity(0.22), lineWidth: 1)
                )
                .foregroundStyle(isActive ? tint : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private enum PatchDecisionAction {
        case accept
        case reject
    }

    private enum PatchDecisionStatus {
        case accepted
        case rejected

        var title: String {
            switch self {
            case .accepted: return "Accepted"
            case .rejected: return "Rejected"
            }
        }

        var icon: String {
            switch self {
            case .accepted: return "checkmark.circle.fill"
            case .rejected: return "xmark.circle.fill"
            }
        }

        var fillColor: Color {
            switch self {
            case .accepted: return .green
            case .rejected: return .gray
            }
        }

        var foregroundColor: Color {
            switch self {
            case .accepted: return Color.green.opacity(0.95)
            case .rejected: return .secondary
            }
        }
    }

    private enum ToastStyle {
        case success
        case neutral

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .neutral: return "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .success: return .green
            case .neutral: return .blue
            }
        }
    }

    private struct DecisionSnapshot {
        let acceptedPatchIDs: Set<UUID>
        let rejectedPatchIDs: Set<UUID>
    }

    private struct DecisionToast: Identifiable {
        let id = UUID()
        let message: String
        let style: ToastStyle
        let showsUndo: Bool
    }

    private var hasDraftChanges: Bool {
        editedJSON != lastPersistedJSON
            || acceptedPatchIDs != lastPersistedAcceptedPatchIDs
            || rejectedPatchIDs != lastPersistedRejectedPatchIDs
    }

    private var unresolvedPatchCount: Int {
        max(0, patches.count - acceptedPatchIDs.count - rejectedPatchIDs.count)
    }

    private var draftSummaryBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                summaryChip(
                    title: "Accepted \(acceptedPatchIDs.count)",
                    icon: "checkmark.circle.fill",
                    tint: .green
                )
                summaryChip(
                    title: "Rejected \(rejectedPatchIDs.count)",
                    icon: "xmark.circle.fill",
                    tint: .gray
                )
                summaryChip(
                    title: "Pending \(unresolvedPatchCount)",
                    icon: "clock.fill",
                    tint: .orange
                )
            }

            Spacer()

            Text(hasDraftChanges ? "Unsaved changes" : "No unsaved changes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(hasDraftChanges ? Color.orange.opacity(0.9) : .secondary)

            Button("Export JSON") {
                exportJSON()
            }
            .buttonStyle(.bordered)

            Button("Export PDF") {
                Task { await exportPDF() }
            }
            .buttonStyle(.bordered)

            Button("Save Tailored Resume") {
                saveSnapshot()
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accent)
            .disabled(!hasDraftChanges)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? Color(red: 0.10, green: 0.12, blue: 0.18) : Color(red: 0.93, green: 0.95, blue: 0.99))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private func summaryChip(title: String, icon: String, tint: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(tint.opacity(colorScheme == .dark ? 0.95 : 0.88))
            .background(
                Capsule()
                    .fill(tint.opacity(colorScheme == .dark ? 0.2 : 0.14))
            )
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.34), lineWidth: 1)
            )
    }

    private func statusChip(_ title: String) -> some View {
        HStack(spacing: 5) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.secondary.opacity(colorScheme == .dark ? 0.18 : 0.12))
        )
    }

    private func decisionToastView(_ toast: DecisionToast) -> some View {
        HStack(spacing: 10) {
            Image(systemName: toast.style.icon)
                .foregroundStyle(toast.style.tint)

            Text(toast.message)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            if toast.showsUndo {
                Button("Undo") {
                    undoLastDecision()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? Color(red: 0.11, green: 0.13, blue: 0.18) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.12), radius: 10, y: 3)
    }

    private func decisionStatus(for patch: ResumePatch) -> PatchDecisionStatus? {
        if acceptedPatchIDs.contains(patch.id) {
            return .accepted
        }
        if rejectedPatchIDs.contains(patch.id) {
            return .rejected
        }
        return nil
    }

    private func applyPatchDecision(_ action: PatchDecisionAction, for patch: ResumePatch) {
        let snapshot = DecisionSnapshot(
            acceptedPatchIDs: acceptedPatchIDs,
            rejectedPatchIDs: rejectedPatchIDs
        )

        switch action {
        case .accept:
            acceptedPatchIDs.insert(patch.id)
            rejectedPatchIDs.remove(patch.id)
            collapsedPatchIDs.insert(patch.id)
            refreshEditedJSON()
            publishUnsavedChangesState()
            presentDecisionToast(
                message: "Accepted \(patch.path). Draft JSON updated.",
                style: .success,
                showsUndo: true,
                snapshot: snapshot
            )
        case .reject:
            rejectedPatchIDs.insert(patch.id)
            acceptedPatchIDs.remove(patch.id)
            collapsedPatchIDs.insert(patch.id)
            refreshEditedJSON()
            publishUnsavedChangesState()
            presentDecisionToast(
                message: "Rejected \(patch.path). Draft JSON updated.",
                style: .neutral,
                showsUndo: true,
                snapshot: snapshot
            )
        }
    }

    private func undoLastDecision() {
        guard let lastDecisionSnapshot else { return }
        acceptedPatchIDs = lastDecisionSnapshot.acceptedPatchIDs
        rejectedPatchIDs = lastDecisionSnapshot.rejectedPatchIDs
        refreshEditedJSON()
        publishUnsavedChangesState()
        presentDecisionToast(
            message: "Undid last decision.",
            style: .neutral,
            showsUndo: false,
            snapshot: nil
        )
    }

    private func presentDecisionToast(
        message: String,
        style: ToastStyle,
        showsUndo: Bool,
        snapshot: DecisionSnapshot?
    ) {
        toastDismissTask?.cancel()
        lastDecisionSnapshot = snapshot

        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            decisionToast = DecisionToast(
                message: message,
                style: style,
                showsUndo: showsUndo
            )
        }

        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    decisionToast = nil
                }
                lastDecisionSnapshot = nil
            }
        }
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
        lastPersistedJSON = editedJSON
        lastPersistedAcceptedPatchIDs = []
        lastPersistedRejectedPatchIDs = []
        collapsedPatchIDs = []
        decisionToast = nil
        lastDecisionSnapshot = nil
        toastDismissTask?.cancel()
        publishUnsavedChangesState()
    }

    private func triggerInitialGenerationIfNeeded() {
        guard !hasTriggeredInitialGeneration, preflightError == nil else { return }
        hasTriggeredInitialGeneration = true
        Task { await generateSuggestions() }
    }

    private func closeTailoringView() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func requestClose() {
        if hasDraftChanges {
            showingDiscardChangesConfirmation = true
            return
        }
        closeTailoringView()
    }

    private func publishUnsavedChangesState() {
        onUnsavedChangesChanged?(hasDraftChanges)
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

            try applyTailoringResult(result, originalJSON: masterRevision.rawJSON)
        } catch let keyError as SettingsViewModel.APIKeyValidationError {
            actionError = keyError.localizedDescription
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func applyTailoringResult(_ result: ResumeTailoringResult, originalJSON: String) throws {
        let validation = try ResumePatchSafetyValidator.validate(
            patches: result.patches,
            originalJSON: originalJSON
        )

        patches = validation.accepted
        safetyRejections = validation.rejected
        sectionGaps = result.sectionGaps
        collapsedPatchIDs = []

        acceptedPatchIDs = []
        rejectedPatchIDs = []
        refreshEditedJSON()
        lastPersistedJSON = editedJSON
        lastPersistedAcceptedPatchIDs = acceptedPatchIDs
        lastPersistedRejectedPatchIDs = rejectedPatchIDs
        decisionToast = nil
        lastDecisionSnapshot = nil
        toastDismissTask?.cancel()
        publishUnsavedChangesState()
    }

    private func refreshEditedJSON() {
        let baseJSON = masterRevision?.rawJSON
        guard let baseJSON else { return }

        do {
            editedJSON = try ResumePatchApplier.apply(
                patches: patches,
                acceptedPatchIDs: acceptedPatchIDs,
                to: baseJSON
            )
        } catch {
            editedJSON = baseJSON
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
            lastPersistedJSON = validated.normalizedJSON
            lastPersistedAcceptedPatchIDs = acceptedPatchIDs
            lastPersistedRejectedPatchIDs = rejectedPatchIDs
            publishUnsavedChangesState()
            closeTailoringView()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func exportJSON() {
        do {
            jsonDocument = try ResumeJSONExportService.makeDocument(json: editedJSON)
            exportFormat = .json
            isExportingFile = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func exportPDF() async {
        do {
            pdfDocument = try await ResumePDFExportService.makeDocument(json: editedJSON)
            exportFormat = .pdf
            isExportingFile = true
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private enum ResumePatchSplitDiff {
    enum TokenKind {
        case unchanged
        case removed
        case added
    }

    struct Token {
        let value: String
        let kind: TokenKind
    }

    struct Row {
        let oldLine: Int?
        let newLine: Int?
        let oldTokens: [Token]
        let newTokens: [Token]
    }

    static func makeRows(before: String, after: String) -> [Row] {
        let beforeWords = tokenize(before)
        let afterWords = tokenize(after)
        let common = longestCommonSubsequence(beforeWords, afterWords)

        var beforeTokens: [Token] = []
        var afterTokens: [Token] = []
        var beforeIndex = 0
        var afterIndex = 0

        for sharedWord in common {
            while beforeIndex < beforeWords.count && beforeWords[beforeIndex] != sharedWord {
                beforeTokens.append(Token(value: beforeWords[beforeIndex], kind: .removed))
                beforeIndex += 1
            }
            while afterIndex < afterWords.count && afterWords[afterIndex] != sharedWord {
                afterTokens.append(Token(value: afterWords[afterIndex], kind: .added))
                afterIndex += 1
            }

            if beforeIndex < beforeWords.count {
                beforeTokens.append(Token(value: beforeWords[beforeIndex], kind: .unchanged))
                beforeIndex += 1
            }
            if afterIndex < afterWords.count {
                afterTokens.append(Token(value: afterWords[afterIndex], kind: .unchanged))
                afterIndex += 1
            }
        }

        while beforeIndex < beforeWords.count {
            beforeTokens.append(Token(value: beforeWords[beforeIndex], kind: .removed))
            beforeIndex += 1
        }
        while afterIndex < afterWords.count {
            afterTokens.append(Token(value: afterWords[afterIndex], kind: .added))
            afterIndex += 1
        }

        let oldLines = wrap(tokens: beforeTokens)
        let newLines = wrap(tokens: afterTokens)
        let rowCount = max(oldLines.count, newLines.count)

        var rows: [Row] = []
        for index in 0..<rowCount {
            let oldTokens = index < oldLines.count ? oldLines[index] : []
            let newTokens = index < newLines.count ? newLines[index] : []
            rows.append(
                Row(
                    oldLine: oldTokens.isEmpty ? nil : index + 1,
                    newLine: newTokens.isEmpty ? nil : index + 1,
                    oldTokens: oldTokens,
                    newTokens: newTokens
                )
            )
        }

        return rows
    }

    private static func tokenize(_ text: String) -> [String] {
        text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private static func wrap(tokens: [Token], maxCharacters: Int = 72) -> [[Token]] {
        guard !tokens.isEmpty else { return [] }

        var lines: [[Token]] = []
        var currentLine: [Token] = []
        var currentCount = 0

        for token in tokens {
            let tokenWidth = token.value.count + (currentLine.isEmpty ? 0 : 1)
            if !currentLine.isEmpty && currentCount + tokenWidth > maxCharacters {
                lines.append(currentLine)
                currentLine = [token]
                currentCount = token.value.count
            } else {
                currentLine.append(token)
                currentCount += tokenWidth
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines
    }

    private static func longestCommonSubsequence(_ lhs: [String], _ rhs: [String]) -> [String] {
        guard !lhs.isEmpty, !rhs.isEmpty else { return [] }

        let n = lhs.count
        let m = rhs.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)

        for i in 1...n {
            for j in 1...m {
                if lhs[i - 1] == rhs[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var i = n
        var j = m
        var result: [String] = []

        while i > 0, j > 0 {
            if lhs[i - 1] == rhs[j - 1] {
                result.append(lhs[i - 1])
                i -= 1
                j -= 1
            } else if dp[i - 1][j] >= dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        return result.reversed()
    }
}

struct JobResumePanel: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var application: JobApplication

    @State private var showingTailor = false
    @State private var showingHistory = false
    @State private var actionError: String?
    #if os(macOS)
    @State private var tailorWindowPresenter = TailorResumeWindowPresenter()
    @State private var historySheetWidth: CGFloat = 980
    #endif

    @State private var isExportingFile = false
    @State private var exportFormat: ResumeExportFormat = .json
    @State private var jsonDocument = ResumeJSONFileDocument(text: "{}")
    @State private var pdfDocument = ResumePDFFileDocument(data: Data())

    var body: some View {
        let snapshots = application.sortedResumeSnapshots

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Resume Versions", systemImage: "doc.text")
                    .font(.headline)

                Spacer()

                Button("History") {
#if os(macOS)
                    historySheetWidth = preferredHistorySheetWidth()
#endif
                    showingHistory = true
                }
                .buttonStyle(.bordered)

                Button {
                    #if os(macOS)
                    presentTailorWindow()
                    #else
                    showingTailor = true
                    #endif
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
        .sheet(isPresented: $showingHistory) {
            ResumeJobSnapshotHistoryView(application: application)
#if os(macOS)
                .frame(
                    minWidth: historySheetWidth,
                    idealWidth: historySheetWidth,
                    maxWidth: historySheetWidth,
                    minHeight: 620
                )
#endif
        }
        .resumeFileExporter(
            isPresented: $isExportingFile,
            format: exportFormat,
            jsonDocument: jsonDocument,
            pdfDocument: pdfDocument,
            defaultFilename: ResumeExportFilename.make(companyName: application.companyName)
        )
        .alert("Resume Action Failed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "Unknown error")
        }
    }

#if os(macOS)
    @MainActor
    private func presentTailorWindow() {
        tailorWindowPresenter.present(
            application: application,
            modelContainer: modelContext.container
        )
    }

    private func preferredHistorySheetWidth() -> CGFloat {
        let windowWidth = NSApp.keyWindow?.frame.width ?? NSApp.mainWindow?.frame.width ?? 1220
        let targetWidth = windowWidth * 0.8
        return max(920, min(targetWidth, 1680))
    }
#endif

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
            exportFormat = .json
            isExportingFile = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func exportPDF(_ snapshot: ResumeJobSnapshot) async {
        do {
            pdfDocument = try await ResumePDFExportService.makeDocument(json: snapshot.rawJSON)
            exportFormat = .pdf
            isExportingFile = true
        } catch {
            actionError = error.localizedDescription
        }
    }
}

struct ResumeJobSnapshotHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var application: JobApplication

    @State private var actionError: String?
    @State private var expandedSnapshotIDs: Set<UUID> = []
    @State private var isExportingFile = false
    @State private var exportFormat: ResumeExportFormat = .json
    @State private var jsonDocument = ResumeJSONFileDocument(text: "{}")
    @State private var pdfDocument = ResumePDFFileDocument(data: Data())

    private var snapshots: [ResumeJobSnapshot] {
        application.sortedResumeSnapshots
    }

    var body: some View {
        NavigationStack {
            Group {
                if snapshots.isEmpty {
                    ContentUnavailableView(
                        "No Resume Versions",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Tailor and save a resume to create version history for this job.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(snapshots.count) snapshot\(snapshots.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ForEach(snapshots) { snapshot in
                                snapshotCard(snapshot)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Resume Version History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .resumeFileExporter(
            isPresented: $isExportingFile,
            format: exportFormat,
            jsonDocument: jsonDocument,
            pdfDocument: pdfDocument,
            defaultFilename: ResumeExportFilename.make(companyName: application.companyName)
        )
        .alert("History Action Failed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "Unknown error")
        }
    }

    private func snapshotCard(_ snapshot: ResumeJobSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                    .fontWeight(.semibold)

                if snapshots.first?.id == snapshot.id {
                    Text("Latest")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(DesignSystem.Colors.accent.opacity(0.2)))
                }

                Spacer()

                Button {
                    toggleDiff(for: snapshot)
                } label: {
                    Label(
                        expandedSnapshotIDs.contains(snapshot.id) ? "Hide Diff" : "Show Diff",
                        systemImage: expandedSnapshotIDs.contains(snapshot.id) ? "chevron.up.circle.fill" : "chevron.down.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
                .controlSize(.large)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Accepted: \(snapshot.acceptedPatchIDs.count)  Rejected: \(snapshot.rejectedPatchIDs.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !snapshot.sectionGaps.isEmpty {
                    Text("Coverage gaps: \(snapshot.sectionGaps.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button("Export JSON") {
                    exportJSON(snapshot)
                }
                .buttonStyle(.bordered)

                Button("Export PDF") {
                    Task { await exportPDF(snapshot) }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Delete", role: .destructive) {
                    deleteSnapshot(snapshot)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)

            if expandedSnapshotIDs.contains(snapshot.id) {
                diffSection(for: snapshot)
            }
        }
        .padding(16)
        .appCard(cornerRadius: 12, elevated: true, shadow: false)
    }

    private func deleteSnapshot(_ snapshot: ResumeJobSnapshot) {
        do {
            try ResumeStoreService.deleteJobSnapshot(snapshot, in: modelContext)
            expandedSnapshotIDs.remove(snapshot.id)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func exportJSON(_ snapshot: ResumeJobSnapshot) {
        do {
            jsonDocument = try ResumeJSONExportService.makeDocument(json: snapshot.rawJSON)
            exportFormat = .json
            isExportingFile = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func exportPDF(_ snapshot: ResumeJobSnapshot) async {
        do {
            pdfDocument = try await ResumePDFExportService.makeDocument(json: snapshot.rawJSON)
            exportFormat = .pdf
            isExportingFile = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func toggleDiff(for snapshot: ResumeJobSnapshot) {
        if expandedSnapshotIDs.contains(snapshot.id) {
            expandedSnapshotIDs.remove(snapshot.id)
        } else {
            expandedSnapshotIDs.insert(snapshot.id)
        }
    }

    private func diffSection(for snapshot: ResumeJobSnapshot) -> some View {
        Group {
            if let previous = previousSnapshot(for: snapshot) {
                let diff = ResumeRevisionDiffService.diff(from: previous.rawJSON, to: snapshot.rawJSON)

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
                Text("No previous version to compare.")
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

    private func previousSnapshot(for snapshot: ResumeJobSnapshot) -> ResumeJobSnapshot? {
        guard let index = snapshots.firstIndex(where: { $0.id == snapshot.id }) else {
            return nil
        }

        let previousIndex = snapshots.index(after: index)
        guard snapshots.indices.contains(previousIndex) else {
            return nil
        }

        return snapshots[previousIndex]
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
}

#if os(macOS)
private final class EscapeClosableWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .keyDown, event.keyCode == 53, modifiers.isEmpty {
            performClose(nil)
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
private final class TailorResumeWindowPresenter: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var hasUnsavedChanges = false

    func present(
        application: JobApplication,
        modelContainer: ModelContainer
    ) {
        hasUnsavedChanges = false
        let rootView = ResumeTailoringView(
            application: application,
            onClose: { [weak self] in
                self?.hasUnsavedChanges = false
                self?.window?.performClose(nil)
            },
            onUnsavedChangesChanged: { [weak self] hasUnsavedChanges in
                self?.hasUnsavedChanges = hasUnsavedChanges
            }
        )
        .modelContainer(modelContainer)

        if let window {
            window.contentViewController = NSHostingController(rootView: rootView)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: rootView)
        let window = EscapeClosableWindow(contentViewController: hostingController)
        window.title = "Tailor Resume"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1320, height: 880))
        window.minSize = NSSize(width: 1120, height: 760)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        hasUnsavedChanges = false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard hasUnsavedChanges else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Discard unsaved changes?"
        alert.informativeText = "You have unsaved changes in Tailor Resume. Close without saving?"
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
#endif

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
        private var lastSyncedText: String?
        private var lastSyncedTheme: Bool?

        weak var webView: WKWebView?

        init(text: Binding<String>, isDarkMode: Bool) {
            _text = text
            self.isDarkMode = isDarkMode
            self.lastSyncedText = nil
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
            syncTextIfNeeded(text, force: true)
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

        private func syncTextIfNeeded(_ newText: String, force: Bool = false) {
            guard isReady else { return }
            if !force, let lastSyncedText, newText == lastSyncedText {
                return
            }
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
            syncTextIfNeeded(text, force: true)
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
