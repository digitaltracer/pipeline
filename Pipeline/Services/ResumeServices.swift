import Foundation
import SwiftUI
import UniformTypeIdentifiers
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

// MARK: - LaTeX Renderer

enum ResumeTeXRenderer {
    enum TeXError: LocalizedError {
        case templateNotFound
        case markerNotFound

        var errorDescription: String? {
            switch self {
            case .templateNotFound:
                return "ResumeTemplate.tex not found in app bundle."
            case .markerNotFound:
                return "ResumeTemplate.tex is missing the %%PIPELINE_BODY%% marker."
            }
        }
    }

    static func renderTeX(from rawJSON: String) throws -> String {
        let validated = try ResumeSchemaValidator.validate(jsonText: rawJSON)
        let resume = validated.schema

        guard let templateURL = Bundle.main.url(forResource: "ResumeTemplate", withExtension: "tex"),
              let templateString = try? String(contentsOf: templateURL, encoding: .utf8)
        else {
            throw TeXError.templateNotFound
        }

        guard templateString.contains("%%PIPELINE_BODY%%") else {
            throw TeXError.markerNotFound
        }

        var body = ""
        body += header(for: resume)
        body += summary(for: resume)
        body += experience(for: resume)
        body += projects(for: resume)
        body += skills(for: resume)
        body += education(for: resume)

        return templateString.replacingOccurrences(of: "%%PIPELINE_BODY%%", with: body)
    }

    // MARK: - Section Generators

    private static func header(for resume: ResumeSchema) -> String {
        let contact = resume.contact
        var parts: [String] = []

        if !contact.phone.trimmedEmpty {
            parts.append(escapeLaTeX(contact.phone))
        }
        if !contact.email.trimmedEmpty {
            parts.append("\\href{mailto:\(escapeURL(contact.email))}{\\underline{\(escapeLaTeX(contact.email))}}")
        }
        if !contact.linkedin.trimmedEmpty {
            let url = normalizeExternalURL(contact.linkedin)
            parts.append("\\href{\(escapeURL(url))}{\\underline{\(escapeLaTeX(contact.linkedin))}}")
        }
        if !contact.github.trimmedEmpty {
            let url = normalizeExternalURL(contact.github)
            parts.append("\\href{\(escapeURL(url))}{\\underline{\(escapeLaTeX(contact.github))}}")
        }

        let contactLine = parts.joined(separator: " $|$ ")

        return """
        \\begin{center}
            \\textbf{\\Huge \\scshape \(escapeLaTeX(resume.name))} \\\\ \\vspace{1pt}
            \\small \(contactLine)
        \\end{center}

        """
    }

    private static func education(for resume: ResumeSchema) -> String {
        guard !resume.education.isEmpty else { return "" }

        var tex = """
        \\section{Education}
          \\resumeSubHeadingListStart

        """

        for entry in resume.education {
            tex += """
                \\resumeEducationNeedSpace
                \\resumeSubheading
                  {\(escapeLaTeX(entry.university))}{\(escapeLaTeX(entry.location))}
                  {\(escapeLaTeX(entry.degree))}{\(escapeLaTeX(entry.date))}

            """
        }

        tex += """
          \\resumeSubHeadingListEnd

        """
        return tex
    }

    private static func experience(for resume: ResumeSchema) -> String {
        guard !resume.experience.isEmpty else { return "" }

        var tex = """
        \\section{Experience}
          \\resumeSubHeadingListStart

        """

        for entry in resume.experience {
            tex += """
                \\resumeEntryNeedSpace
                \\resumeSubheading
                  {\(escapeLaTeX(entry.title))}{\(escapeLaTeX(entry.dates))}
                  {\(escapeLaTeX(entry.company))}{\(escapeLaTeX(entry.location))}
                  \\resumeItemListStart

            """
            for bullet in entry.responsibilities {
                tex += "            \\resumeItem{\(escapeLaTeX(bullet))}\n"
            }
            tex += "          \\resumeItemListEnd\n\n"
        }

        tex += """
          \\resumeSubHeadingListEnd

        """
        return tex
    }

    private static func projects(for resume: ResumeSchema) -> String {
        guard !resume.projects.isEmpty else { return "" }

        var tex = """
        \\section{Projects}
          \\resumeSubHeadingListStart

        """

        for project in resume.projects {
            let projectName: String
            if let url = project.url, !url.isEmpty {
                projectName = "\\href{\(escapeURL(normalizeExternalURL(url)))}{\\underline{\\textbf{\(escapeLaTeX(project.name))}}}"
            } else {
                projectName = "\\textbf{\(escapeLaTeX(project.name))}"
            }

            let techStr = project.technologies.isEmpty
                ? ""
                : " $|$ \\emph{\(escapeLaTeX(project.technologies.joined(separator: ", ")))}"

            tex += """
                \\resumeProjectNeedSpace
                \\resumeProjectHeading
                  {\(projectName)\(techStr)}{\(escapeLaTeX(project.date))}
                  \\resumeItemListStart

            """
            for bullet in project.description {
                tex += "            \\resumeItem{\(escapeLaTeX(bullet))}\n"
            }
            tex += "          \\resumeItemListEnd\n\n"
        }

        tex += """
          \\resumeSubHeadingListEnd

        """
        return tex
    }

    private static func skills(for resume: ResumeSchema) -> String {
        guard !resume.skills.isEmpty else { return "" }

        var tex = """
        \\section{Technical Skills}
         \\begin{itemize}[leftmargin=0.15in, label={}]
            \\small{\\item{

        """

        let sortedKeys = resume.skills.keys.sorted()
        var skillsContent = ""
        for (index, category) in sortedKeys.enumerated() {
            let values = resume.skills[category] ?? []
            let separator = index < sortedKeys.count - 1 ? " \\\\ " : ""
            skillsContent += "\\textbf{\(escapeLaTeX(category))}{: \(escapeLaTeX(values.joined(separator: ", ")))}\(separator)"
        }

        tex += """
             \(skillsContent)
            }}
         \\end{itemize}

        """
        return tex
    }

    private static func summary(for resume: ResumeSchema) -> String {
        guard let summary = resume.summary,
              !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return ""
        }

        return """
        \\section{Summary}
         \\begin{itemize}[leftmargin=0.15in, label={}]
            \\small{\\item{
             \(escapeLaTeX(summary))
            }}
         \\end{itemize}

        """
    }

    // MARK: - Escaping

    static func escapeLaTeX(_ value: String) -> String {
        var result = value
        // Backslash must be first to avoid double-escaping
        result = result.replacingOccurrences(of: "\\", with: "\\textbackslash{}")
        result = result.replacingOccurrences(of: "{", with: "\\{")
        result = result.replacingOccurrences(of: "}", with: "\\}")
        result = result.replacingOccurrences(of: "$", with: "\\$")
        result = result.replacingOccurrences(of: "&", with: "\\&")
        result = result.replacingOccurrences(of: "#", with: "\\#")
        result = result.replacingOccurrences(of: "^", with: "\\^{}")
        result = result.replacingOccurrences(of: "_", with: "\\_")
        result = result.replacingOccurrences(of: "~", with: "\\~{}")
        result = result.replacingOccurrences(of: "%", with: "\\%")
        return result
    }

    private static func escapeURL(_ value: String) -> String {
        // URLs inside \href only need % and # escaped for LaTeX
        value
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "#", with: "\\#")
    }

    private static func normalizeExternalURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }
}

private extension String {
    var trimmedEmpty: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Tectonic PDF Compiler

#if os(macOS)
enum TectonicPDFCompiler {
    enum CompileError: LocalizedError {
        case tectonicNotFound
        case compilationFailed(String)
        case outputNotFound

        var errorDescription: String? {
            switch self {
            case .tectonicNotFound:
                return "Tectonic binary not found in app bundle."
            case .compilationFailed(let output):
                return "LaTeX compilation failed:\n\(output)"
            case .outputNotFound:
                return "Tectonic did not produce a PDF file."
            }
        }
    }

    static func compile(tex: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try compileSync(tex: tex)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func compileSync(tex: String) throws -> Data {
        guard let tectonicURL = Bundle.main.url(forResource: "tectonic", withExtension: nil) else {
            throw CompileError.tectonicNotFound
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipeline-tex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let texFile = tempDir.appendingPathComponent("resume.tex")
        try tex.write(to: texFile, atomically: true, encoding: .utf8)
        try stageResumeFonts(in: tempDir)

        let process = Process()
        process.executableURL = tectonicURL
        process.arguments = [texFile.path]
        process.currentDirectoryURL = tempDir

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw CompileError.compilationFailed(output)
        }

        let pdfFile = tempDir.appendingPathComponent("resume.pdf")
        guard FileManager.default.fileExists(atPath: pdfFile.path) else {
            throw CompileError.outputNotFound
        }

        return try Data(contentsOf: pdfFile)
    }

    private static func stageResumeFonts(in tempDir: URL) throws {
        guard let bundledFontsURL = Bundle.main.resourceURL?.appendingPathComponent("ResumeFonts"),
              FileManager.default.fileExists(atPath: bundledFontsURL.path)
        else {
            return
        }

        let destinationURL = tempDir.appendingPathComponent("ResumeFonts")
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: bundledFontsURL, to: destinationURL)
    }
}
#endif

// MARK: - PDF Export Service

enum ResumePDFExportService {
    @MainActor
    static func makeDocument(json: String) async throws -> ResumePDFFileDocument {
        #if os(macOS)
        let tex = try ResumeTeXRenderer.renderTeX(from: json)
        let data = try await TectonicPDFCompiler.compile(tex: tex)
        return ResumePDFFileDocument(data: data)
        #else
        throw NSError(
            domain: "com.pipeline.resume",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "PDF export is not available on iOS. Please use a Mac to export your resume as PDF."
            ]
        )
        #endif
    }
}
