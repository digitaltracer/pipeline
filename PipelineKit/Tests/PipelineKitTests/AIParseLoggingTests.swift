import Testing
@testable import PipelineKit

@Test func aiParsePreviewRedactsSensitiveText() {
    let preview = AIParseDebugLogger.preview("Highly sensitive resume text", maxLength: 10)
    #expect(preview == "<redacted 10 chars>")
}

@Test func aiParseSummarizedURLStripsQueryAndFragment() {
    let summary = AIParseDebugLogger.summarizedURL("https://example.com/jobs/123?token=secret#fragment")
    #expect(summary == "example.com/jobs/123")
}
