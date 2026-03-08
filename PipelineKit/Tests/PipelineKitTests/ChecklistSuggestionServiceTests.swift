import Foundation
import Testing
@testable import PipelineKit

@Test func checklistSuggestionServiceParsesValidJSON() throws {
    let rawJSON = """
    {
      "suggestions": [
        {
          "title": "Draft a migration story for distributed systems work",
          "rationale": "This role emphasizes large-scale systems. A crisp story helps you answer technical and behavioral prompts."
        },
        {
          "title": "Collect two metrics-driven launch examples",
          "rationale": "The team will likely ask for impact. Quantified examples make your examples sharper."
        }
      ]
    }
    """

    let result = try ChecklistSuggestionService.parseResponse(rawJSON, usage: nil)

    #expect(result.suggestions.count == 2)
    #expect(result.suggestions.first?.title == "Draft a migration story for distributed systems work")
    #expect(result.suggestions.first?.rationale.contains("large-scale systems") == true)
}

@Test func checklistSuggestionServiceStripsMarkdownFences() throws {
    let rawJSON = """
    ```json
    {
      "suggestions": [
        {
          "title": "Prepare a portfolio walkthrough",
          "rationale": "The hiring manager may want to see product thinking in action."
        }
      ]
    }
    ```
    """

    let result = try ChecklistSuggestionService.parseResponse(rawJSON, usage: nil)

    #expect(result.suggestions.count == 1)
    #expect(result.suggestions.first?.title == "Prepare a portfolio walkthrough")
}

@Test func checklistSuggestionServiceRejectsMalformedJSON() {
    let rawJSON = "not valid json"

    #expect(throws: AIServiceError.self) {
        _ = try ChecklistSuggestionService.parseResponse(rawJSON, usage: nil)
    }
}

@Test func checklistSuggestionFeatureHasDedicatedCostCenterLabel() {
    #expect(AIUsageFeature.checklistSuggestions.title == "Checklist Suggestions")
}
