import SwiftUI
import PipelineKit

struct JobDescriptionView: View {
    private enum DescriptionBlock: Equatable {
        case heading(String)
        case paragraph(String)
        case bulletList([String])
    }

    let description: String
    var isDenoising: Bool = false
    var onDenoise: (() -> Void)? = nil
    @State private var isExpanded = false

    private let previewBlockLimit = 4
    private let previewBulletLimit = 4

    private var parsedBlocks: [DescriptionBlock] {
        parseDescription(description)
    }

    private var hasCollapsibleContent: Bool {
        parsedBlocks.count > previewBlockLimit || parsedBlocks.contains {
            if case .bulletList(let items) = $0 {
                return items.count > previewBulletLimit
            }
            return false
        }
    }

    private var displayedBlocks: [DescriptionBlock] {
        guard !isExpanded else { return parsedBlocks }

        var blocks: [DescriptionBlock] = []
        for block in parsedBlocks {
            guard blocks.count < previewBlockLimit else { break }
            switch block {
            case .bulletList(let items):
                let limited = Array(items.prefix(previewBulletLimit))
                if !limited.isEmpty {
                    blocks.append(.bulletList(limited))
                }
            case .heading(let heading):
                if !heading.isEmpty {
                    blocks.append(.heading(heading))
                }
            case .paragraph(let paragraph):
                if !paragraph.isEmpty {
                    blocks.append(.paragraph(paragraph))
                }
            }
        }
        return blocks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Job Description", systemImage: "doc.text")
                    .font(.headline)

                Spacer()

                HStack(spacing: 8) {
                    if let onDenoise {
                        Button(action: onDenoise) {
                            HStack(spacing: 6) {
                                if isDenoising {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(DesignSystem.Colors.accent)
                                } else {
                                    Image(systemName: "sparkles")
                                }

                                Text(isDenoising ? "Denoising..." : "Denoise")
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(DesignSystem.Colors.accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isDenoising)
                        .interactiveHandCursor()
                    }

                    if hasCollapsibleContent {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            Text(isExpanded ? "Show Less" : "Show More")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(DesignSystem.Colors.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(DesignSystem.Colors.accent.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .interactiveHandCursor()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(displayedBlocks.enumerated()), id: \.offset) { _, block in
                    descriptionBlockView(block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    @ViewBuilder
    private func descriptionBlockView(_ block: DescriptionBlock) -> some View {
        switch block {
        case .heading(let text):
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .paragraph(let text):
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(DesignSystem.Colors.accent.opacity(0.9))
                            .frame(width: 5, height: 5)
                            .padding(.top, 8)

                        Text(item)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func parseDescription(_ rawDescription: String) -> [DescriptionBlock] {
        let text = normalizeDescription(rawDescription)
        guard !text.isEmpty else { return [] }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var blocks: [DescriptionBlock] = []
        var paragraphLines: [String] = []
        var bulletItems: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let paragraph = normalizeInlineSpacing(paragraphLines.joined(separator: " "))
            if paragraph.isEmpty {
                paragraphLines.removeAll()
                return
            }

            if isHeadingLine(paragraph) {
                blocks.append(.heading(paragraph))
            } else {
                blocks.append(.paragraph(paragraph))
            }
            paragraphLines.removeAll()
        }

        func flushBullets() {
            guard !bulletItems.isEmpty else { return }
            let cleanedItems = bulletItems.filter { !$0.isEmpty }
            if !cleanedItems.isEmpty {
                blocks.append(.bulletList(cleanedItems))
            }
            bulletItems.removeAll()
        }

        for line in lines {
            if line.isEmpty {
                flushParagraph()
                flushBullets()
                continue
            }

            if let bulletText = bulletItem(from: line) {
                flushParagraph()
                let cleaned = cleanBulletItem(bulletText)
                if !cleaned.isEmpty {
                    bulletItems.append(cleaned)
                }
                continue
            }

            flushBullets()
            paragraphLines.append(line)
        }

        flushParagraph()
        flushBullets()

        return blocks.filter { block in
            switch block {
            case .heading(let text), .paragraph(let text):
                return !text.isEmpty
            case .bulletList(let items):
                return !items.isEmpty
            }
        }
    }

    private func normalizeDescription(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")

        let bulletCharacters: Set<Character> = ["•", "●", "◦", "▪", "‣", "∙"]
        var transformed = ""
        var previousCharacter: Character?
        var index = normalized.startIndex

        while index < normalized.endIndex {
            let character = normalized[index]

            if bulletCharacters.contains(character) {
                let previous = previousCharacter
                if let previous, previous != "\n" {
                    transformed.append("\n")
                }
                transformed.append("•")
                transformed.append(" ")

                index = normalized.index(after: index)
                while index < normalized.endIndex,
                      normalized[index].isWhitespace,
                      normalized[index] != "\n" {
                    index = normalized.index(after: index)
                }
                previousCharacter = " "
                continue
            }

            transformed.append(character)
            previousCharacter = character
            index = normalized.index(after: index)
        }

        normalized = transformed
        normalized = normalized.replacingOccurrences(
            of: #"(?m)[ ]{2,}"#,
            with: " ",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func bulletItem(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("•") || trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func normalizeInlineSpacing(_ text: String) -> String {
        text.replacingOccurrences(of: #"[ ]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanBulletItem(_ text: String) -> String {
        let cleaned = normalizeInlineSpacing(text)
            .replacingOccurrences(
                of: #"^[a-z]\s+(?=[A-Z])"#,
                with: "",
                options: .regularExpression
            )
        return cleaned
    }

    private func isHeadingLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.count <= 60 else { return false }
        if trimmed.hasSuffix(":") { return true }
        if trimmed.contains(".") || trimmed.contains("?") || trimmed.contains("!") { return false }

        let words = trimmed.split(separator: " ")
        guard words.count <= 7 else { return false }

        let startsWithUppercase = trimmed.unicodeScalars.first.map {
            CharacterSet.uppercaseLetters.contains($0)
        } ?? false

        let lowercaseWords: Set<String> = ["and", "or", "to", "for", "the", "of", "with", "in", "a", "an"]
        let mostlyTitleCase = words.filter { word in
            guard let scalar = word.unicodeScalars.first else { return false }
            if CharacterSet.uppercaseLetters.contains(scalar) { return true }
            return lowercaseWords.contains(word.lowercased())
        }.count >= max(1, words.count - 1)

        return startsWithUppercase && mostlyTitleCase
    }
}

#Preview {
    JobDescriptionView(
        description: """
        We are looking for an experienced iOS developer to join our team. You will be responsible for developing and maintaining our iOS applications.

        Requirements:
        - 5+ years of iOS development experience
        - Strong knowledge of Swift and SwiftUI
        - Experience with Core Data and CloudKit
        - Excellent problem-solving skills
        - Strong communication skills

        Nice to have:
        - Experience with macOS development
        - Knowledge of CI/CD pipelines
        - Open source contributions
        """
    )
    .padding()
}
