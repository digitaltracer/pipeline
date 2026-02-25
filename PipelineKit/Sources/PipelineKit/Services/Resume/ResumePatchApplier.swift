import Foundation

public enum ResumePatchApplier {
    public static func apply(
        patches: [ResumePatch],
        acceptedPatchIDs: Set<UUID>,
        to rawJSON: String
    ) throws -> String {
        guard let rawData = rawJSON.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: rawData)
        else {
            throw AIServiceError.parsingError("Resume JSON is invalid.")
        }

        for patch in patches where acceptedPatchIDs.contains(patch.id) {
            object = try apply(patch: patch, to: object)
        }

        guard JSONSerialization.isValidJSONObject(object),
              let output = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let text = String(data: output, encoding: .utf8)
        else {
            throw AIServiceError.parsingError("Failed to serialize patched resume JSON.")
        }

        return text
    }

    private static func apply(patch: ResumePatch, to root: Any) throws -> Any {
        let tokens = tokens(from: patch.path)

        switch patch.operation {
        case .add:
            guard let afterValue = patch.afterValue?.foundationObject else {
                throw AIServiceError.parsingError("Patch add missing afterValue")
            }
            return try mutate(value: root, tokens: tokens, operation: .add, payload: afterValue)
        case .replace:
            guard let afterValue = patch.afterValue?.foundationObject else {
                throw AIServiceError.parsingError("Patch replace missing afterValue")
            }
            return try mutate(value: root, tokens: tokens, operation: .replace, payload: afterValue)
        case .remove:
            return try mutate(value: root, tokens: tokens, operation: .remove, payload: nil)
        }
    }

    private static func tokens(from pointer: String) -> [String] {
        pointer
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { token in
                token.replacingOccurrences(of: "~1", with: "/")
                    .replacingOccurrences(of: "~0", with: "~")
            }
    }

    private static func mutate(
        value: Any,
        tokens: [String],
        operation: ResumePatch.Operation,
        payload: Any?
    ) throws -> Any {
        guard let head = tokens.first else {
            switch operation {
            case .add, .replace:
                guard let payload else {
                    throw AIServiceError.parsingError("Missing payload for patch mutation.")
                }
                return payload
            case .remove:
                throw AIServiceError.parsingError("Cannot remove root value.")
            }
        }

        let tail = Array(tokens.dropFirst())

        if var object = value as? [String: Any] {
            if tail.isEmpty {
                switch operation {
                case .add, .replace:
                    guard let payload else {
                        throw AIServiceError.parsingError("Missing payload for object mutation.")
                    }
                    object[head] = payload
                case .remove:
                    guard object[head] != nil else {
                        throw AIServiceError.parsingError("Remove path does not exist.")
                    }
                    object.removeValue(forKey: head)
                }
                return object
            }

            guard let child = object[head] else {
                throw AIServiceError.parsingError("Patch path does not exist: /\(tokens.joined(separator: "/"))")
            }

            object[head] = try mutate(value: child, tokens: tail, operation: operation, payload: payload)
            return object
        }

        if var array = value as? [Any] {
            let index: Int
            if head == "-" {
                index = array.count
            } else if let parsed = Int(head) {
                index = parsed
            } else {
                throw AIServiceError.parsingError("Array path segment must be an integer or '-'.")
            }

            if tail.isEmpty {
                switch operation {
                case .add:
                    guard let payload else {
                        throw AIServiceError.parsingError("Missing payload for array add.")
                    }
                    if index == array.count {
                        array.append(payload)
                    } else if array.indices.contains(index) {
                        array.insert(payload, at: index)
                    } else {
                        throw AIServiceError.parsingError("Array add index out of bounds.")
                    }
                case .replace:
                    guard let payload else {
                        throw AIServiceError.parsingError("Missing payload for array replace.")
                    }
                    guard array.indices.contains(index) else {
                        throw AIServiceError.parsingError("Array replace index out of bounds.")
                    }
                    array[index] = payload
                case .remove:
                    guard array.indices.contains(index) else {
                        throw AIServiceError.parsingError("Array remove index out of bounds.")
                    }
                    array.remove(at: index)
                }

                return array
            }

            guard array.indices.contains(index) else {
                throw AIServiceError.parsingError("Array path index out of bounds.")
            }

            array[index] = try mutate(value: array[index], tokens: tail, operation: operation, payload: payload)
            return array
        }

        throw AIServiceError.parsingError("Patch path traverses a non-container JSON value.")
    }
}
