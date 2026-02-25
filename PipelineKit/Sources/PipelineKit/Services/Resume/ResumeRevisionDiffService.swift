import Foundation

public struct ResumeDiffLine: Sendable, Hashable {
    public enum Kind: String, Sendable {
        case context
        case added
        case removed
    }

    public let kind: Kind
    public let oldLineNumber: Int?
    public let newLineNumber: Int?
    public let content: String

    public init(kind: Kind, oldLineNumber: Int?, newLineNumber: Int?, content: String) {
        self.kind = kind
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.content = content
    }
}

public struct ResumeDiffHunk: Sendable, Hashable {
    public let header: String
    public let lines: [ResumeDiffLine]

    public init(header: String, lines: [ResumeDiffLine]) {
        self.header = header
        self.lines = lines
    }
}

public struct ResumeRevisionDiff: Sendable, Hashable {
    public let hunks: [ResumeDiffHunk]
    public let addedLineCount: Int
    public let removedLineCount: Int

    public init(hunks: [ResumeDiffHunk], addedLineCount: Int, removedLineCount: Int) {
        self.hunks = hunks
        self.addedLineCount = addedLineCount
        self.removedLineCount = removedLineCount
    }

    public var hasChanges: Bool {
        addedLineCount > 0 || removedLineCount > 0
    }
}

public enum ResumeRevisionDiffService {
    private struct TraceLine {
        let kind: ResumeDiffLine.Kind
        let oldLineNumber: Int?
        let newLineNumber: Int?
        let content: String
    }

    public static func diff(
        from oldJSON: String,
        to newJSON: String,
        contextLines: Int = 3
    ) -> ResumeRevisionDiff {
        let oldLines = splitLines(oldJSON)
        let newLines = splitLines(newJSON)
        let trace = traceLines(oldLines: oldLines, newLines: newLines)

        let addedCount = trace.reduce(into: 0) { count, line in
            if line.kind == .added {
                count += 1
            }
        }
        let removedCount = trace.reduce(into: 0) { count, line in
            if line.kind == .removed {
                count += 1
            }
        }

        guard addedCount > 0 || removedCount > 0 else {
            return ResumeRevisionDiff(hunks: [], addedLineCount: 0, removedLineCount: 0)
        }

        let hunks = buildHunks(from: trace, contextLines: contextLines)
        return ResumeRevisionDiff(
            hunks: hunks,
            addedLineCount: addedCount,
            removedLineCount: removedCount
        )
    }

    private static func splitLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func traceLines(oldLines: [String], newLines: [String]) -> [TraceLine] {
        let n = oldLines.count
        let m = newLines.count
        var lcs = Array(
            repeating: Array(repeating: 0, count: m + 1),
            count: n + 1
        )

        if n > 0, m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    if oldLines[i] == newLines[j] {
                        lcs[i][j] = lcs[i + 1][j + 1] + 1
                    } else {
                        lcs[i][j] = max(lcs[i + 1][j], lcs[i][j + 1])
                    }
                }
            }
        }

        var i = 0
        var j = 0
        var oldLineNumber = 1
        var newLineNumber = 1
        var trace: [TraceLine] = []

        while i < n, j < m {
            if oldLines[i] == newLines[j] {
                trace.append(
                    TraceLine(
                        kind: .context,
                        oldLineNumber: oldLineNumber,
                        newLineNumber: newLineNumber,
                        content: oldLines[i]
                    )
                )
                i += 1
                j += 1
                oldLineNumber += 1
                newLineNumber += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                trace.append(
                    TraceLine(
                        kind: .removed,
                        oldLineNumber: oldLineNumber,
                        newLineNumber: nil,
                        content: oldLines[i]
                    )
                )
                i += 1
                oldLineNumber += 1
            } else {
                trace.append(
                    TraceLine(
                        kind: .added,
                        oldLineNumber: nil,
                        newLineNumber: newLineNumber,
                        content: newLines[j]
                    )
                )
                j += 1
                newLineNumber += 1
            }
        }

        while i < n {
            trace.append(
                TraceLine(
                    kind: .removed,
                    oldLineNumber: oldLineNumber,
                    newLineNumber: nil,
                    content: oldLines[i]
                )
            )
            i += 1
            oldLineNumber += 1
        }

        while j < m {
            trace.append(
                TraceLine(
                    kind: .added,
                    oldLineNumber: nil,
                    newLineNumber: newLineNumber,
                    content: newLines[j]
                )
            )
            j += 1
            newLineNumber += 1
        }

        return trace
    }

    private static func buildHunks(from trace: [TraceLine], contextLines: Int) -> [ResumeDiffHunk] {
        guard !trace.isEmpty else { return [] }

        let safeContext = max(0, contextLines)
        let changedIndices = trace.indices.filter { trace[$0].kind != .context }
        guard !changedIndices.isEmpty else { return [] }

        var ranges: [(start: Int, end: Int)] = []

        for index in changedIndices {
            let start = max(0, index - safeContext)
            let end = min(trace.count - 1, index + safeContext)

            if let lastIndex = ranges.indices.last, start <= ranges[lastIndex].end + 1 {
                ranges[lastIndex].end = max(ranges[lastIndex].end, end)
            } else {
                ranges.append((start: start, end: end))
            }
        }

        return ranges.map { range in
            let linesSlice = Array(trace[range.start...range.end])

            let oldStart = linesSlice.compactMap(\.oldLineNumber).first ?? 0
            let oldCount = linesSlice.reduce(into: 0) { count, line in
                if line.oldLineNumber != nil {
                    count += 1
                }
            }

            let newStart = linesSlice.compactMap(\.newLineNumber).first ?? 0
            let newCount = linesSlice.reduce(into: 0) { count, line in
                if line.newLineNumber != nil {
                    count += 1
                }
            }

            let header = "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
            let lines = linesSlice.map {
                ResumeDiffLine(
                    kind: $0.kind,
                    oldLineNumber: $0.oldLineNumber,
                    newLineNumber: $0.newLineNumber,
                    content: $0.content
                )
            }

            return ResumeDiffHunk(header: header, lines: lines)
        }
    }
}
