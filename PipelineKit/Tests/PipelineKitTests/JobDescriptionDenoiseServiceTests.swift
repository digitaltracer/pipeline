import Testing
@testable import PipelineKit

@Test func jobDescriptionDenoiseParserAcceptsValidJSON() throws {
    let usage = AIUsageMetrics(promptTokens: 120, completionTokens: 80, totalTokens: 200)
    let result = try JobDescriptionDenoiseService.parseResponse(
        #"{"cleanedDescription":"Senior iOS Engineer\n- Build SwiftUI features\n- Partner with design"}"#,
        usage: usage
    )

    #expect(result.cleanedDescription.contains("Senior iOS Engineer"))
    #expect(result.cleanedDescription.contains("Build SwiftUI features"))
    #expect(result.usage == usage)
}

@Test func jobDescriptionDenoiseParserAcceptsMarkdownWrappedPayload() throws {
    let result = try JobDescriptionDenoiseService.parseResponse(
        """
        ```json
        {
          "cleaned_description": "Responsibilities\\n- Ship product\\n- Review code"
        }
        ```
        """,
        usage: nil
    )

    #expect(result.cleanedDescription.contains("Responsibilities"))
    #expect(result.cleanedDescription.contains("Review code"))
}

@Test func jobDescriptionDenoiseParserRejectsMalformedPayload() {
    do {
        _ = try JobDescriptionDenoiseService.parseResponse(
            #"{"cleanedDescription":}"#,
            usage: nil
        )
        Issue.record("Expected parseResponse to fail for malformed JSON.")
    } catch let error as AIServiceError {
        guard case .parsingError = error else {
            Issue.record("Expected parsingError, got \(error)")
            return
        }
    } catch {
        Issue.record("Expected AIServiceError, got \(error)")
    }
}
