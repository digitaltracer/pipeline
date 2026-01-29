import Foundation
import SwiftData
import SwiftUI

@Observable
final class AddEditApplicationViewModel {
    // Form fields
    var companyName: String = ""
    var role: String = ""
    var location: String = ""
    var jobURL: String = ""
    var jobDescription: String = ""
    var status: ApplicationStatus = .saved
    var priority: Priority = .medium
    var source: Source = .jobPortal
    var platform: Platform = .other
    var interviewStage: InterviewStage?
    var currency: Currency = .usd
    var salaryMinString: String = ""
    var salaryMaxString: String = ""
    var appliedDate: Date?
    var hasAppliedDate: Bool = false
    var nextFollowUpDate: Date?
    var hasFollowUpDate: Bool = false

    // State
    var isEditing: Bool = false
    var editingApplication: JobApplication?

    // MARK: - Initialization

    init() {}

    init(application: JobApplication) {
        self.isEditing = true
        self.editingApplication = application
        loadFromApplication(application)
    }

    private func loadFromApplication(_ app: JobApplication) {
        companyName = app.companyName
        role = app.role
        location = app.location
        jobURL = app.jobURL ?? ""
        jobDescription = app.jobDescription ?? ""
        status = app.status
        priority = app.priority
        source = app.source
        platform = app.platform
        interviewStage = app.interviewStage
        currency = app.currency
        salaryMinString = app.salaryMin.map { String($0) } ?? ""
        salaryMaxString = app.salaryMax.map { String($0) } ?? ""
        appliedDate = app.appliedDate
        hasAppliedDate = app.appliedDate != nil
        nextFollowUpDate = app.nextFollowUpDate
        hasFollowUpDate = app.nextFollowUpDate != nil
    }

    // MARK: - Validation

    var isValid: Bool {
        validationErrors.isEmpty
    }

    var validationErrors: [String] {
        makeValidationErrors()
    }

    private func makeValidationErrors() -> [String] {
        var errors: [String] = []

        if companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Company name is required")
        }

        if role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Role is required")
        }

        if location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Location is required")
        }

        if !jobURL.isEmpty, URL(string: jobURL) == nil {
            errors.append("Invalid job URL")
        }

        if let min = salaryMin, let max = salaryMax, min > max {
            errors.append("Minimum salary cannot exceed maximum salary")
        }

        return errors
    }

    // MARK: - Computed Properties

    var salaryMin: Int? {
        Int(salaryMinString.replacingOccurrences(of: ",", with: ""))
    }

    var salaryMax: Int? {
        Int(salaryMaxString.replacingOccurrences(of: ",", with: ""))
    }

    var title: String {
        isEditing ? "Edit Application" : "Add Application"
    }

    // MARK: - Actions

    func save(context: ModelContext) -> Bool {
        guard isValid else { return false }

        if isEditing, let app = editingApplication {
            updateApplication(app)
            try? context.save()
        } else {
            let app = createApplication()
            context.insert(app)
            try? context.save()
        }

        return true
    }

    private func createApplication() -> JobApplication {
        let app = JobApplication(
            companyName: companyName.trimmingCharacters(in: .whitespacesAndNewlines),
            role: role.trimmingCharacters(in: .whitespacesAndNewlines),
            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
            jobURL: jobURL.isEmpty ? nil : jobURL,
            jobDescription: jobDescription.isEmpty ? nil : jobDescription,
            status: status,
            priority: priority,
            source: source,
            platform: platform,
            interviewStage: interviewStage,
            currency: currency,
            salaryMin: salaryMin,
            salaryMax: salaryMax,
            appliedDate: hasAppliedDate ? appliedDate : nil,
            nextFollowUpDate: hasFollowUpDate ? nextFollowUpDate : nil
        )

        // Auto-detect platform from URL if not manually set
        if platform == .other && !jobURL.isEmpty {
            app.platform = Platform.detect(from: jobURL)
        }

        return app
    }

    private func updateApplication(_ app: JobApplication) {
        app.companyName = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        app.role = role.trimmingCharacters(in: .whitespacesAndNewlines)
        app.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        app.jobURL = jobURL.isEmpty ? nil : jobURL
        app.jobDescription = jobDescription.isEmpty ? nil : jobDescription
        app.status = status
        app.priority = priority
        app.source = source
        app.platform = platform
        app.interviewStage = interviewStage
        app.currency = currency
        app.salaryMin = salaryMin
        app.salaryMax = salaryMax
        app.appliedDate = hasAppliedDate ? appliedDate : nil
        app.nextFollowUpDate = hasFollowUpDate ? nextFollowUpDate : nil
        app.updateTimestamp()

        // Auto-detect platform from URL if set to other
        if platform == .other && !jobURL.isEmpty {
            app.platform = Platform.detect(from: jobURL)
        }
    }

    // MARK: - URL Changed Handler

    func onJobURLChanged() {
        guard !jobURL.isEmpty else { return }

        // Auto-detect platform
        let detectedPlatform = Platform.detect(from: jobURL)
        if detectedPlatform != .other {
            platform = detectedPlatform
        }
    }

    // MARK: - Reset

    func reset() {
        companyName = ""
        role = ""
        location = ""
        jobURL = ""
        jobDescription = ""
        status = .saved
        priority = .medium
        source = .jobPortal
        platform = .other
        interviewStage = nil
        currency = .usd
        salaryMinString = ""
        salaryMaxString = ""
        appliedDate = nil
        hasAppliedDate = false
        nextFollowUpDate = nil
        hasFollowUpDate = false
        isEditing = false
        editingApplication = nil
    }
}
