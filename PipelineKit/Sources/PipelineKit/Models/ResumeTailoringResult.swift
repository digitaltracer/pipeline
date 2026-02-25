import Foundation

public struct ResumeTailoringResult: Codable, Sendable, Equatable {
    public let patches: [ResumePatch]
    public let sectionGaps: [String]

    public init(patches: [ResumePatch], sectionGaps: [String]) {
        self.patches = patches
        self.sectionGaps = sectionGaps
    }
}
