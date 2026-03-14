import SwiftUI

struct OnboardingCardAction: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    let action: OnboardingAction
    var isProminent = false
}

struct OnboardingChecklistCard: View {
    let title: String
    let progress: OnboardingProgress
    let onAction: (OnboardingAction) -> Void
    var onMute: (() -> Void)? = nil
    var includeOptional = true
    var showsReplayAction = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.88 : 1.0),
                                    Color.green.opacity(colorScheme == .dark ? 0.55 : 0.78)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: "checklist.checked")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(progress.summary)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(progress.progressLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.18 : 0.10))
                    )
            }

            VStack(spacing: 10) {
                ForEach(progress.requiredItems) { item in
                    checklistRow(item)
                }

                if includeOptional {
                    ForEach(progress.optionalItems) { item in
                        checklistRow(item)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    onAction(progress.nextRecommendedAction)
                } label: {
                    Label(primaryActionTitle, systemImage: primaryActionIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)

                if showsReplayAction {
                    Button {
                        onAction(.replayTour)
                    } label: {
                        Label("Replay Tour", systemImage: "play.rectangle")
                    }
                    .buttonStyle(.bordered)
                }

                if let onMute {
                    Button("Hide Guidance", action: onMute)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            DesignSystem.Colors.surfaceElevated(colorScheme),
                            DesignSystem.Colors.surface(colorScheme)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }

    private func checklistRow(_ item: OnboardingChecklistItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.isComplete ? "checkmark.circle.fill" : (item.isRequired ? "circle.dotted" : "sparkles"))
                .foregroundColor(item.isComplete ? .green : DesignSystem.Colors.accent)
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))

                    if !item.isRequired {
                        Text("Optional")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                    }
                }

                Text(item.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            if !item.isComplete {
                Button(actionTitle(for: item.action)) {
                    onAction(item.action)
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DesignSystem.Colors.surface(colorScheme).opacity(colorScheme == .dark ? 0.78 : 0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }

    private var primaryActionTitle: String {
        actionTitle(for: progress.nextRecommendedAction)
    }

    private var primaryActionIcon: String {
        switch progress.nextRecommendedAction {
        case .addApplication:
            return "plus.circle.fill"
        case .openAISettings:
            return "brain.head.profile"
        case .openResumeWorkspace:
            return "doc.badge.plus"
        case .openIntegrations:
            return "puzzlepiece.extension"
        case .openDashboard:
            return "chart.bar.xaxis"
        case .replayTour:
            return "play.rectangle"
        }
    }

    private func actionTitle(for action: OnboardingAction) -> String {
        switch action {
        case .addApplication:
            return "Add Application"
        case .openAISettings:
            return "Open AI Settings"
        case .openResumeWorkspace:
            return "Open Resume"
        case .openIntegrations:
            return "Review Integrations"
        case .openDashboard:
            return "Open Dashboard"
        case .replayTour:
            return "Replay Tour"
        }
    }
}

struct OnboardingFeatureCalloutCard: View {
    let title: String
    let message: String
    let icon: String
    let actions: [OnboardingCardAction]
    let onAction: (OnboardingAction) -> Void
    var onMute: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.20 : 0.12))

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.accent)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 10) {
                ForEach(actions) { item in
                    if item.isProminent {
                        Button {
                            onAction(item.action)
                        } label: {
                            Label(item.title, systemImage: item.systemImage)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accent)
                    } else {
                        Button {
                            onAction(item.action)
                        } label: {
                            Label(item.title, systemImage: item.systemImage)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let onMute {
                    Button("Hide Guidance", action: onMute)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }
}

#Preview {
    OnboardingChecklistCard(
        title: "Finish Setup",
        progress: .preview,
        onAction: { _ in }
    )
    .padding()
    .background(DesignSystem.Colors.contentBackground(.light))
}
