import SwiftUI
import SwiftData
import PipelineKit

struct ManualEntryFormView: View {
    @Query(sort: \JobSearchCycle.startDate, order: .reverse) private var cycles: [JobSearchCycle]
    @Bindable var viewModel: AddEditApplicationViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingAddCustomStatus = false
    @State private var showingAddCustomSource = false
    @State private var showingAddCustomInterviewStage = false

    @State private var customStatusText: String = ""
    @State private var customSourceText: String = ""
    @State private var customInterviewStageText: String = ""

    private var statusOptions: [ApplicationStatus] {
        let defaults = ApplicationStatus.allCases.sorted { $0.sortOrder < $1.sortOrder }
        let customs = CustomValuesStore.customStatuses()
            .map { ApplicationStatus(rawValue: $0) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return (defaults + customs).uniquedPreservingOrder(by: { $0.rawValue.lowercased() })
    }

    private var sourceOptions: [Source] {
        let defaults = Source.allCases
        let customs = CustomValuesStore.customSources()
            .map { Source(rawValue: $0) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return (defaults + customs).uniquedPreservingOrder(by: { $0.rawValue.lowercased() })
    }

    private var interviewStageOptions: [InterviewStage] {
        let defaults = InterviewStage.orderedCases
        let customs = CustomValuesStore.customInterviewStages()
            .map { InterviewStage(rawValue: $0) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return (defaults + customs).uniquedPreservingOrder(by: { $0.rawValue.lowercased() })
    }

    private var cycleOptions: [JobSearchCycle] {
        cycles.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive && !rhs.isActive
            }
            if lhs.startDate != rhs.startDate {
                return lhs.startDate > rhs.startDate
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 18) {
            LabeledTextField(
                label: "Job URL",
                placeholder: "https://linkedin.com/jobs/...",
                text: $viewModel.jobURL
            )
            .onChange(of: viewModel.jobURL) { _, _ in
                viewModel.onJobURLChanged()
            }

            HStack(spacing: 16) {
                LabeledTextField(label: "Company *", placeholder: "Apple", text: $viewModel.companyName)
                LabeledTextField(label: "Role *", placeholder: "Senior Software Engineer", text: $viewModel.role)
            }

            LabeledTextField(label: "Location *", placeholder: "San Francisco, CA (Remote)", text: $viewModel.location)

            VStack(alignment: .leading, spacing: 10) {
                Text("Seniority")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Seniority", selection: $viewModel.seniorityOverride) {
                    Text("Auto").tag(nil as SeniorityBand?)
                    ForEach(SeniorityBand.allCases) { band in
                        Text(band.title).tag(band as SeniorityBand?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .appInput()
            }

            if !cycleOptions.isEmpty {
                LabeledOptionalPicker(label: "Search Cycle", selection: $viewModel.selectedCycleID) {
                    Text("No Cycle").tag(nil as UUID?)
                    ForEach(cycleOptions) { cycle in
                        Text(cyclePickerTitle(for: cycle)).tag(cycle.id as UUID?)
                    }
                }
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Status")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Picker("", selection: $viewModel.status) {
                            ForEach(statusOptions) { status in
                                Text(status.displayName).tag(status)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .appInput()
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            showingAddCustomStatus = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.accent)
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.Radius.input, style: .continuous)
                                        .fill(DesignSystem.Colors.inputBackground(colorScheme))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.Radius.input, style: .continuous)
                                        .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .fastTooltip("Add custom status")
                        .popover(isPresented: $showingAddCustomStatus, arrowEdge: .top) {
                            AddCustomValuePopover(
                                title: "Add Custom Status",
                                placeholder: "On Hold",
                                text: $customStatusText,
                                onCancel: { showingAddCustomStatus = false },
                                onAdd: {
                                    CustomValuesStore.addCustomStatus(customStatusText)
                                    let value = customStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !value.isEmpty {
                                        viewModel.status = .custom(value)
                                    }
                                    customStatusText = ""
                                    showingAddCustomStatus = false
                                }
                            )
                        }
                    }
                }

                LabeledPicker(label: "Priority", selection: $viewModel.priority) {
                    ForEach(Priority.allCases) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Source")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Picker("", selection: $viewModel.source) {
                            ForEach(sourceOptions) { source in
                                Text(source.displayName).tag(source)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .appInput()
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            showingAddCustomSource = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.accent)
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.Radius.input, style: .continuous)
                                        .fill(DesignSystem.Colors.inputBackground(colorScheme))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.Radius.input, style: .continuous)
                                        .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .fastTooltip("Add custom source")
                        .popover(isPresented: $showingAddCustomSource, arrowEdge: .top) {
                            AddCustomValuePopover(
                                title: "Add Custom Source",
                                placeholder: "Recruiter",
                                text: $customSourceText,
                                onCancel: { showingAddCustomSource = false },
                                onAdd: {
                                    CustomValuesStore.addCustomSource(customSourceText)
                                    let value = customSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !value.isEmpty {
                                        viewModel.source = .custom(value)
                                    }
                                    customSourceText = ""
                                    showingAddCustomSource = false
                                }
                            )
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Posted Compensation")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    Picker("", selection: $viewModel.currency) {
                        ForEach(Currency.allCases) { currency in
                            Text(currency.displayName).tag(currency)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 80)
                    .appInput()

                    TextField("Base min", text: $viewModel.salaryMinString)
                        .textFieldStyle(.plain)
                        .appInput()

                    Text("to")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("Base max", text: $viewModel.salaryMaxString)
                        .textFieldStyle(.plain)
                        .appInput()
                }

                HStack(spacing: 10) {
                    TextField("Annual bonus", text: $viewModel.postedBonusString)
                        .textFieldStyle(.plain)
                        .appInput()

                    TextField("Annual equity", text: $viewModel.postedEquityString)
                        .textFieldStyle(.plain)
                        .appInput()
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Track expected compensation", isOn: $viewModel.showExpectedCompensation)
                    .toggleStyle(.switch)

                if viewModel.showExpectedCompensation {
                    HStack(spacing: 10) {
                        TextField("Expected base min", text: $viewModel.expectedSalaryMinString)
                            .textFieldStyle(.plain)
                            .appInput()

                        Text("to")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("Expected base max", text: $viewModel.expectedSalaryMaxString)
                            .textFieldStyle(.plain)
                            .appInput()
                    }

                    HStack(spacing: 10) {
                        TextField("Expected bonus", text: $viewModel.expectedBonusString)
                            .textFieldStyle(.plain)
                            .appInput()

                        TextField("Expected equity", text: $viewModel.expectedEquityString)
                            .textFieldStyle(.plain)
                            .appInput()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Track final offer compensation", isOn: $viewModel.showOfferCompensation)
                    .toggleStyle(.switch)

                if viewModel.showOfferCompensation {
                    HStack(spacing: 10) {
                        TextField("Offer base", text: $viewModel.offerBaseString)
                            .textFieldStyle(.plain)
                            .appInput()

                        TextField("Offer bonus", text: $viewModel.offerBonusString)
                            .textFieldStyle(.plain)
                            .appInput()

                        TextField("Equity (4yr est.)", text: $viewModel.offerEquityString)
                            .textFieldStyle(.plain)
                            .appInput()
                    }

                    HStack(spacing: 10) {
                        TextField("PTO", text: $viewModel.offerPTOText)
                            .textFieldStyle(.plain)
                            .appInput()

                        scoreField(label: "PTO Score", rating: scoreBinding($viewModel.offerPTOScoreString))

                        TextField("Remote policy", text: $viewModel.offerRemotePolicyText)
                            .textFieldStyle(.plain)
                            .appInput()

                        scoreField(label: "Remote Score", rating: scoreBinding($viewModel.offerRemotePolicyScoreString))
                    }

                    HStack(spacing: 18) {
                        qualitativeScoreRow(
                            title: "Growth",
                            rating: scoreBinding($viewModel.offerGrowthScoreString)
                        )

                        qualitativeScoreRow(
                            title: "Team/Culture",
                            rating: scoreBinding($viewModel.offerTeamCultureFitScoreString)
                        )
                    }
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Interview Stage")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Picker("", selection: $viewModel.interviewStage) {
                            Text("Not Set").tag(nil as InterviewStage?)
                            ForEach(interviewStageOptions) { stage in
                                Text(stage.displayName).tag(stage as InterviewStage?)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .appInput()
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            showingAddCustomInterviewStage = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.accent)
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.Radius.input, style: .continuous)
                                        .fill(DesignSystem.Colors.inputBackground(colorScheme))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.Radius.input, style: .continuous)
                                        .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .fastTooltip("Add custom interview stage")
                        .popover(isPresented: $showingAddCustomInterviewStage, arrowEdge: .top) {
                            AddCustomValuePopover(
                                title: "Add Interview Stage",
                                placeholder: "Onsite",
                                text: $customInterviewStageText,
                                onCancel: { showingAddCustomInterviewStage = false },
                                onAdd: {
                                    CustomValuesStore.addCustomInterviewStage(customInterviewStageText)
                                    let value = customInterviewStageText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !value.isEmpty {
                                        viewModel.interviewStage = .custom(value)
                                    }
                                    customInterviewStageText = ""
                                    showingAddCustomInterviewStage = false
                                }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                OptionalDateField(
                    label: "Next Follow Up",
                    date: $viewModel.nextFollowUpDate,
                    isEnabled: $viewModel.hasFollowUpDate
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Job Description")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextEditor(text: $viewModel.jobDescription)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 120)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.input, style: .continuous)
                            .fill(DesignSystem.Colors.inputBackground(colorScheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.input, style: .continuous)
                            .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
                    )
            }

            if !viewModel.validationErrors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.validationErrors, id: \.self) { error in
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(12)
                .background(Color.red.opacity(colorScheme == .dark ? 0.14 : 0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .onAppear {
            viewModel.ensureDefaultCycleSelection(from: cycleOptions)
        }
        #else
        Form {
            // Basic Info Section
            Section("Basic Information") {
                TextField("Company Name *", text: $viewModel.companyName)

                TextField("Role / Position *", text: $viewModel.role)

                TextField("Location *", text: $viewModel.location)

                Picker("Seniority", selection: $viewModel.seniorityOverride) {
                    Text("Auto").tag(nil as SeniorityBand?)
                    ForEach(SeniorityBand.allCases) { band in
                        Text(band.title).tag(band as SeniorityBand?)
                    }
                }

                TextField("Job URL", text: $viewModel.jobURL)
                    .onChange(of: viewModel.jobURL) { _, _ in
                        viewModel.onJobURLChanged()
                    }

                if !cycleOptions.isEmpty {
                    Picker("Search Cycle", selection: $viewModel.selectedCycleID) {
                        Text("No Cycle").tag(nil as UUID?)
                        ForEach(cycleOptions) { cycle in
                            Text(cyclePickerTitle(for: cycle)).tag(cycle.id as UUID?)
                        }
                    }
                }
            }

            // Status Section
            Section("Status & Priority") {
                Picker("Status", selection: $viewModel.status) {
                    ForEach(statusOptions) { status in
                        Label(status.displayName, systemImage: status.icon)
                            .tag(status)
                    }
                }

                Button("Add Custom Status") { showingAddCustomStatus = true }

                Picker("Priority", selection: $viewModel.priority) {
                    ForEach(Priority.allCases) { priority in
                        Label(priority.displayName, systemImage: priority.icon)
                            .tag(priority)
                    }
                }

                Picker("Interview Stage", selection: $viewModel.interviewStage) {
                    Text("Not Set").tag(nil as InterviewStage?)
                    ForEach(interviewStageOptions) { stage in
                        Label(stage.displayName, systemImage: stage.icon)
                            .tag(stage as InterviewStage?)
                    }
                }

                Button("Add Custom Interview Stage") { showingAddCustomInterviewStage = true }
            }

            // Source & Platform Section
            Section("Source & Platform") {
                Picker("Source", selection: $viewModel.source) {
                    ForEach(sourceOptions) { source in
                        Label(source.displayName, systemImage: source.icon)
                            .tag(source)
                    }
                }

                Button("Add Custom Source") { showingAddCustomSource = true }

                Picker("Platform", selection: $viewModel.platform) {
                    ForEach(Platform.allCases) { platform in
                        Text(platform.displayName)
                            .tag(platform)
                    }
                }
            }

            // Salary Section
            Section("Compensation") {
                Picker("Currency", selection: $viewModel.currency) {
                    ForEach(Currency.allCases) { currency in
                        Text("\(currency.displayName) (\(currency.symbol))")
                            .tag(currency)
                    }
                }

                HStack {
                    TextField("Posted Base Min", text: $viewModel.salaryMinString)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif

                    Text("to")
                        .foregroundColor(.secondary)

                    TextField("Posted Base Max", text: $viewModel.salaryMaxString)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }

                HStack {
                    TextField("Posted Bonus", text: $viewModel.postedBonusString)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif

                    TextField("Posted Equity", text: $viewModel.postedEquityString)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }

                Toggle("Track Expected Compensation", isOn: $viewModel.showExpectedCompensation)

                if viewModel.showExpectedCompensation {
                    HStack {
                        TextField("Expected Base Min", text: $viewModel.expectedSalaryMinString)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif

                        Text("to")
                            .foregroundColor(.secondary)

                        TextField("Expected Base Max", text: $viewModel.expectedSalaryMaxString)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }

                    HStack {
                        TextField("Expected Bonus", text: $viewModel.expectedBonusString)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif

                        TextField("Expected Equity", text: $viewModel.expectedEquityString)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                }

                Toggle("Track Final Offer Compensation", isOn: $viewModel.showOfferCompensation)

                if viewModel.showOfferCompensation {
                    HStack {
                        TextField("Offer Base", text: $viewModel.offerBaseString)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif

                        TextField("Offer Bonus", text: $viewModel.offerBonusString)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif

                        TextField("Equity (4yr est.)", text: $viewModel.offerEquityString)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }

                    TextField("PTO", text: $viewModel.offerPTOText)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("PTO Score")
                            .foregroundColor(.secondary)
                        StarRating(rating: scoreBinding($viewModel.offerPTOScoreString), minRating: 0, size: 18)
                    }

                    TextField("Remote Policy", text: $viewModel.offerRemotePolicyText)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Remote Policy Score")
                            .foregroundColor(.secondary)
                        StarRating(rating: scoreBinding($viewModel.offerRemotePolicyScoreString), minRating: 0, size: 18)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Growth Score")
                            .foregroundColor(.secondary)
                        StarRating(rating: scoreBinding($viewModel.offerGrowthScoreString), minRating: 0, size: 18)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Team/Culture Fit")
                            .foregroundColor(.secondary)
                        StarRating(rating: scoreBinding($viewModel.offerTeamCultureFitScoreString), minRating: 0, size: 18)
                    }
                }
            }

            // Dates Section
            Section("Dates") {
                Toggle("Applied Date", isOn: $viewModel.hasAppliedDate)

                if viewModel.hasAppliedDate {
                    DatePicker(
                        "Applied On",
                        selection: Binding(
                            get: { viewModel.appliedDate ?? Date() },
                            set: { viewModel.appliedDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                }

                Toggle("Follow-up Reminder", isOn: $viewModel.hasFollowUpDate)

                if viewModel.hasFollowUpDate {
                    DatePicker(
                        "Follow-up Date",
                        selection: Binding(
                            get: { viewModel.nextFollowUpDate ?? Date().addingTimeInterval(86400 * 7) },
                            set: { viewModel.nextFollowUpDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                }

                Toggle("Posted Date", isOn: $viewModel.hasPostedAt)

                if viewModel.hasPostedAt {
                    DatePicker(
                        "Posted On",
                        selection: Binding(
                            get: { viewModel.postedAt ?? Date() },
                            set: { viewModel.postedAt = $0 }
                        ),
                        displayedComponents: .date
                    )
                }

                Toggle("Application Deadline", isOn: $viewModel.hasApplicationDeadline)

                if viewModel.hasApplicationDeadline {
                    DatePicker(
                        "Deadline",
                        selection: Binding(
                            get: { viewModel.applicationDeadline ?? Date().addingTimeInterval(86400 * 7) },
                            set: { viewModel.applicationDeadline = $0 }
                        ),
                        displayedComponents: .date
                    )
                }

                Toggle("Add to Apply Queue", isOn: $viewModel.isInApplyQueue)
                    .disabled(viewModel.status != .saved)
            }

            // Description Section
            Section("Job Description") {
                TextEditor(text: $viewModel.jobDescription)
                    .frame(minHeight: 100)
            }

            // Validation Errors
            if !viewModel.validationErrors.isEmpty {
                Section {
                    ForEach(viewModel.validationErrors, id: \.self) { error in
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAddCustomStatus) {
            NavigationStack {
                AddCustomValuePopover(
                    title: "Add Custom Status",
                    placeholder: "On Hold",
                    text: $customStatusText,
                    onCancel: { showingAddCustomStatus = false },
                    onAdd: {
                        CustomValuesStore.addCustomStatus(customStatusText)
                        let value = customStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty {
                            viewModel.status = .custom(value)
                        }
                        customStatusText = ""
                        showingAddCustomStatus = false
                    }
                )
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showingAddCustomSource) {
            NavigationStack {
                AddCustomValuePopover(
                    title: "Add Custom Source",
                    placeholder: "Recruiter",
                    text: $customSourceText,
                    onCancel: { showingAddCustomSource = false },
                    onAdd: {
                        CustomValuesStore.addCustomSource(customSourceText)
                        let value = customSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty {
                            viewModel.source = .custom(value)
                        }
                        customSourceText = ""
                        showingAddCustomSource = false
                    }
                )
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showingAddCustomInterviewStage) {
            NavigationStack {
                AddCustomValuePopover(
                    title: "Add Interview Stage",
                    placeholder: "Onsite",
                    text: $customInterviewStageText,
                    onCancel: { showingAddCustomInterviewStage = false },
                    onAdd: {
                        CustomValuesStore.addCustomInterviewStage(customInterviewStageText)
                        let value = customInterviewStageText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty {
                            viewModel.interviewStage = .custom(value)
                        }
                        customInterviewStageText = ""
                        showingAddCustomInterviewStage = false
                    }
                )
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onAppear {
            viewModel.ensureDefaultCycleSelection(from: cycleOptions)
        }
        #endif
    }

    private func cyclePickerTitle(for cycle: JobSearchCycle) -> String {
        if cycle.isActive {
            return "\(cycle.name) (Active)"
        }
        return cycle.name
    }

    private func scoreBinding(_ stringBinding: Binding<String>) -> Binding<Int> {
        Binding<Int>(
            get: {
                guard let value = Int(stringBinding.wrappedValue), value > 0 else { return 0 }
                return min(max(value, 1), 5)
            },
            set: { stringBinding.wrappedValue = $0 <= 0 ? "" : String(min(max($0, 1), 5)) }
        )
    }

    @ViewBuilder
    private func scoreField(label: String, rating: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            StarRating(rating: rating, minRating: 0, size: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func qualitativeScoreRow(title: String, rating: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            StarRating(rating: rating, minRating: 0, size: 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AddCustomValuePopover: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let onCancel: () -> Void
    let onAdd: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(DesignSystem.Colors.surfaceElevated(colorScheme))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            TextField("", text: $text, prompt: Text(placeholder))
                .textFieldStyle(.plain)
                .appInput()

            HStack {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered)

                Spacer()

                Button("Add") { onAdd() }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

private extension Array {
    func uniquedPreservingOrder<T: Hashable>(by key: (Element) -> T) -> [Element] {
        var seen = Set<T>()
        var result: [Element] = []
        result.reserveCapacity(count)
        for element in self {
            let value = key(element)
            guard !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(element)
        }
        return result
    }
}

#if os(macOS)
private struct LabeledTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextField("", text: $text, prompt: Text(placeholder))
                .textFieldStyle(.plain)
                .appInput()
        }
    }
}

private struct LabeledPicker<SelectionValue: Hashable, Content: View>: View {
    let label: String
    @Binding var selection: SelectionValue
    let content: () -> Content

    init(label: String, selection: Binding<SelectionValue>, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self._selection = selection
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Picker("", selection: $selection) { content() }
                .labelsHidden()
                .pickerStyle(.menu)
                .appInput()
        }
    }
}

private struct LabeledOptionalPicker<SelectionValue: Hashable, Content: View>: View {
    let label: String
    @Binding var selection: SelectionValue?
    let content: () -> Content

    init(label: String, selection: Binding<SelectionValue?>, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self._selection = selection
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Picker("", selection: $selection) { content() }
                .labelsHidden()
                .pickerStyle(.menu)
                .appInput()
        }
    }
}

private struct OptionalDateField: View {
    let label: String
    @Binding var date: Date?
    @Binding var isEnabled: Bool

    @State private var showingPicker = false
    @Environment(\.colorScheme) private var colorScheme

    private var formattedValue: String {
        guard isEnabled, let date else { return "Not set" }
        return date.formatted(date: .numeric, time: .omitted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button {
                if !isEnabled {
                    isEnabled = true
                }
                if date == nil {
                    date = Calendar.current.date(byAdding: .day, value: 7, to: Date())
                }
                showingPicker = true
            } label: {
                HStack(spacing: 8) {
                    Text(formattedValue)
                        .foregroundColor(isEnabled ? .primary : DesignSystem.Colors.placeholder(colorScheme))

                    Spacer()

                    Image(systemName: "calendar")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .appInput()
            .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(label)
                            .font(.headline)

                        Spacer()

                        Button {
                            showingPicker = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 28, height: 28)
                                .background(DesignSystem.Colors.surfaceElevated(colorScheme))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quick picks")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            QuickDateButton(title: "Tomorrow") {
                                date = Calendar.current.date(byAdding: .day, value: 1, to: Date())
                                isEnabled = true
                                showingPicker = false
                            }

                            QuickDateButton(title: "Next week") {
                                date = Calendar.current.date(byAdding: .day, value: 7, to: Date())
                                isEnabled = true
                                showingPicker = false
                            }

                            QuickDateButton(title: "2 weeks") {
                                date = Calendar.current.date(byAdding: .day, value: 14, to: Date())
                                isEnabled = true
                                showingPicker = false
                            }
                        }
                    }

                    FollowUpCalendarView(
                        selectedDate: Binding(
                            get: { date ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date() },
                            set: {
                                date = $0
                                isEnabled = true
                            }
                        ),
                        onDateSelected: { showingPicker = false }
                    )
                    .frame(height: 324)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
                    )

                    HStack {
                        Button("Clear") {
                            date = nil
                            isEnabled = false
                            showingPicker = false
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button("Done") { showingPicker = false }
                            .buttonStyle(.borderedProminent)
                            .tint(DesignSystem.Colors.accent)
                    }
                }
                .padding(16)
                .frame(width: 396)
            }
        }
    }
}

private struct FollowUpCalendarView: View {
    @Binding var selectedDate: Date
    let onDateSelected: () -> Void
    @State private var displayedMonth: Date

    private let calendar = Calendar.current

    init(selectedDate: Binding<Date>, onDateSelected: @escaping () -> Void = {}) {
        self._selectedDate = selectedDate
        self.onDateSelected = onDateSelected
        let month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: selectedDate.wrappedValue)) ?? Date()
        self._displayedMonth = State(initialValue: month)
    }

    private var monthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide).year())
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let firstWeekdayIndex = max(0, calendar.firstWeekday - 1)
        return Array(symbols[firstWeekdayIndex...] + symbols[..<firstWeekdayIndex])
    }

    private var gridDates: [Date] {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) ?? displayedMonth
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -offset, to: monthStart) ?? monthStart

        return (0..<42).compactMap { index in
            calendar.date(byAdding: .day, value: index, to: gridStart)
        }
    }

    private func isInDisplayedMonth(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(monthTitle)
                    .font(.title2.weight(.semibold))

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)

                    Button {
                        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundColor(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            GeometryReader { proxy in
                let cellHeight = max(30, (proxy.size.height - (5 * 8)) / 6)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                    ForEach(gridDates, id: \.self) { day in
                        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
                        let inMonth = isInDisplayedMonth(day)

                        Button {
                            selectedDate = day
                            displayedMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: day)) ?? displayedMonth
                            onDateSelected()
                        } label: {
                            Text(String(calendar.component(.day, from: day)))
                                .font(.headline.weight(.medium))
                                .foregroundColor(isSelected ? .white : (inMonth ? .primary : .secondary.opacity(0.55)))
                                .frame(maxWidth: .infinity, minHeight: cellHeight)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isSelected ? DesignSystem.Colors.accent : .clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct QuickDateButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title) { action() }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 34)
    }
}
#endif

#Preview {
    ManualEntryFormView(viewModel: AddEditApplicationViewModel())
}
