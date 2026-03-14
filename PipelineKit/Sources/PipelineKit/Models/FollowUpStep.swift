import Foundation
import SwiftData

@Model
public final class FollowUpStep {
    public var id: UUID = UUID()
    public var dueDate: Date = Date()
    public var originalDueDate: Date = Date()
    private var stateRawValue: String = FollowUpStepState.pending.rawValue
    private var kindRawValue: String = FollowUpStepKind.legacyManual.rawValue
    private var cadenceKindRawValue: String = FollowUpCadenceKind.applicationApplied.rawValue
    public var sequenceIndex: Int = 0
    public var completedAt: Date?
    public var snoozedUntil: Date?
    public var snoozeCount: Int = 0
    public var lastGeneratedSubject: String?
    public var lastGeneratedBody: String?
    public var lastGeneratedAt: Date?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var application: JobApplication?

    public var state: FollowUpStepState {
        get { FollowUpStepState(rawValue: stateRawValue) ?? .pending }
        set {
            guard stateRawValue != newValue.rawValue else { return }
            stateRawValue = newValue.rawValue
            updateTimestamp()
        }
    }

    public var kind: FollowUpStepKind {
        get { FollowUpStepKind(rawValue: kindRawValue) ?? .legacyManual }
        set {
            guard kindRawValue != newValue.rawValue else { return }
            kindRawValue = newValue.rawValue
            updateTimestamp()
        }
    }

    public var cadenceKind: FollowUpCadenceKind {
        get { FollowUpCadenceKind(rawValue: cadenceKindRawValue) ?? .applicationApplied }
        set {
            guard cadenceKindRawValue != newValue.rawValue else { return }
            cadenceKindRawValue = newValue.rawValue
            updateTimestamp()
        }
    }

    public init(
        id: UUID = UUID(),
        dueDate: Date,
        originalDueDate: Date? = nil,
        state: FollowUpStepState = .pending,
        kind: FollowUpStepKind,
        cadenceKind: FollowUpCadenceKind,
        sequenceIndex: Int,
        completedAt: Date? = nil,
        snoozedUntil: Date? = nil,
        snoozeCount: Int = 0,
        lastGeneratedSubject: String? = nil,
        lastGeneratedBody: String? = nil,
        lastGeneratedAt: Date? = nil,
        application: JobApplication? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.dueDate = dueDate
        self.originalDueDate = originalDueDate ?? dueDate
        self.stateRawValue = state.rawValue
        self.kindRawValue = kind.rawValue
        self.cadenceKindRawValue = cadenceKind.rawValue
        self.sequenceIndex = sequenceIndex
        self.completedAt = completedAt
        self.snoozedUntil = snoozedUntil
        self.snoozeCount = snoozeCount
        self.lastGeneratedSubject = lastGeneratedSubject
        self.lastGeneratedBody = lastGeneratedBody
        self.lastGeneratedAt = lastGeneratedAt
        self.application = application
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isActive: Bool {
        state.isActive
    }

    public func setDueDate(_ date: Date, preserveOriginalDate: Bool = true) {
        dueDate = date
        if !preserveOriginalDate || originalDueDate == .distantPast {
            originalDueDate = date
        }
        if state == .snoozed {
            snoozedUntil = date
        }
        updateTimestamp()
    }

    public func markCompleted(at date: Date = Date()) {
        state = .completed
        completedAt = date
        snoozedUntil = nil
        updateTimestamp()
    }

    public func markDismissed() {
        state = .dismissed
        completedAt = nil
        snoozedUntil = nil
        updateTimestamp()
    }

    public func markPending() {
        state = .pending
        completedAt = nil
        snoozedUntil = nil
        updateTimestamp()
    }

    public func snooze(until date: Date) {
        state = .snoozed
        dueDate = date
        snoozedUntil = date
        snoozeCount += 1
        completedAt = nil
        updateTimestamp()
    }

    public func saveGeneratedDraft(subject: String?, body: String?, generatedAt: Date = Date()) {
        lastGeneratedSubject = normalized(subject)
        lastGeneratedBody = normalized(body)
        lastGeneratedAt = generatedAt
        updateTimestamp()
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
