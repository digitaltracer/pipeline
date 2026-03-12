import SwiftUI

#if os(macOS)
import AppKit
#endif

struct AppLockRootView<Content: View>: View {
    @Environment(AppLockCoordinator.self) private var appLockCoordinator
    @Environment(\.scenePhase) private var scenePhase

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            protectedContent

            if appLockCoordinator.shouldObscureContent {
                AppLockOverlayView()
                    .transition(.opacity)
            }
        }
        .task {
            await appLockCoordinator.authenticateIfNeeded()
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appLockCoordinator.handleAppDidBecomeActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            appLockCoordinator.handleAppWillResignActive()
        }
        #else
        .onChange(of: scenePhase) { _, newPhase in
            appLockCoordinator.handleProtectedScenePhase(newPhase)
        }
        #endif
    }

    @ViewBuilder
    private var protectedContent: some View {
        if appLockCoordinator.shouldObscureContent {
            content
                .privacySensitive()
                .allowsHitTesting(false)
                .hidden()
        } else {
            content
                .privacySensitive()
        }
    }
}

private struct AppLockOverlayView: View {
    @Environment(AppLockCoordinator.self) private var appLockCoordinator
    @Environment(\.colorScheme) private var colorScheme

    private var iconName: String {
        let description = appLockCoordinator.availability.mechanismDescription.lowercased()
        if description.contains("face id") {
            return "faceid"
        }
        if description.contains("touch id") {
            return "touchid"
        }
        return "lock.fill"
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.contentBackground(colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: iconName)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .frame(width: 72, height: 72)
                    .background(
                        Circle()
                            .fill(DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.18 : 0.10))
                    )

                VStack(spacing: 8) {
                    Text("Pipeline Is Locked")
                        .font(.title2.weight(.semibold))

                    Text("Unlock to view your job search data.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text(appLockCoordinator.availability.supportSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let errorMessage = appLockCoordinator.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button {
                    Task {
                        await appLockCoordinator.authenticateIfNeeded()
                    }
                } label: {
                    if appLockCoordinator.isAuthenticating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Unlock Pipeline", systemImage: iconName)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(DesignSystem.Colors.accent)
                .disabled(appLockCoordinator.isAuthenticating || !appLockCoordinator.availability.isAvailable)
                .frame(maxWidth: 280)
            }
            .padding(32)
            .frame(maxWidth: 420)
            .appCard(cornerRadius: 24, elevated: true, shadow: false)
            .padding(24)
        }
    }
}
