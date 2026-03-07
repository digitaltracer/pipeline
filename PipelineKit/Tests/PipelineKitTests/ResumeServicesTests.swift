import Foundation
import SwiftData
import Testing
@testable import PipelineKit

@Test func resumeSchemaValidatorAcceptsKnownSchema() throws {
    let sample = """
    {
      "name": "A Test",
      "contact": {
        "phone": "111",
        "email": "test@example.com",
        "linkedin": "linkedin.com/in/test",
        "github": "github.com/test"
      },
      "education": [{"university":"U","location":"L","degree":"D","date":"2020"}],
      "summary": "Summary",
      "experience": [{"title":"SWE","company":"C","location":"L","dates":"2020-2022","responsibilities":["Built APIs"]}],
      "projects": [{"name":"P","url":"https://example.com","technologies":["Swift"],"date":"2024","description":["Desc"]}],
      "skills": {"Languages":["Swift"]},
      "meta": {"notes": "preserve me"}
    }
    """

    let result = try ResumeSchemaValidator.validate(jsonText: sample)
    #expect(result.schema.name == "A Test")
    #expect(result.unknownFieldPaths.contains("/meta"))
    #expect(result.normalizedJSON.contains("https://example.com"))
    #expect(!result.normalizedJSON.contains("\\/\\/example.com"))
}

@Test func resumePatchSafetyRejectsUnrelatedSkillAddWithoutEvidence() throws {
    let sample = """
    {
      "name": "A Test",
      "contact": {"phone":"1","email":"a@b.com","linkedin":"x","github":"y"},
      "education": [{"university":"U","location":"L","degree":"D","date":"2020"}],
      "experience": [{"title":"SWE","company":"C","location":"L","dates":"2020-2022","responsibilities":["Built APIs"]}],
      "projects": [{"name":"P","url":"https://example.com","technologies":["Swift"],"date":"2024","description":["Desc"]}],
      "skills": {"Languages":["Swift"]}
    }
    """

    let patch = ResumePatch(
        path: "/skills/Languages/1",
        operation: .add,
        beforeValue: nil,
        afterValue: .string("Rust"),
        reason: "Add for JD",
        evidencePaths: [],
        risk: .high
    )

    let result = try ResumePatchSafetyValidator.validate(patches: [patch], originalJSON: sample)
    #expect(result.accepted.isEmpty)
    #expect(result.rejected.count == 1)
}

@Test func resumePatchApplierHandlesReplaceAddRemove() throws {
    let sample = """
    {
      "name": "A Test",
      "contact": {"phone":"1","email":"a@b.com","linkedin":"x","github":"y"},
      "education": [{"university":"U","location":"L","degree":"D","date":"2020"}],
      "experience": [{"title":"SWE","company":"C","location":"L","dates":"2020-2022","responsibilities":["Built APIs"]}],
      "projects": [{"name":"P","url":"https://example.com","technologies":["Swift"],"date":"2024","description":["Desc"]}],
      "skills": {"Languages":["Swift"]}
    }
    """

    let replaceName = ResumePatch(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        path: "/name",
        operation: .replace,
        beforeValue: .string("A Test"),
        afterValue: .string("A Better Test"),
        reason: "Better",
        evidencePaths: ["/summary"],
        risk: .low
    )

    let addSkill = ResumePatch(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        path: "/skills/Languages/-",
        operation: .add,
        beforeValue: nil,
        afterValue: .string("TypeScript"),
        reason: "Already used",
        evidencePaths: ["/projects/0/description/0"],
        risk: .medium
    )

    let removeProjectURL = ResumePatch(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        path: "/projects/0/url",
        operation: .remove,
        beforeValue: .string("https://example.com"),
        afterValue: nil,
        reason: "Not required",
        evidencePaths: [],
        risk: .low
    )

    let output = try ResumePatchApplier.apply(
        patches: [replaceName, addSkill, removeProjectURL],
        acceptedPatchIDs: [replaceName.id, addSkill.id, removeProjectURL.id],
        to: sample
    )

    #expect(output.contains("A Better Test"))
    #expect(output.contains("TypeScript"))
    #expect(!output.contains("example.com"))
}

@Test func resumeTailoringParserRejectsMalformedJSON() {
    do {
        _ = try ResumeTailoringService.parseResult(from: "not a json payload")
        Issue.record("Expected parseResult to fail for malformed JSON.")
    } catch let error as AIServiceError {
        switch error {
        case .parsingError(let message):
            #expect(message.contains("not valid JSON"))
            #expect(message.contains("AIParse"))
        default:
            Issue.record("Expected parsingError, got \(error)")
        }
    } catch {
        Issue.record("Expected AIServiceError, got \(error)")
    }
}

@Test func resumeTailoringParserReturnsTruncatedErrorForCutoffJSON() {
    let payload = """
    {
      "patches": [
        {
          "id": "a4d3e8f1-c7b2-4a1e-9d0f-5b6c7a8d9e0f",
          "path": "/summary",
          "operation": "replace",
          "beforeValue": "Senior backend engineer with over 9 years
    """

    do {
        _ = try ResumeTailoringService.parseResult(from: payload)
        Issue.record("Expected parseResult to fail for truncated JSON.")
    } catch let error as AIServiceError {
        switch error {
        case .parsingError(let message):
            #expect(message.contains("appears truncated"))
            #expect(message.contains("AIParse"))
        default:
            Issue.record("Expected parsingError, got \(error)")
        }
    } catch {
        Issue.record("Expected AIServiceError, got \(error)")
    }
}

@Test func resumeTailoringParserAcceptsMarkdownWrappedSnakeCasePayload() throws {
    let payload = """
    ```json
    {
      "patches": [
        {
          "path": "/summary",
          "op": "REPLACE",
          "before": "Old summary",
          "after": "Tailored summary",
          "reason": "Highlight relevant impact",
          "evidence_paths": ["/experience/0/responsibilities/0"],
          "risk": "HIGH"
        }
      ],
      "section_gaps": ["Leadership examples"]
    }
    ```
    """

    let result = try ResumeTailoringService.parseResult(from: payload)
    #expect(result.patches.count == 1)
    #expect(result.patches[0].operation == .replace)
    #expect(result.patches[0].risk == .high)
    #expect(result.sectionGaps == ["Leadership examples"])
}

@Test func resumeTailoringParserReturnsSchemaMismatchForWrongJSONShape() {
    let payload = #"{"foo":"bar"}"#

    do {
        _ = try ResumeTailoringService.parseResult(from: payload)
        Issue.record("Expected parseResult to fail for schema mismatch.")
    } catch let error as AIServiceError {
        switch error {
        case .parsingError(let message):
            #expect(message.contains("expected schema"))
            #expect(message.contains("AIParse"))
        default:
            Issue.record("Expected parsingError, got \(error)")
        }
    } catch {
        Issue.record("Expected AIServiceError, got \(error)")
    }
}

@Test func resumeSchemaValidatorAllowsEmptySectionsWhenSchemaIsValid() throws {
    let sample = """
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

    let result = try ResumeSchemaValidator.validate(jsonText: sample)
    #expect(result.normalizedJSON.contains("\"education\""))
}

@Test func resumeSchemaValidatorIncludesPathForMissingRequiredKey() {
    let sample = """
    {
      "name": "A Test",
      "contact": {
        "phone": "111",
        "linkedin": "linkedin.com/in/test",
        "github": "github.com/test"
      },
      "education": [],
      "summary": "",
      "experience": [],
      "projects": [],
      "skills": {}
    }
    """

    do {
        _ = try ResumeSchemaValidator.validate(jsonText: sample)
        Issue.record("Expected schema validation to fail for missing contact.email")
    } catch let error as ResumeSchemaValidationError {
        switch error {
        case .schemaMismatch(let message):
            #expect(message.contains("/contact/email"))
        default:
            Issue.record("Expected schemaMismatch, got \(error)")
        }
    } catch {
        Issue.record("Expected ResumeSchemaValidationError, got \(error)")
    }
}

@Test func resumeRevisionDiffServiceProducesAddedAndRemovedLines() {
    let oldText = """
    {
      "name": "A Test",
      "skills": {
        "Languages": [
          "Swift",
          "Python"
        ]
      }
    }
    """

    let newText = """
    {
      "name": "A Better Test",
      "skills": {
        "Languages": [
          "Swift",
          "Go"
        ]
      }
    }
    """

    let diff = ResumeRevisionDiffService.diff(from: oldText, to: newText)
    #expect(diff.hasChanges)
    #expect(diff.addedLineCount > 0)
    #expect(diff.removedLineCount > 0)

    let flattened = diff.hunks.flatMap(\.lines)
    #expect(flattened.contains(where: { $0.kind == .added && $0.content.contains("\"Go\"") }))
    #expect(flattened.contains(where: { $0.kind == .removed && $0.content.contains("\"Python\"") }))
}

@Test func resumeStoreSaveAndFetchMasterRevisions() throws {
    let schema = Schema([
        JobApplication.self,
        JobSearchCycle.self,
        SearchGoal.self,
        InterviewLog.self,
        Contact.self,
        ApplicationContactLink.self,
        ApplicationActivity.self,
        ResumeMasterRevision.self,
        ResumeJobSnapshot.self,
        AIUsageRecord.self,
        AIModelRate.self
    ])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = ModelContext(container)

    let first = try ResumeStoreService.saveMasterRevision(
        rawJSON: #"{"name":"A"}"#,
        unknownFieldPaths: ["/meta"],
        in: context
    )

    var revisions = try ResumeStoreService.masterRevisions(in: context)
    #expect(revisions.count == 1)
    #expect(revisions.first?.isCurrent == true)
    #expect(revisions.first?.unknownFieldPaths == ["/meta"])
    #expect(try ResumeStoreService.currentMasterRevision(in: context)?.id == first.id)

    let second = try ResumeStoreService.saveMasterRevision(
        rawJSON: #"{"name":"B"}"#,
        unknownFieldPaths: [],
        in: context
    )

    revisions = try ResumeStoreService.masterRevisions(in: context)
    #expect(revisions.count == 2)
    #expect(try ResumeStoreService.currentMasterRevision(in: context)?.id == second.id)
    #expect(revisions.contains(where: { $0.id == first.id && $0.isCurrent == false }))
}

@Test func resumeTailoringResultRetainsUsageMetadata() throws {
    let usage = AIUsageMetrics(promptTokens: 120, completionTokens: 80, totalTokens: 200)
    let result = ResumeTailoringResult(
        patches: [],
        sectionGaps: ["Summary"],
        usage: usage
    )

    let encoded = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(ResumeTailoringResult.self, from: encoded)

    #expect(decoded.usage == usage)
    #expect(decoded.sectionGaps == ["Summary"])
}

@Test func parsedJobDataCanCarryUsageMetrics() {
    let usage = AIUsageMetrics(promptTokens: 10, completionTokens: 25, totalTokens: 35)
    let parsed = ParsedJobData(
        companyName: "Example",
        role: "iOS Engineer",
        location: "Remote",
        jobDescription: "Build apps",
        salaryMin: nil,
        salaryMax: nil,
        currency: .usd,
        usage: usage
    )

    #expect(parsed.usage?.totalTokens == 35)
    #expect(parsed.hasMeaningfulContent)
}
