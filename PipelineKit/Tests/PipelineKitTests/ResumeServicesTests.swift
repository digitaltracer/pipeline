import Foundation
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
    #expect(throws: Error.self) {
        _ = try ResumeTailoringService.parseResult(from: "not a json payload")
    }
}
