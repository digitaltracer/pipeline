import Foundation
import Testing
@testable import PipelineKit

@Test func atsKeywordExtractionParsesValidJSON() throws {
    let result = try ATSKeywordExtractionService.parseResponse(
        """
        {
          "keywords": [
            {
              "term": "Kubernetes",
              "aliases": ["k8s"],
              "kind": "platform",
              "importance": "core"
            },
            {
              "term": "Stakeholder Communication",
              "aliases": [],
              "kind": "role_concept",
              "importance": "supporting"
            }
          ]
        }
        """,
        companyName: "Uber",
        usage: nil
    )

    #expect(result.keywords.count == 2)
    #expect(result.keywords[0] == ATSKeywordCandidate(
        term: "Kubernetes",
        aliases: ["k8s"],
        kind: .platform,
        importance: .core
    ))
    #expect(result.keywords[1].kind == .roleConcept)
}

@Test func atsKeywordExtractionRecoversEmbeddedJSONAndSanitizesBoilerplate() throws {
    let result = try ATSKeywordExtractionService.parseResponse(
        """
        ```json
        {
          "keywords": [
            {
              "term": "Uber",
              "aliases": [],
              "kind": "domain",
              "importance": "core"
            },
            {
              "term": "They",
              "aliases": [],
              "kind": "role_concept",
              "importance": "supporting"
            },
            {
              "term": "Kubernetes",
              "aliases": ["k8s", "Kubernetes"],
              "kind": "platform",
              "importance": "core"
            }
          ]
        }
        ```
        """,
        companyName: "Uber",
        usage: nil
    )

    #expect(result.keywords.count == 1)
    #expect(result.keywords[0].term == "Kubernetes")
    #expect(result.keywords[0].aliases == ["k8s"])
}

@Test func atsKeywordExtractionRejectsMalformedOrEmptyPayload() {
    #expect(throws: Error.self) {
        try ATSKeywordExtractionService.parseResponse(
            "{\"keywords\":[]}",
            companyName: "Acme",
            usage: nil
        )
    }

    #expect(throws: Error.self) {
        try ATSKeywordExtractionService.parseResponse(
            "not json",
            companyName: "Acme",
            usage: nil
        )
    }
}
