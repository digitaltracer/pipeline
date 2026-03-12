import Foundation
import SwiftData

@Model
public final class CoverLetterDraft {
    public var id: UUID = UUID()
    private var toneRawValue: String = CoverLetterTone.formal.rawValue
    public var greeting: String = ""
    public var hookParagraph: String = ""
    public var bodyParagraphs: [String] = []
    public var closingParagraph: String = ""
    public var plainText: String = ""
    public var sourceResumeKind: String?
    public var sourceResumeLabel: String?
    public var sourceResumeSnapshotID: UUID?
    public var lastGeneratedProviderID: String?
    public var lastGeneratedModel: String?
    public var lastGeneratedAt: Date?
    public var application: JobApplication?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var tone: CoverLetterTone {
        get { CoverLetterTone(rawValue: toneRawValue) ?? .formal }
        set { toneRawValue = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        tone: CoverLetterTone = .formal,
        greeting: String = "",
        hookParagraph: String = "",
        bodyParagraphs: [String] = [],
        closingParagraph: String = "",
        plainText: String? = nil,
        sourceResumeKind: String? = nil,
        sourceResumeLabel: String? = nil,
        sourceResumeSnapshotID: UUID? = nil,
        lastGeneratedProviderID: String? = nil,
        lastGeneratedModel: String? = nil,
        lastGeneratedAt: Date? = nil,
        application: JobApplication? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.toneRawValue = tone.rawValue
        self.greeting = greeting
        self.hookParagraph = hookParagraph
        self.bodyParagraphs = bodyParagraphs
        self.closingParagraph = closingParagraph
        self.plainText = plainText ?? Self.composePlainText(
            greeting: greeting,
            hookParagraph: hookParagraph,
            bodyParagraphs: bodyParagraphs,
            closingParagraph: closingParagraph
        )
        self.sourceResumeKind = sourceResumeKind
        self.sourceResumeLabel = sourceResumeLabel
        self.sourceResumeSnapshotID = sourceResumeSnapshotID
        self.lastGeneratedProviderID = lastGeneratedProviderID
        self.lastGeneratedModel = lastGeneratedModel
        self.lastGeneratedAt = lastGeneratedAt
        self.application = application
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var hasContent: Bool {
        !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func applyEdits(
        tone: CoverLetterTone,
        greeting: String,
        hookParagraph: String,
        bodyParagraphs: [String],
        closingParagraph: String,
        shouldTouch: Bool = true
    ) {
        toneRawValue = tone.rawValue
        self.greeting = greeting
        self.hookParagraph = hookParagraph
        self.bodyParagraphs = bodyParagraphs
        self.closingParagraph = closingParagraph
        refreshPlainText(shouldTouch: shouldTouch)
    }

    public func recordGenerationMetadata(
        sourceResumeKind: String?,
        sourceResumeLabel: String?,
        sourceResumeSnapshotID: UUID?,
        providerID: String?,
        model: String?,
        generatedAt: Date = Date(),
        shouldTouch: Bool = true
    ) {
        self.sourceResumeKind = sourceResumeKind
        self.sourceResumeLabel = sourceResumeLabel
        self.sourceResumeSnapshotID = sourceResumeSnapshotID
        self.lastGeneratedProviderID = providerID
        self.lastGeneratedModel = model
        self.lastGeneratedAt = generatedAt
        if shouldTouch {
            updateTimestamp()
        }
    }

    public func refreshPlainText(shouldTouch: Bool = true) {
        plainText = Self.composePlainText(
            greeting: greeting,
            hookParagraph: hookParagraph,
            bodyParagraphs: bodyParagraphs,
            closingParagraph: closingParagraph
        )
        if shouldTouch {
            updateTimestamp()
        }
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }

    public static func composePlainText(
        greeting: String,
        hookParagraph: String,
        bodyParagraphs: [String],
        closingParagraph: String
    ) -> String {
        let sections = [greeting, hookParagraph]
            + bodyParagraphs
            + [closingParagraph]

        return sections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
