import Foundation

public struct ResumePatchRejection: Sendable {
    public let patch: ResumePatch
    public let reason: String

    public init(patch: ResumePatch, reason: String) {
        self.patch = patch
        self.reason = reason
    }
}

public struct ResumePatchValidationResult: Sendable {
    public let accepted: [ResumePatch]
    public let rejected: [ResumePatchRejection]

    public init(accepted: [ResumePatch], rejected: [ResumePatchRejection]) {
        self.accepted = accepted
        self.rejected = rejected
    }
}

public enum ResumePatchSafetyValidator {
    private static let allowedRootKeys: Set<String> = [
        "name", "contact", "education", "summary", "experience", "projects", "skills"
    ]

    public static func validate(
        patches: [ResumePatch],
        originalJSON: String
    ) throws -> ResumePatchValidationResult {
        guard let data = originalJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = try? JSONValue(foundationObject: object)
        else {
            throw AIServiceError.parsingError("Could not validate patches because resume JSON is invalid.")
        }

        var accepted: [ResumePatch] = []
        var rejected: [ResumePatchRejection] = []

        for patch in patches {
            if let rejectionReason = rejectionReason(for: patch, root: root) {
                rejected.append(ResumePatchRejection(patch: patch, reason: rejectionReason))
            } else {
                accepted.append(patch)
            }
        }

        return ResumePatchValidationResult(accepted: accepted, rejected: rejected)
    }

    private static func rejectionReason(for patch: ResumePatch, root: JSONValue) -> String? {
        guard patch.path.hasPrefix("/") else {
            return "Patch path is not a valid JSON pointer."
        }

        let pathTokens = tokens(from: patch.path)
        guard let rootToken = pathTokens.first, allowedRootKeys.contains(rootToken) else {
            return "Patch points to a non-resume path."
        }

        if (patch.operation == .add || patch.operation == .replace), patch.afterValue == nil {
            return "Add/replace patch must include afterValue."
        }

        if patch.operation == .remove && patch.beforeValue == nil {
            return "Remove patch must include beforeValue."
        }

        switch patch.operation {
        case .replace, .remove:
            guard pathExists(pathTokens, in: root) else {
                return "Patch points to a path that does not exist in the resume."
            }
        case .add:
            guard parentExists(pathTokens, in: root) else {
                return "Patch add target has no valid parent path in the resume."
            }
        }

        if pathTokens.first == "skills" {
            if patch.operation == .add || patch.operation == .replace {
                guard !patch.evidencePaths.isEmpty else {
                    return "Skill changes require evidencePaths from existing resume content."
                }

                let hasAllowedEvidence = patch.evidencePaths.contains { evidencePath in
                    evidencePath.hasPrefix("/experience/") || evidencePath.hasPrefix("/projects/") || evidencePath == "/summary"
                }
                guard hasAllowedEvidence else {
                    return "Skill change evidence must reference experience, projects, or summary."
                }

                let evidenceAllExist = patch.evidencePaths.allSatisfy { evidencePath in
                    pathExists(tokens(from: evidencePath), in: root)
                }
                guard evidenceAllExist else {
                    return "Skill change evidencePaths include non-existing resume paths."
                }
            }
        }

        return nil
    }

    private static func tokens(from pointer: String) -> [String] {
        pointer
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { token in
                token.replacingOccurrences(of: "~1", with: "/")
                    .replacingOccurrences(of: "~0", with: "~")
            }
    }

    private static func parentExists(_ tokens: [String], in value: JSONValue) -> Bool {
        guard !tokens.isEmpty else { return false }
        return pathExists(Array(tokens.dropLast()), in: value)
    }

    private static func pathExists(_ tokens: [String], in value: JSONValue) -> Bool {
        guard !tokens.isEmpty else { return true }

        var current = value
        for token in tokens {
            switch current {
            case .object(let object):
                guard let nested = object[token] else { return false }
                current = nested
            case .array(let array):
                if token == "-" {
                    return true
                }
                guard let index = Int(token), array.indices.contains(index) else {
                    return false
                }
                current = array[index]
            default:
                return false
            }
        }

        return true
    }
}
