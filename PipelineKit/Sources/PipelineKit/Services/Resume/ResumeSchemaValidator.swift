import Foundation

public struct ResumeSchemaValidationResult: Sendable {
    public let schema: ResumeSchema
    public let normalizedJSON: String
    public let unknownFieldPaths: [String]

    public init(schema: ResumeSchema, normalizedJSON: String, unknownFieldPaths: [String]) {
        self.schema = schema
        self.normalizedJSON = normalizedJSON
        self.unknownFieldPaths = unknownFieldPaths
    }
}

public enum ResumeSchemaValidationError: LocalizedError {
    case emptyInput
    case invalidJSON
    case schemaMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Resume JSON is empty."
        case .invalidJSON:
            return "Resume JSON is not valid JSON."
        case .schemaMismatch(let message):
            return message
        }
    }
}

public enum ResumeSchemaValidator {
    private static let renderedRootKeys: Set<String> = [
        "name", "contact", "education", "summary", "experience", "projects", "skills"
    ]

    public static func validate(jsonText: String) throws -> ResumeSchemaValidationResult {
        let trimmed = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ResumeSchemaValidationError.emptyInput
        }

        guard let rawData = trimmed.data(using: .utf8),
              let rawObject = try? JSONSerialization.jsonObject(with: rawData),
              let root = rawObject as? [String: Any]
        else {
            throw ResumeSchemaValidationError.invalidJSON
        }

        let decoder = JSONDecoder()
        let schema: ResumeSchema
        do {
            schema = try decoder.decode(ResumeSchema.self, from: rawData)
        } catch {
            throw ResumeSchemaValidationError.schemaMismatch(
                "Resume JSON does not match required schema: \(error.localizedDescription)"
            )
        }

        let semanticErrors = validateSemantics(schema)
        if !semanticErrors.isEmpty {
            throw ResumeSchemaValidationError.schemaMismatch(semanticErrors.joined(separator: " "))
        }

        let unknownFieldPaths = collectUnknownFieldPaths(in: root)

        guard JSONSerialization.isValidJSONObject(root),
              let normalizedData = try? JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let normalizedJSON = String(data: normalizedData, encoding: .utf8)
        else {
            throw ResumeSchemaValidationError.invalidJSON
        }

        return ResumeSchemaValidationResult(
            schema: schema,
            normalizedJSON: normalizedJSON,
            unknownFieldPaths: unknownFieldPaths
        )
    }

    private static func validateSemantics(_ schema: ResumeSchema) -> [String] {
        var errors: [String] = []

        if schema.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("`name` cannot be empty.")
        }

        if schema.contact.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("`contact.email` cannot be empty.")
        }

        if schema.education.isEmpty {
            errors.append("`education` must contain at least one entry.")
        }

        if schema.experience.isEmpty {
            errors.append("`experience` must contain at least one entry.")
        }

        if schema.projects.isEmpty {
            errors.append("`projects` must contain at least one entry.")
        }

        if schema.skills.isEmpty {
            errors.append("`skills` must contain at least one category.")
        }

        return errors
    }

    private static func collectUnknownFieldPaths(in root: [String: Any]) -> [String] {
        var unknowns = Set<String>()
        walk(value: root, path: [], unknowns: &unknowns)
        return unknowns.sorted()
    }

    private static func walk(value: Any, path: [String], unknowns: inout Set<String>) {
        if !path.isEmpty, !isRenderedPath(path) {
            unknowns.insert(pointer(path))
        }

        if let object = value as? [String: Any] {
            for key in object.keys.sorted() {
                if path.isEmpty, !renderedRootKeys.contains(key) {
                    unknowns.insert(pointer([key]))
                }
                walk(value: object[key] as Any, path: path + [key], unknowns: &unknowns)
            }
            return
        }

        if let array = value as? [Any] {
            for (index, nested) in array.enumerated() {
                walk(value: nested, path: path + ["\(index)"], unknowns: &unknowns)
            }
        }
    }

    private static func pointer(_ components: [String]) -> String {
        "/" + components
            .map { $0.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1") }
            .joined(separator: "/")
    }

    private static func isRenderedPath(_ components: [String]) -> Bool {
        guard let root = components.first else { return false }

        switch root {
        case "name", "summary":
            return components.count == 1
        case "contact":
            guard components.count <= 2 else { return false }
            if components.count == 1 { return true }
            return ["phone", "email", "linkedin", "github"].contains(components[1])
        case "education":
            guard components.count >= 1 else { return false }
            if components.count == 1 { return true }
            guard components.count >= 2, Int(components[1]) != nil else { return false }
            if components.count == 2 { return true }
            return ["university", "location", "degree", "date"].contains(components[2]) && components.count == 3
        case "experience":
            if components.count == 1 { return true }
            guard components.count >= 2, Int(components[1]) != nil else { return false }
            if components.count == 2 { return true }
            if ["title", "company", "location", "dates"].contains(components[2]) {
                return components.count == 3
            }
            if components[2] == "responsibilities" {
                if components.count == 3 { return true }
                return components.count == 4 && Int(components[3]) != nil
            }
            return false
        case "projects":
            if components.count == 1 { return true }
            guard components.count >= 2, Int(components[1]) != nil else { return false }
            if components.count == 2 { return true }
            if ["name", "url", "date"].contains(components[2]) {
                return components.count == 3
            }
            if ["technologies", "description"].contains(components[2]) {
                if components.count == 3 { return true }
                return components.count == 4 && Int(components[3]) != nil
            }
            return false
        case "skills":
            if components.count == 1 { return true }
            if components.count == 2 { return true }
            return components.count == 3 && Int(components[2]) != nil
        default:
            return false
        }
    }
}
