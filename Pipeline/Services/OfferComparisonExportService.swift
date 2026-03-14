import Foundation
import PipelineKit

#if os(macOS)
import AppKit

enum OfferComparisonPDFExportService {
    static func makeDocument(
        worksheet: OfferComparisonWorksheet,
        applications: [JobApplication],
        evaluation: OfferComparisonEvaluation,
        scoringService: OfferComparisonScoringService = OfferComparisonScoringService()
    ) throws -> ResumePDFFileDocument {
        let report = OfferComparisonReportBuilder.makeReport(
            worksheet: worksheet,
            applications: applications,
            evaluation: evaluation,
            scoringService: scoringService
        )
        return ResumePDFFileDocument(data: try renderPDF(from: report))
    }

    private static func renderPDF(from report: String) throws -> Data {
        let pageWidth: CGFloat = 612
        let padding: CGFloat = 36
        let contentWidth = pageWidth - (padding * 2)

        let textStorage = NSTextStorage(
            string: report,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
        )
        let textContainer = NSTextContainer(containerSize: CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let usedRect = layoutManager.usedRect(for: textContainer)
        let height = max(usedRect.height + (padding * 2), 792)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: height), textContainer: textContainer)
        textView.textStorage?.setAttributedString(textStorage)
        textView.backgroundColor = .white
        textView.drawsBackground = true
        textView.isEditable = false
        textView.textContainerInset = CGSize(width: padding, height: padding)

        return textView.dataWithPDF(inside: textView.bounds)
    }
}
#endif

enum OfferComparisonReportBuilder {
    static func makeReport(
        worksheet: OfferComparisonWorksheet,
        applications: [JobApplication],
        evaluation: OfferComparisonEvaluation,
        scoringService: OfferComparisonScoringService = OfferComparisonScoringService()
    ) -> String {
        let selectedApplications = scoringService.selectedApplications(for: worksheet, from: applications)
        let factors = worksheet.sortedFactors.filter(\.isEnabled)

        let summary = [
            "Pipeline Offer Comparison",
            "",
            "Generated: \(Date().formatted(date: .abbreviated, time: .shortened))",
            "Selected offers: \(selectedApplications.count)",
            evaluation.isComplete
                ? "Calculated recommendation: \(evaluation.results.first?.companyName ?? "—")"
                : "Calculated recommendation: incomplete worksheet",
            ""
        ].joined(separator: "\n")

        let table = factors.map { factor in
            let cells = selectedApplications.map { application in
                let value = scoringService.displayValue(for: factor, application: application)
                return "\(application.companyName): \(value.text) [score: \(value.score.map(String.init) ?? "missing")]"
            }.joined(separator: " | ")
            return "\(factor.title) (weight \(factor.weight))\n\(cells)"
        }.joined(separator: "\n\n")

        let ranking = evaluation.results.enumerated().map { index, result in
            "\(index + 1). \(result.companyName) - \(result.role) - \(String(format: "%.2f", result.weightedAverage))/5"
        }.joined(separator: "\n")

        let recommendation = [
            "AI Recommendation",
            worksheet.recommendationText ?? "Not generated.",
            "",
            citationsText(title: "Recommendation Citations", citations: worksheet.recommendationCitations)
        ].joined(separator: "\n")

        let negotiation = [
            "Negotiation Helper",
            worksheet.negotiationText ?? "Not generated.",
            "",
            citationsText(title: "Negotiation Citations", citations: worksheet.negotiationCitations)
        ].joined(separator: "\n")

        return [
            summary,
            "Worksheet",
            table,
            "",
            "Ranking",
            ranking.isEmpty ? "No ranking available." : ranking,
            "",
            recommendation,
            "",
            negotiation
        ].joined(separator: "\n")
    }

    private static func citationsText(title: String, citations: [AIWebSearchCitation]) -> String {
        let body = citations.isEmpty
            ? "No citations saved."
            : citations.enumerated().map { index, citation in
                "\(index + 1). \(citation.title) - \(citation.urlString)"
            }.joined(separator: "\n")
        return "\(title)\n\(body)"
    }
}
