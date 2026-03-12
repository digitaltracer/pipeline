import Foundation

public struct ResumeTailoringResult: Codable, Sendable, Equatable {
    public let patches: [ResumePatch]
    public let sectionGaps: [String]
    public let usage: AIUsageMetrics?

    public init(
        patches: [ResumePatch],
        sectionGaps: [String],
        usage: AIUsageMetrics? = nil
    ) {
        self.patches = patches
        self.sectionGaps = sectionGaps
        self.usage = usage
    }
}
