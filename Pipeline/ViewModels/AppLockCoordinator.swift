import Observation
import SwiftUI

@MainActor
@Observable
final class AppLockCoordinator {
    private let settingsViewModel: SettingsViewModel
    @ObservationIgnored private let service: AppLockService

    private(set) var availability: AppLockAvailability
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    private(set) var errorMessage: String?
    private var shouldPromptOnNextActivation: Bool

    var appLockEnabled: Bool {
        settingsViewModel.appLockEnabled
    }

    var shouldObscureContent: Bool {
        appLockEnabled && isLocked
    }

    init(
        settingsViewModel: SettingsViewModel,
        service: AppLockService = LocalAuthenticationAppLockService()
    ) {
        self.settingsViewModel = settingsViewModel
        self.service = service
        self.availability = service.availability()
        self.isLocked = settingsViewModel.appLockEnabled
        self.shouldPromptOnNextActivation = settingsViewModel.appLockEnabled
    }

    func refreshAvailability() {
        availability = service.availability()
    }

    func setAppLockEnabled(_ isEnabled: Bool) async {
        refreshAvailability()
        errorMessage = nil

        if isEnabled {
            await enableAppLock()
        } else {
            settingsViewModel.appLockEnabled = false
            isLocked = false
            shouldPromptOnNextActivation = false
        }
    }

    func authenticateIfNeeded() async {
        guard appLockEnabled else {
            isLocked = false
            shouldPromptOnNextActivation = false
            return
        }

        guard (isLocked || shouldPromptOnNextActivation), !isAuthenticating else {
            return
        }

        refreshAvailability()
        guard availability.isAvailable else {
            settingsViewModel.appLockEnabled = false
            isLocked = false
            shouldPromptOnNextActivation = false
            errorMessage = availability.unavailableReason
            return
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            try await service.authenticate(reason: "Unlock Pipeline to view your job search data.")
            isLocked = false
            shouldPromptOnNextActivation = false
            errorMessage = nil
        } catch let error as AppLockServiceError {
            isLocked = true
            shouldPromptOnNextActivation = true
            errorMessage = lockErrorMessage(for: error, enabling: false)
        } catch {
            isLocked = true
            shouldPromptOnNextActivation = true
            errorMessage = error.localizedDescription
        }
    }

    func handleProtectedScenePhase(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            Task {
                await authenticateIfNeeded()
            }
        case .inactive, .background:
            lockIfNeeded()
        @unknown default:
            break
        }
    }

    func handleAppDidBecomeActive() {
        Task {
            await authenticateIfNeeded()
        }
    }

    func handleAppWillResignActive() {
        lockIfNeeded()
    }

    func dismissError() {
        errorMessage = nil
    }

    private func enableAppLock() async {
        guard availability.isAvailable else {
            settingsViewModel.appLockEnabled = false
            isLocked = false
            shouldPromptOnNextActivation = false
            errorMessage = availability.unavailableReason
            return
        }

        isLocked = true
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            try await service.authenticate(reason: "Authenticate to enable app lock for Pipeline.")
            settingsViewModel.appLockEnabled = true
            isLocked = false
            shouldPromptOnNextActivation = false
            errorMessage = nil
        } catch let error as AppLockServiceError {
            settingsViewModel.appLockEnabled = false
            isLocked = false
            shouldPromptOnNextActivation = false
            errorMessage = lockErrorMessage(for: error, enabling: true)
        } catch {
            settingsViewModel.appLockEnabled = false
            isLocked = false
            shouldPromptOnNextActivation = false
            errorMessage = error.localizedDescription
        }
    }

    private func lockIfNeeded() {
        guard appLockEnabled else { return }
        isLocked = true
        shouldPromptOnNextActivation = true
        errorMessage = nil
    }

    private func lockErrorMessage(for error: AppLockServiceError, enabling: Bool) -> String? {
        switch error {
        case .cancelled:
            return enabling
                ? "Pipeline stayed unlocked because authentication was cancelled."
                : "Pipeline remains locked until you authenticate."
        case .unavailable(let message), .failed(let message):
            return message
        }
    }
}
