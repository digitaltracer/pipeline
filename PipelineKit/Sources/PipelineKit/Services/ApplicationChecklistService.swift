import Foundation
import SwiftData

public enum ApplicationChecklistSyncTrigger: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case applicationCreated
    case statusChanged
    case interviewLogged
    case contactsChanged
    case companyResearchSaved
    case coverLetterSaved
    case resumeSnapshotSaved
    case detailViewed
    case submittedResumeSaved

    public var id: String { rawValue }
}

public struct ApplicationChecklistService {
    private enum TemplateID: String, CaseIterable {
        case tailorResume
        case generateCoverLetter
        case researchCompany
        case findReferral
        case submitApplication
        case followUpOnApplication
        case reviewInterviewPrep
        case researchInterviewer
        case compareOfferDetails
        case planSalaryNegotiation
        case sendThankYouNote
    }

    private struct ChecklistTemplate {
        let id: TemplateID
        let title: String
        let priority: Priority
        let actionKind: ApplicationTaskActionKind
        let dueDateResolver: (JobApplication, Calendar) -> Date?
        let autoCompletion: (JobApplication) -> Bool
    }

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func sync(
        for application: JobApplication,
        trigger: ApplicationChecklistSyncTrigger,
        in context: ModelContext
    ) throws {
        _ = trigger
        var didChange = false
        let dismissedIDs = Set(application.dismissedChecklistTemplateIDs)
        let existingChecklistTasks = application.sortedChecklistTasks.reduce(into: [String: ApplicationTask]()) { result, task in
            guard let templateID = task.checklistTemplateID else { return }
            if result[templateID] == nil {
                result[templateID] = task
            }
        }

        for template in eligibleTemplates(for: application) {
            let templateID = template.id.rawValue

            if let existingTask = existingChecklistTasks[templateID] {
                didChange = syncCompletion(for: existingTask, template: template) || didChange
                continue
            }

            guard !dismissedIDs.contains(templateID) else { continue }

            let task = ApplicationTask(
                title: template.title,
                dueDate: template.dueDateResolver(application, calendar),
                priority: template.priority,
                application: application,
                origin: .smartChecklist,
                checklistTemplateID: templateID,
                actionKind: template.actionKind
            )

            if template.autoCompletion(application) {
                task.setCompleted(true)
            }

            context.insert(task)
            application.addTask(task)
            didChange = true
        }

        if didChange {
            application.updateTimestamp()
        }

        if context.hasChanges {
            try context.save()
        }
    }

    private func syncCompletion(for task: ApplicationTask, template: ChecklistTemplate) -> Bool {
        guard !task.isCompleted,
              let application = task.application,
              template.autoCompletion(application) else {
            return false
        }

        task.setCompleted(true)
        application.updateTimestamp()
        return true
    }

    private func eligibleTemplates(for application: JobApplication) -> [ChecklistTemplate] {
        guard shouldSeedChecklist(for: application) else { return [] }

        var templates: [ChecklistTemplate] = []

        switch application.status {
        case .saved:
            templates.append(contentsOf: savedStageTemplates)
        case .applied:
            templates.append(contentsOf: savedStageTemplates)
            templates.append(contentsOf: appliedStageTemplates)
        case .interviewing:
            templates.append(contentsOf: savedStageTemplates)
            templates.append(contentsOf: appliedStageTemplates)
            templates.append(contentsOf: interviewingStageTemplates)
        case .offered:
            templates.append(contentsOf: savedStageTemplates)
            templates.append(contentsOf: appliedStageTemplates)
            templates.append(contentsOf: interviewingStageTemplates)
            templates.append(contentsOf: offeredStageTemplates)
        case .rejected, .archived, .custom(_):
            break
        }

        if !application.sortedInterviewLogs.isEmpty {
            templates.append(thankYouTemplate)
        }

        return templates
    }

    private func shouldSeedChecklist(for application: JobApplication) -> Bool {
        switch application.status {
        case .rejected, .archived, .custom(_):
            return false
        case .saved, .applied, .interviewing, .offered:
            return true
        }
    }

    private var savedStageTemplates: [ChecklistTemplate] {
        [
            ChecklistTemplate(
                id: .tailorResume,
                title: "Tailor resume for this role",
                priority: .medium,
                actionKind: .resumeTailoring,
                dueDateResolver: { _, _ in nil },
                autoCompletion: { application in
                    !application.sortedResumeSnapshots.isEmpty || application.submittedResumeAttachment != nil
                }
            ),
            ChecklistTemplate(
                id: .generateCoverLetter,
                title: "Generate cover letter",
                priority: .medium,
                actionKind: .coverLetter,
                dueDateResolver: { _, _ in nil },
                autoCompletion: { application in
                    application.coverLetterDraft?.hasContent == true
                }
            ),
            ChecklistTemplate(
                id: .researchCompany,
                title: "Research company",
                priority: .medium,
                actionKind: .companyResearch,
                dueDateResolver: { _, _ in nil },
                autoCompletion: { application in
                    !(application.company?.sortedResearchSnapshots.isEmpty ?? true)
                }
            ),
            ChecklistTemplate(
                id: .findReferral,
                title: "Find referral or recruiter contact",
                priority: .medium,
                actionKind: .manageContacts,
                dueDateResolver: { _, _ in nil },
                autoCompletion: { application in
                    !(application.contactLinks ?? []).isEmpty
                }
            ),
            ChecklistTemplate(
                id: .submitApplication,
                title: "Submit application",
                priority: .high,
                actionKind: .none,
                dueDateResolver: { _, _ in nil },
                autoCompletion: { application in
                    switch application.status {
                    case .applied, .interviewing, .offered, .rejected, .archived:
                        return true
                    case .saved, .custom(_):
                        return false
                    }
                }
            )
        ]
    }

    private var appliedStageTemplates: [ChecklistTemplate] {
        [
            ChecklistTemplate(
                id: .followUpOnApplication,
                title: "Follow up on application",
                priority: .high,
                actionKind: .followUpDrafter,
                dueDateResolver: { application, calendar in
                    if let followUpDate = application.nextFollowUpDate {
                        return followUpDate
                    }

                    let baseline = application.appliedDate ?? Date()
                    return calendar.date(byAdding: .day, value: 7, to: baseline)
                },
                autoCompletion: { _ in false }
            )
        ]
    }

    private var interviewingStageTemplates: [ChecklistTemplate] {
        [
            ChecklistTemplate(
                id: .reviewInterviewPrep,
                title: "Review interview prep",
                priority: .high,
                actionKind: .interviewPrep,
                dueDateResolver: { _, _ in nil },
                autoCompletion: { _ in false }
            ),
            ChecklistTemplate(
                id: .researchInterviewer,
                title: "Research interviewer or add interview contacts",
                priority: .high,
                actionKind: .manageContacts,
                dueDateResolver: { _, _ in nil },
                autoCompletion: { application in
                    application.sortedContactLinks.contains(where: { $0.role == .interviewer })
                }
            )
        ]
    }

    private var offeredStageTemplates: [ChecklistTemplate] {
        [
            ChecklistTemplate(
                id: .compareOfferDetails,
                title: "Compare offer details",
                priority: .high,
                actionKind: .salaryComparison,
                dueDateResolver: { _, _ in nil },
                autoCompletion: { _ in false }
            ),
            ChecklistTemplate(
                id: .planSalaryNegotiation,
                title: "Plan salary negotiation",
                priority: .high,
                actionKind: .none,
                dueDateResolver: { _, _ in nil },
                autoCompletion: { _ in false }
            )
        ]
    }

    private var thankYouTemplate: ChecklistTemplate {
        ChecklistTemplate(
            id: .sendThankYouNote,
            title: "Send thank-you note after interview",
            priority: .high,
            actionKind: .followUpDrafter,
            dueDateResolver: { application, calendar in
                let baseline = application.sortedInterviewLogs.first?.date ?? Date()
                return calendar.date(byAdding: .day, value: 1, to: baseline)
            },
            autoCompletion: { _ in false }
        )
    }
}
