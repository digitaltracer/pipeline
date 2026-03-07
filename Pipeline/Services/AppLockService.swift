import Foundation
import LocalAuthentication

struct AppLockAvailability: Equatable {
    let isAvailable: Bool
    let mechanismDescription: String
    let unavailableReason: String?

    var supportSummary: String {
        if isAvailable {
            return "Uses \(mechanismDescription) to unlock Pipeline."
        }
        return unavailableReason ?? "This device cannot authenticate to protect Pipeline."
    }
}

protocol AppLockService {
    func availability() -> AppLockAvailability
    func authenticate(reason: String) async throws
}

enum AppLockServiceError: LocalizedError {
    case unavailable(String)
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        case .cancelled:
            return "Authentication was cancelled. Pipeline remains unlocked."
        case .failed(let message):
            return message
        }
    }
}

final class LocalAuthenticationAppLockService: AppLockService {
    func availability() -> AppLockAvailability {
        let context = makeContext()
        var error: NSError?
        let isAvailable = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)

        return AppLockAvailability(
            isAvailable: isAvailable,
            mechanismDescription: mechanismDescription(for: context.biometryType),
            unavailableReason: unavailableReason(from: error)
        )
    }

    func authenticate(reason: String) async throws {
        let context = makeContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw AppLockServiceError.unavailable(
                unavailableReason(from: error) ?? "This device cannot authenticate to protect Pipeline."
            )
        }

        do {
            let didAuthenticate = try await evaluatePolicy(with: context, reason: reason)
            if !didAuthenticate {
                throw AppLockServiceError.cancelled
            }
        } catch let authError as AppLockServiceError {
            throw authError
        } catch let authError as LAError {
            throw mappedError(from: authError)
        } catch {
            throw AppLockServiceError.failed(error.localizedDescription)
        }
    }

    private func evaluatePolicy(with context: LAContext, reason: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: success)
            }
        }
    }

    private func makeContext() -> LAContext {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        return context
    }

    private func mechanismDescription(for biometryType: LABiometryType) -> String {
        switch biometryType {
        case .faceID:
            return "Face ID or device passcode"
        case .touchID:
            return "Touch ID or device passcode"
        #if os(iOS)
        case .opticID:
            return "Optic ID or device passcode"
        #endif
        case .none:
            return "device passcode"
        default:
            return "device authentication"
        }
    }

    private func unavailableReason(from error: NSError?) -> String? {
        guard let error else { return nil }

        if let authError = error as? LAError {
            switch authError.code {
            case .passcodeNotSet:
                return "Set a device passcode before you enable app lock."
            case .biometryNotEnrolled:
                return "Set up Face ID or Touch ID, or use a device passcode, before you enable app lock."
            case .biometryNotAvailable:
                return "This device does not support Face ID or Touch ID, and no device passcode is available."
            default:
                return authError.localizedDescription
            }
        }

        return error.localizedDescription
    }

    private func mappedError(from error: LAError) -> AppLockServiceError {
        switch error.code {
        case .userCancel, .appCancel, .systemCancel:
            return .cancelled
        case .passcodeNotSet:
            return .unavailable("Set a device passcode before you enable app lock.")
        case .biometryNotEnrolled:
            return .unavailable("Set up Face ID or Touch ID, or use a device passcode, before you enable app lock.")
        case .biometryNotAvailable:
            return .unavailable("This device does not support Face ID or Touch ID, and no device passcode is available.")
        default:
            return .failed(error.localizedDescription)
        }
    }
}
