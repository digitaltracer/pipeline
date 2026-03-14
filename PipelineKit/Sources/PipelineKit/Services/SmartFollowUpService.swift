import Foundation
import SwiftData

@MainActor
public final class SmartFollowUpService {
    public static let shared = SmartFollowUpService()

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func refreshAll(
        applications: [JobApplication],
        in context: ModelContext
    ) throws {
        var didChange = false

        for application in applications {
            let changed = try refresh(application, in: context)
            didChange = didChange || changed
        }

        if didChange {
            try context.save()
        }
    }

    @discardableResult
    public func refresh(
        _ application: JobApplication,
        in context: ModelContext
    ) throws -> Bool {
        var didChange = false

        didChange = ensureLegacyBackfillIfNeeded(for: application, in: context) || didChange

        if application.status == .archived {
            didChange = dismissActiveSteps(for: application) || didChange
            didChange = syncMirror(for: application) || didChange
            return didChange
        }

        if hasAppliedCadenceSteps(in: application) {
            didChange = rebaseCadence(for: application, in: context) || didChange
        }

        if hasPostInterviewCadenceSteps(in: application) || latestCompletedInterview(for: application) != nil {
            didChange = rebuildInterviewCadence(for: application, in: context) || didChange
        }

        didChange = syncMirror(for: application) || didChange
        return didChange
    }

    public func ensureAppliedCadence(
        for application: JobApplication,
        in context: ModelContext
    ) throws {
        _ = dismissLegacyManualSteps(for: application)

        if !hasAppliedCadenceSteps(in: application) {
            let baseline = application.appliedDate ?? application.updatedAt
            let responseAdjustment = responseAdjustmentDays(for: application, in: context)
            let specs: [(FollowUpStepKind, Int)] = [
                (.ackCheck, 3),
                (.followUp1, 7),
                (.followUp2, 14),
                (.followUp3, 21),
                (.archiveSuggestion, 30)
            ]

            for (index, spec) in specs.enumerated() {
                let date = scheduledDate(
                    from: baseline,
                    offsetDays: spec.1,
                    responseAdjustmentDays: spec.0 == .ackCheck ? 0 : responseAdjustment,
                    applyBusinessDayRules: spec.0 != .ackCheck
                )
                let step = FollowUpStep(
                    dueDate: date,
                    originalDueDate: date,
                    state: .pending,
                    kind: spec.0,
                    cadenceKind: .applicationApplied,
                    sequenceIndex: index,
                    application: application
                )
                context.insert(step)
                application.addFollowUpStep(step)
            }
        }

        _ = rebaseCadence(for: application, in: context)
        _ = syncMirror(for: application)
        try context.save()
    }

    public func syncInterviewCadence(
        for application: JobApplication,
        in context: ModelContext
    ) throws {
        _ = rebuildInterviewCadence(for: application, in: context)
        _ = syncMirror(for: application)
        try context.save()
    }

    public func applyManualFollowUpDate(
        _ date: Date?,
        for application: JobApplication,
        in context: ModelContext
    ) throws {
        var didChange = false

        if let nextStep = application.nextPendingFollowUpStep {
            if let date {
                nextStep.setDueDate(date)
                if nextStep.state == .snoozed {
                    nextStep.markPending()
                }
                didChange = true
            } else {
                nextStep.markDismissed()
                didChange = true
            }
        } else if let date {
            let step = FollowUpStep(
                dueDate: date,
                originalDueDate: date,
                state: .pending,
                kind: .legacyManual,
                cadenceKind: .applicationApplied,
                sequenceIndex: 999,
                application: application
            )
            context.insert(step)
            application.addFollowUpStep(step)
            didChange = true
        } else {
            application.nextFollowUpDate = nil
        }

        didChange = syncMirror(for: application) || didChange
        if didChange {
            try context.save()
        }
    }

    public func markStepDone(
        _ step: FollowUpStep,
        for application: JobApplication,
        in context: ModelContext
    ) throws {
        step.markCompleted()
        application.updateTimestamp()
        _ = syncMirror(for: application)
        try context.save()
    }

    public func dismissStep(
        _ step: FollowUpStep,
        for application: JobApplication,
        in context: ModelContext
    ) throws {
        step.markDismissed()
        application.updateTimestamp()
        _ = syncMirror(for: application)
        try context.save()
    }

    public func snoozeStep(
        _ step: FollowUpStep,
        by days: Int,
        for application: JobApplication,
        in context: ModelContext
    ) throws {
        let shifted = calendar.date(byAdding: .day, value: days, to: step.dueDate) ?? step.dueDate
        let dueDate: Date
        if step.kind == .ackCheck || step.kind == .legacyManual {
            dueDate = shifted
        } else {
            dueDate = nextAllowedBusinessDate(from: shifted)
        }
        step.snooze(until: dueDate)
        application.updateTimestamp()
        _ = syncMirror(for: application)
        try context.save()
    }

    public func recordGeneratedDraft(
        subject: String?,
        body: String?,
        for step: FollowUpStep,
        application: JobApplication,
        in context: ModelContext
    ) throws {
        step.saveGeneratedDraft(subject: subject, body: body)
        application.updateTimestamp()
        try context.save()
    }

    private func rebuildInterviewCadence(
        for application: JobApplication,
        in context: ModelContext
    ) -> Bool {
        let latestInterview = latestCompletedInterview(for: application)
        var didChange = false

        guard let latestInterview else {
            for step in application.sortedFollowUpSteps where step.cadenceKind == .postInterview && step.isActive {
                step.markDismissed()
                didChange = true
            }
            if hasAppliedCadenceSteps(in: application) {
                didChange = rebaseCadence(for: application, in: context) || didChange
            }
            return didChange
        }

        let thankYouDue = nextAllowedBusinessDate(
            from: calendar.date(byAdding: .day, value: 1, to: latestInterview.occurredAt) ?? latestInterview.occurredAt
        )
        didChange = upsertStep(
            kind: .postInterviewThankYou,
            cadenceKind: .postInterview,
            sequenceIndex: 0,
            dueDate: thankYouDue,
            application: application,
            in: context
        ) || didChange

        didChange = rebaseCadence(for: application, in: context) || didChange

        return didChange
    }

    private func upsertStep(
        kind: FollowUpStepKind,
        cadenceKind: FollowUpCadenceKind,
        sequenceIndex: Int,
        dueDate: Date,
        application: JobApplication,
        in context: ModelContext
    ) -> Bool {
        if let existing = application.sortedFollowUpSteps.first(where: {
            $0.kind == kind && $0.cadenceKind == cadenceKind
        }) {
            guard existing.state != .completed && existing.state != .dismissed else {
                return false
            }
            let previousDate = existing.dueDate
            existing.setDueDate(dueDate)
            if existing.state == .snoozed {
                existing.markPending()
            }
            existing.sequenceIndex = sequenceIndex
            return previousDate != dueDate
        }

        let step = FollowUpStep(
            dueDate: dueDate,
            originalDueDate: dueDate,
            state: .pending,
            kind: kind,
            cadenceKind: cadenceKind,
            sequenceIndex: sequenceIndex,
            application: application
        )
        context.insert(step)
        application.addFollowUpStep(step)
        return true
    }

    private func rebaseCadence(
        for application: JobApplication,
        in context: ModelContext
    ) -> Bool {
        guard hasAppliedCadenceSteps(in: application) else { return false }

        let baseline = application.appliedDate ?? application.updatedAt
        let responseAdjustment = responseAdjustmentDays(for: application, in: context)
        let latestInterview = latestCompletedInterview(for: application)
        var didChange = false

        for step in application.sortedFollowUpSteps where step.cadenceKind == .applicationApplied {
            guard step.state != .completed && step.state != .dismissed else { continue }

            let targetDate: Date
            switch step.kind {
            case .ackCheck:
                targetDate = scheduledDate(
                    from: baseline,
                    offsetDays: 3,
                    responseAdjustmentDays: 0,
                    applyBusinessDayRules: false
                )
            case .followUp1:
                targetDate = latestInterview == nil
                    ? scheduledDate(from: baseline, offsetDays: 7, responseAdjustmentDays: responseAdjustment, applyBusinessDayRules: true)
                    : scheduledDate(from: latestInterview!.occurredAt, offsetDays: 5, responseAdjustmentDays: responseAdjustment, applyBusinessDayRules: true)
            case .followUp2:
                targetDate = latestInterview == nil
                    ? scheduledDate(from: baseline, offsetDays: 14, responseAdjustmentDays: responseAdjustment, applyBusinessDayRules: true)
                    : scheduledDate(from: latestInterview!.occurredAt, offsetDays: 10, responseAdjustmentDays: responseAdjustment, applyBusinessDayRules: true)
            case .followUp3:
                targetDate = latestInterview == nil
                    ? scheduledDate(from: baseline, offsetDays: 21, responseAdjustmentDays: responseAdjustment, applyBusinessDayRules: true)
                    : scheduledDate(from: latestInterview!.occurredAt, offsetDays: 17, responseAdjustmentDays: responseAdjustment, applyBusinessDayRules: true)
            case .archiveSuggestion:
                targetDate = latestInterview == nil
                    ? scheduledDate(from: baseline, offsetDays: 30, responseAdjustmentDays: responseAdjustment, applyBusinessDayRules: true)
                    : scheduledDate(from: latestInterview!.occurredAt, offsetDays: 24, responseAdjustmentDays: responseAdjustment, applyBusinessDayRules: true)
            case .postInterviewThankYou, .legacyManual:
                continue
            }

            if step.dueDate != targetDate {
                step.setDueDate(targetDate)
                if step.state == .snoozed {
                    step.markPending()
                }
                didChange = true
            }
        }

        return didChange
    }

    private func ensureLegacyBackfillIfNeeded(
        for application: JobApplication,
        in context: ModelContext
    ) -> Bool {
        guard application.followUpSteps?.isEmpty ?? true,
              let nextFollowUpDate = application.nextFollowUpDate else {
            return false
        }

        let step = FollowUpStep(
            dueDate: nextFollowUpDate,
            originalDueDate: nextFollowUpDate,
            state: .pending,
            kind: .legacyManual,
            cadenceKind: .applicationApplied,
            sequenceIndex: 999,
            application: application
        )
        context.insert(step)
        application.addFollowUpStep(step)
        return true
    }

    private func dismissLegacyManualSteps(for application: JobApplication) -> Bool {
        var didChange = false
        for step in application.sortedFollowUpSteps where step.kind == .legacyManual && step.isActive {
            step.markDismissed()
            didChange = true
        }
        return didChange
    }

    private func dismissActiveSteps(for application: JobApplication) -> Bool {
        var didChange = false
        for step in application.sortedFollowUpSteps where step.isActive {
            step.markDismissed()
            didChange = true
        }
        return didChange
    }

    private func syncMirror(for application: JobApplication) -> Bool {
        let targetDate: Date?
        if application.status == .archived {
            targetDate = nil
        } else {
            targetDate = application.nextPendingFollowUpStep?.dueDate
        }
        guard application.nextFollowUpDate != targetDate else { return false }
        application.nextFollowUpDate = targetDate
        application.updateTimestamp()
        return true
    }

    private func hasAppliedCadenceSteps(in application: JobApplication) -> Bool {
        application.sortedFollowUpSteps.contains {
            $0.cadenceKind == .applicationApplied && $0.kind != .legacyManual
        }
    }

    private func hasPostInterviewCadenceSteps(in application: JobApplication) -> Bool {
        application.sortedFollowUpSteps.contains { $0.cadenceKind == .postInterview }
    }

    private func latestCompletedInterview(for application: JobApplication) -> ApplicationActivity? {
        application.sortedInterviewActivities.first(where: { !$0.isScheduledInterview })
    }

    private func responseAdjustmentDays(
        for application: JobApplication,
        in context: ModelContext?
    ) -> Int {
        let history: [JobApplication]
        if let context {
            let allApplications = (try? context.fetch(FetchDescriptor<JobApplication>())) ?? []
            history = allApplications.filter { $0.id != application.id && belongsToSameCompany($0, as: application) }
        } else {
            history = []
        }

        let latencies = history.compactMap(firstResponseLatencyDays(for:)).sorted()
        guard !latencies.isEmpty else { return 0 }
        let median = latencies[latencies.count / 2]
        if median <= 3 { return -1 }
        if median >= 10 { return 2 }
        return 0
    }

    private func firstResponseLatencyDays(for application: JobApplication) -> Int? {
        guard let appliedDate = application.appliedDate else { return nil }

        let responseDates = application.sortedActivities.compactMap { activity -> Date? in
            guard activity.occurredAt >= appliedDate else { return nil }
            if activity.kind == .statusChange,
               let toStatus = activity.toStatus,
               toStatus == .interviewing || toStatus == .offered || toStatus == .rejected {
                return activity.occurredAt
            }

            guard !activity.isSystemGenerated else { return nil }
            switch activity.kind {
            case .interview, .email, .call, .text:
                return activity.occurredAt
            case .note, .statusChange, .followUp:
                return nil
            }
        }

        guard let firstResponse = responseDates.min() else { return nil }
        return calendar.dateComponents([.day], from: appliedDate, to: firstResponse).day
    }

    private func belongsToSameCompany(_ lhs: JobApplication, as rhs: JobApplication) -> Bool {
        if let lhsCompanyID = lhs.company?.id, let rhsCompanyID = rhs.company?.id {
            return lhsCompanyID == rhsCompanyID
        }

        return normalizedCompanyName(lhs.companyName) == normalizedCompanyName(rhs.companyName)
    }

    private func normalizedCompanyName(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private func scheduledDate(
        from baseline: Date,
        offsetDays: Int,
        responseAdjustmentDays: Int,
        applyBusinessDayRules: Bool
    ) -> Date {
        let shifted = calendar.date(byAdding: .day, value: offsetDays + responseAdjustmentDays, to: baseline) ?? baseline
        if applyBusinessDayRules {
            return nextAllowedBusinessDate(from: shifted)
        }
        return anchorTime(on: shifted)
    }

    private func nextAllowedBusinessDate(from date: Date) -> Date {
        var candidate = anchorTime(on: date)
        while isBlockedFollowUpWeekday(candidate) {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            candidate = anchorTime(on: candidate)
        }
        return candidate
    }

    private func anchorTime(on date: Date) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 10
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? date
    }

    private func isBlockedFollowUpWeekday(_ date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 2 || weekday == 7
    }
}
