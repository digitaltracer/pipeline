import Testing
@testable import PipelineKit

@Test func currencyFormatting() {
    let formatted = Currency.usd.format(120000)
    #expect(formatted.contains("120"))
}

@Test func urlNormalization() {
    let result = URLHelpers.normalize("example.com")
    #expect(result == "https://example.com")
}
