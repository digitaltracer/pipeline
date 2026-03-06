import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import PipelineKit

struct ResumeJSONFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return .init(regularFileWithContents: data)
    }
}

struct ResumePDFFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        .init(regularFileWithContents: data)
    }
}

enum ResumeJSONExportService {
    static func makeDocument(json: String) throws -> ResumeJSONFileDocument {
        let normalized = try ResumeSchemaValidator.validate(jsonText: json).normalizedJSON
        return ResumeJSONFileDocument(text: normalized)
    }
}

enum ResumeHTMLRenderer {
    private struct RenderTemplate: Decodable {
        let css: String
        let sectionTitles: [String: String]
        let fontStylesheet: String?
    }

    private static let fallbackTemplate = RenderTemplate(
        css: """
        * { margin: 0; padding: 0; box-sizing: border-box; }
        @page { size: letter; margin: 0; }
        html, body { width: 612pt; }
        body {
          font-family: "Computer Modern Serif", "CMU Serif", "Latin Modern Roman", "TeX Gyre Termes", "Times New Roman", "Times", "serif";
          font-size: 10.95pt;
          line-height: 1.2;
          color: black;
          margin: 0;
          padding: 36pt;
          font-display: swap;
        }
        .font-loading {
          font-family: "Computer Modern Serif", "CMU Serif", "Latin Modern Roman", "TeX Gyre Termes", "Times New Roman", "Times", "serif";
        }
        .header { text-align: center; margin-bottom: 1pt; }
        .name { font-size: 24.88pt; font-weight: bold; font-variant: small-caps; text-transform: none; line-height: 1; margin-bottom: 1pt; }
        .contact { font-size: 10pt; color: black; }
        .contact a { color: black; text-decoration: underline; }
        .contact-sep { margin: 0 3pt; }
        .section { margin-bottom: 0; margin-top: -4pt; }
        .section-title {
          font-size: 12pt;
          font-variant: small-caps;
          text-transform: none;
          letter-spacing: 0;
          font-weight: normal;
          margin-bottom: 0;
          border-bottom: 0.6pt solid black;
          padding-bottom: 0;
          line-height: 1;
        }
        .section-content { margin-left: 0; padding-top: -5pt; }
        .subheading-list { list-style: none; padding-left: 10.8pt; margin: 0; }
        .experience-entry, .basic-entry {
          break-inside: avoid;
          page-break-inside: avoid;
          margin-top: -2pt;
          margin-bottom: 0;
        }
        .entry { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 0; }
        .entry-main { font-weight: bold; font-size: 10.95pt; }
        .entry-date { font-weight: normal; font-size: 10.95pt; }
        .entry-sub { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 0; font-style: italic; font-size: 10pt; }
        .entry-location { font-weight: normal; font-style: italic; font-size: 10pt; }
        .item-list { margin-left: 18pt; margin-top: -7pt; margin-bottom: 0; padding-left: 0; }
        .item-list li { margin-bottom: -2pt; font-size: 10pt; line-height: 1.2; }
        .item-list li::marker { font-size: 6pt; }
        .project-entry { break-inside: avoid; page-break-inside: avoid; margin-top: 0; margin-bottom: 0; }
        .project-header { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 0; font-size: 10pt; }
        .project-name { font-weight: bold; }
        .project-name a { color: black; text-decoration: underline; }
        .project-tech { font-style: italic; }
        .project-date { font-size: 10.95pt; }
        .summary-text { margin-left: 0; font-size: 10pt; line-height: 1.3; text-align: justify; }
        .skills-list { list-style: none; padding-left: 10.8pt; margin: 0; }
        .skill-category { font-weight: bold; }
        .skill-line { margin-bottom: 0; font-size: 10pt; line-height: 1.3; }
        @media print {
          body { padding: 36pt; margin: 0; }
        }
        """,
        sectionTitles: [
            "summary": "Summary",
            "experience": "Experience",
            "projects": "Projects",
            "skills": "Technical Skills",
            "education": "Education"
        ],
        fontStylesheet: "ResumeFonts/ResumeFonts.css"
    )

    static func renderHTML(from rawJSON: String) throws -> String {
        let validated = try ResumeSchemaValidator.validate(jsonText: rawJSON)
        let resume = validated.schema
        let template = loadTemplate()
        let fontHeadBlock = buildFontHeadBlock(stylesheetURL: template.fontStylesheet)

        var html = """
        <!DOCTYPE html>
        <html lang=\"en\">
        <head>
        <meta charset=\"UTF-8\" />
        <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />
        <title>\(escapeHTML(resume.name)) - Resume</title>
        \(fontHeadBlock)
        <style>\(template.css)</style>
        </head>
        <body>
        \(header(for: resume))
        \(summary(for: resume, title: template.sectionTitles["summary"] ?? "Summary"))
        \(experience(for: resume, title: template.sectionTitles["experience"] ?? "Experience"))
        \(projects(for: resume, title: template.sectionTitles["projects"] ?? "Projects"))
        \(skills(for: resume, title: template.sectionTitles["skills"] ?? "Technical Skills"))
        \(education(for: resume, title: template.sectionTitles["education"] ?? "Education"))
        </body>
        </html>
        """

        html = html.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        return html
    }

    private static func header(for resume: ResumeSchema) -> String {
        let contact = resume.contact
        var parts: [String] = []
        if !contact.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(escapeHTML(contact.phone))
        }
        if !contact.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("<a href=\"mailto:\(escapeHTML(contact.email))\">\(escapeHTML(contact.email))</a>")
        }
        if !contact.linkedin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let linkedinURL = normalizeExternalURL(contact.linkedin)
            parts.append("<a href=\"\(escapeHTML(linkedinURL))\">\(escapeHTML(contact.linkedin))</a>")
        }
        if !contact.github.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let githubURL = normalizeExternalURL(contact.github)
            parts.append("<a href=\"\(escapeHTML(githubURL))\">\(escapeHTML(contact.github))</a>")
        }

        let separator = "<span class=\"contact-sep\">|</span>"
        return """
        <div class=\"header\">
          <div class=\"name\">\(escapeHTML(resume.name))</div>
          <div class=\"contact\">\(parts.joined(separator: " \(separator) "))</div>
        </div>
        """
    }

    private static func summary(for resume: ResumeSchema, title: String) -> String {
        guard let summary = resume.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        return """
        <div class=\"section\">
          <div class=\"section-title\">\(title)</div>
          <div class=\"section-content\">
            <div class=\"summary-text\">\(escapeHTML(summary))</div>
          </div>
        </div>
        """
    }

    private static func education(for resume: ResumeSchema, title: String) -> String {
        let entries = resume.education.map { item in
            """
            <div class=\"basic-entry\">
              <div class=\"entry\"><div class=\"entry-main\">\(escapeHTML(item.university))</div><div class=\"entry-location\">\(escapeHTML(item.location))</div></div>
              <div class=\"entry-sub\"><div>\(escapeHTML(item.degree))</div><div>\(escapeHTML(item.date))</div></div>
            </div>
            """
        }
        return section(title: title, content: "<div class=\"subheading-list\">\(entries.joined(separator: "\n"))</div>")
    }

    private static func experience(for resume: ResumeSchema, title: String) -> String {
        let entries = resume.experience.map { item in
            let bullets = item.responsibilities
                .map { "<li>\(escapeHTML($0))</li>" }
                .joined(separator: "")

            return """
            <div class=\"experience-entry\">
              <div class=\"entry\"><div class=\"entry-main\">\(escapeHTML(item.title))</div><div class=\"entry-date\">\(escapeHTML(item.dates))</div></div>
              <div class=\"entry-sub\"><div>\(escapeHTML(item.company))</div><div>\(escapeHTML(item.location))</div></div>
              <ul class=\"item-list\">\(bullets)</ul>
            </div>
            """
        }
        return section(title: title, content: "<div class=\"subheading-list\">\(entries.joined(separator: "\n"))</div>")
    }

    private static func projects(for resume: ResumeSchema, title: String) -> String {
        let entries = resume.projects.map { item in
            let bulletHTML = item.description.map { "<li>\(escapeHTML($0))</li>" }.joined(separator: "")
            let projectName: String
            if let url = item.url, !url.isEmpty {
                projectName = "<span class=\"project-name\"><a href=\"\(escapeHTML(url))\">\(escapeHTML(item.name))</a></span>"
            } else {
                projectName = "<span class=\"project-name\">\(escapeHTML(item.name))</span>"
            }
            let techStr = item.technologies.isEmpty ? "" : " <span class=\"contact-sep\">|</span> <span class=\"project-tech\">\(escapeHTML(item.technologies.joined(separator: ", ")))</span>"
            return """
            <div class=\"project-entry\">
              <div class=\"project-header\">
                <div>\(projectName)\(techStr)</div>
                <div class=\"project-date\">\(escapeHTML(item.date))</div>
              </div>
              <ul class=\"item-list\">\(bulletHTML)</ul>
            </div>
            """
        }
        return section(title: title, content: "<div class=\"subheading-list\">\(entries.joined(separator: "\n"))</div>")
    }

    private static func skills(for resume: ResumeSchema, title: String) -> String {
        let lines = resume.skills.keys.sorted().map { category -> String in
            let values = resume.skills[category] ?? []
            return "<div class=\"skill-line\"><span class=\"skill-category\">\(escapeHTML(category))</span>: \(escapeHTML(values.joined(separator: ", ")))</div>"
        }

        let content = """
        <div class=\"skills-list\">
          \(lines.joined(separator: "\n"))
        </div>
        """
        return section(title: title, content: content)
    }

    private static func section(title: String, content: String) -> String {
        """
        <div class=\"section\">
          <div class=\"section-title\">\(title)</div>
          <div class=\"section-content\">\(content)</div>
        </div>
        """
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func normalizeExternalURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    private static func buildFontHeadBlock(stylesheetURL: String?) -> String {
        guard let stylesheetURL, !stylesheetURL.isEmpty else {
            return ""
        }

        if stylesheetURL.hasPrefix("http://") || stylesheetURL.hasPrefix("https://") {
            return """
            <link rel=\"preconnect\" href=\"https://fonts.googleapis.com\" />
            <link rel=\"preconnect\" href=\"https://fonts.gstatic.com\" crossorigin />
            <link href=\"\(escapeHTML(stylesheetURL))\" rel=\"stylesheet\" />
            """
        }

        return """
        <link href=\"\(escapeHTML(stylesheetURL))\" rel=\"stylesheet\" />
        """
    }

    private static func loadTemplate() -> RenderTemplate {
        guard let url = Bundle.main.url(forResource: "ResumeTemplate", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let template = try? JSONDecoder().decode(RenderTemplate.self, from: data)
        else {
            return fallbackTemplate
        }
        return template
    }
}

enum ResumePDFExportService {
    // WKWebView uses points for PDF output; use true US Letter points.
    private static let pdfPageWidth: CGFloat = 612
    private static let minimumPDFPageHeight: CGFloat = 792

    @MainActor
    static func makeDocument(json: String) async throws -> ResumePDFFileDocument {
        let html = try ResumeHTMLRenderer.renderHTML(from: json)
        let data = try await renderPDFData(html: html)
        return ResumePDFFileDocument(data: data)
    }

    @MainActor
    private static func renderPDFData(html: String) async throws -> Data {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: pdfPageWidth, height: minimumPDFPageHeight))
        let delegate = WebViewLoadDelegate()
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: Bundle.main.resourceURL)

        try await delegate.awaitLoad()
        await adjustExperienceEntryBreaks(for: webView)
        let documentHeight = try await measuredDocumentHeight(for: webView)
        let exportHeight = max(documentHeight, minimumPDFPageHeight)

        let rawData: Data = try await withCheckedThrowingContinuation { continuation in
            let config = WKPDFConfiguration()
            // Capture full rendered content, then paginate into letter pages below.
            config.rect = CGRect(x: 0, y: 0, width: pdfPageWidth, height: exportHeight)
            webView.createPDF(configuration: config) { result in
                continuation.resume(with: result)
            }
        }

        return paginateIfNeeded(pdfData: rawData)
    }

    @MainActor
    private static func measuredDocumentHeight(for webView: WKWebView) async throws -> CGFloat {
        let script = """
        Math.max(
          document.body ? document.body.scrollHeight : 0,
          document.body ? document.body.offsetHeight : 0,
          document.documentElement ? document.documentElement.clientHeight : 0,
          document.documentElement ? document.documentElement.scrollHeight : 0,
          document.documentElement ? document.documentElement.offsetHeight : 0
        )
        """

        do {
            let value = try await evaluateJavaScript(script, in: webView)

            if let number = value as? NSNumber {
                return CGFloat(number.doubleValue)
            }
            if let value = value as? Double {
                return CGFloat(value)
            }
            if let value = value as? Int {
                return CGFloat(value)
            }
        } catch {
            // Fall through to native scroll size below.
        }

        return max(webView.bounds.height, minimumPDFPageHeight)
    }

    @MainActor
    private static func adjustExperienceEntryBreaks(for webView: WKWebView) async {
        let script = """
        (async () => {
          if (document.fonts && document.fonts.ready) {
            try { await document.fonts.ready; } catch (_) {}
          }

          const pageHeight = \(minimumPDFPageHeight);
          const overflowTolerance = 0.5;
          const entries = Array.from(document.querySelectorAll(".experience-entry, .project-entry, .basic-entry"));

          for (const entry of entries) {
            const computedMargin = parseFloat(window.getComputedStyle(entry).marginTop || "0");
            const baseMargin = Number.isFinite(computedMargin) ? computedMargin : 0;
            entry.style.marginTop = `${baseMargin}px`;
          }

          for (const entry of entries) {
            const rect = entry.getBoundingClientRect();
            const top = rect.top + window.scrollY;
            const height = rect.height;

            if (height >= pageHeight - overflowTolerance) {
              continue;
            }

            const nextBoundary = (Math.floor(top / pageHeight) + 1) * pageHeight;
            const overflow = (top + height) - nextBoundary;
            if (overflow <= overflowTolerance) {
              continue;
            }

            const shift = nextBoundary - top;
            if (shift > overflowTolerance) {
              const baseMargin = parseFloat(entry.style.marginTop || "0") || 0;
              entry.style.marginTop = `${baseMargin + shift}px`;
            }
          }

          return true;
        })()
        """

        _ = try? await evaluateJavaScript(script, in: webView)
    }

    @MainActor
    private static func evaluateJavaScript(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: result)
            }
        }
    }

    private static func paginateIfNeeded(pdfData: Data) -> Data {
        guard let provider = CGDataProvider(data: pdfData as CFData),
              let sourceDocument = CGPDFDocument(provider),
              sourceDocument.numberOfPages == 1,
              let sourcePage = sourceDocument.page(at: 1)
        else {
            return pdfData
        }

        let sourceRect = sourcePage.getBoxRect(.mediaBox)
        guard sourceRect.height > minimumPDFPageHeight + 0.5 else {
            return pdfData
        }

        let pageCount = Int(ceil(sourceRect.height / minimumPDFPageHeight))
        let outputData = NSMutableData()
        guard let consumer = CGDataConsumer(data: outputData as CFMutableData) else {
            return pdfData
        }

        var mediaBox = CGRect(x: 0, y: 0, width: pdfPageWidth, height: minimumPDFPageHeight)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return pdfData
        }

        // Split from top-to-bottom so page 1 keeps the visual start of the resume.
        for index in 0..<pageCount {
            context.beginPDFPage(nil)
            context.saveGState()

            let sliceTop = sourceRect.height - CGFloat(index) * minimumPDFPageHeight
            let sliceBottom = max(0, sliceTop - minimumPDFPageHeight)
            context.translateBy(x: 0, y: -sliceBottom)
            context.drawPDFPage(sourcePage)

            context.restoreGState()
            context.endPDFPage()
        }

        context.closePDF()
        return outputData as Data
    }
}

@MainActor
private final class WebViewLoadDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func awaitLoad() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume(returning: ())
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
