import SwiftUI

struct ManualEntryFormView: View {
    @Bindable var viewModel: AddEditApplicationViewModel

    var body: some View {
        Form {
            // Basic Info Section
            Section("Basic Information") {
                TextField("Company Name *", text: $viewModel.companyName)

                TextField("Role / Position *", text: $viewModel.role)

                TextField("Location *", text: $viewModel.location)

                TextField("Job URL", text: $viewModel.jobURL)
                    .onChange(of: viewModel.jobURL) { _, _ in
                        viewModel.onJobURLChanged()
                    }
            }

            // Status Section
            Section("Status & Priority") {
                Picker("Status", selection: $viewModel.status) {
                    ForEach(ApplicationStatus.allCases) { status in
                        Label(status.displayName, systemImage: status.icon)
                            .tag(status)
                    }
                }

                Picker("Priority", selection: $viewModel.priority) {
                    ForEach(Priority.allCases) { priority in
                        Label(priority.displayName, systemImage: priority.icon)
                            .tag(priority)
                    }
                }

                if viewModel.status == .interviewing {
                    Picker("Interview Stage", selection: $viewModel.interviewStage) {
                        Text("Not Set").tag(nil as InterviewStage?)
                        ForEach(InterviewStage.allCases) { stage in
                            Label(stage.displayName, systemImage: stage.icon)
                                .tag(stage as InterviewStage?)
                        }
                    }
                }
            }

            // Source & Platform Section
            Section("Source & Platform") {
                Picker("Source", selection: $viewModel.source) {
                    ForEach(Source.allCases) { source in
                        Label(source.displayName, systemImage: source.icon)
                            .tag(source)
                    }
                }

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
                    TextField("Min Salary", text: $viewModel.salaryMinString)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif

                    Text("to")
                        .foregroundColor(.secondary)

                    TextField("Max Salary", text: $viewModel.salaryMaxString)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
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
    }
}

#Preview {
    ManualEntryFormView(viewModel: AddEditApplicationViewModel())
}
