import SwiftUI

struct OnboardingFlowView: View {
    let progress: OnboardingProgress
    let onAction: (OnboardingAction) -> Void
    let onComplete: () -> Void
    let onSkip: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedStep: OnboardingStep = .welcome

    private let steps = OnboardingStep.allCases

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(DesignSystem.Colors.divider(colorScheme))

            Group {
                switch selectedStep {
                case .welcome:
                    welcomeStep
                case .pipeline:
                    pipelineStep
                case .focus:
                    focusStep
                case .ai:
                    aiStep
                case .launch:
                    launchStep
                }
            }

            Divider()
                .overlay(DesignSystem.Colors.divider(colorScheme))

            footer
        }
        .frame(maxWidth: 1120, maxHeight: 760)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
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
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 30, y: 18)
        .padding(24)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(selectedStep.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text(selectedStep.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(steps) { step in
                    Capsule(style: .continuous)
                        .fill(step == selectedStep ? DesignSystem.Colors.accent : Color.secondary.opacity(0.18))
                        .frame(width: step == selectedStep ? 28 : 10, height: 10)
                }
            }

            Button("Skip Tour", action: onSkip)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Back") {
                move(-1)
            }
            .buttonStyle(.bordered)
            .disabled(selectedStep == steps.first)

            Spacer()

            if selectedStep == .launch {
                Button("Finish Tour", action: onComplete)
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accent)
            } else {
                Button("Next") {
                    move(1)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Pipeline is built for a real job search, not a demo checklist.")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    Text("Use one workspace to capture jobs, prioritize where to spend time, tailor resumes, and keep momentum visible without juggling tabs and spreadsheets.")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: 540, alignment: .leading)

                    HStack(spacing: 12) {
                        introMetric(title: "Capture", subtitle: "Applications, contacts, timelines")
                        introMetric(title: "Focus", subtitle: "Dashboard, kanban, follow-ups")
                        introMetric(title: "Tailor", subtitle: "AI parse, ATS, resume revisions")
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(OnboardingDemoData.metrics) { metric in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.title)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            Text(metric.value)
                                .font(.title.weight(.bold))
                            Text(metric.change)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(DesignSystem.Colors.accent)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(DesignSystem.Colors.surface(colorScheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
                        )
                    }
                }
                .frame(width: 280)
            }

            Spacer()
        }
        .padding(28)
    }

    private var pipelineStep: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Every application becomes a structured record.")
                    .font(.title.weight(.bold))

                Text("Start with manual entry or AI parse. Once a job is in the system, Pipeline can track status changes, reminders, match scoring, and notes around a single source of truth.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(spacing: 12) {
                    ForEach(OnboardingDemoData.applications) { application in
                        demoApplicationCard(application)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                demoPanelTitle("What gets better immediately")

                bullet("Grid and detail views stay in sync around one application record.")
                bullet("Status changes feed kanban, dashboards, and follow-up workflows.")
                bullet("You can start small. One real application is enough to light up the workspace.")

                Spacer()
            }
            .frame(width: 320, alignment: .topLeading)
        }
        .padding(28)
    }

    private var focusStep: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Move between list, kanban, and executive overview without re-entering data.")
                    .font(.title.weight(.bold))

                Text("The same application pipeline powers visual status lanes, cadence tracking, goal progress, and follow-up prioritization.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(alignment: .top, spacing: 12) {
                    ForEach(OnboardingDemoData.kanbanColumns) { column in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(column.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(column.count)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }

                            ForEach(column.companies, id: \.self) { company in
                                Text(company)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(DesignSystem.Colors.surface(colorScheme))
                                    )
                            }

                            Spacer()
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
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
            }

            VStack(alignment: .leading, spacing: 14) {
                demoPanelTitle("Dashboard highlights")

                ForEach(OnboardingDemoData.metrics) { metric in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(metric.title)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(metric.value)
                                .font(.headline.weight(.semibold))
                        }

                        Spacer()

                        Text(metric.change)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.green)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(DesignSystem.Colors.surface(colorScheme))
                    )
                }

                Spacer()
            }
            .frame(width: 300, alignment: .topLeading)
        }
        .padding(28)
    }

    private var aiStep: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("AI features stay reviewable and optional.")
                    .font(.title.weight(.bold))

                Text("Configure a provider once, then use AI to extract job fields, tailor your resume, and support high-stakes comparisons without turning the workspace into a black box.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Text(OnboardingDemoData.sampleParseURL)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(DesignSystem.Colors.surface(colorScheme))
                        )

                    ForEach(OnboardingDemoData.sampleParseFields, id: \.label) { field in
                        HStack {
                            Text(field.label)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Text(field.value)
                                .font(.subheadline)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(DesignSystem.Colors.surface(colorScheme).opacity(colorScheme == .dark ? 0.84 : 0.98))
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                demoPanelTitle("Resume workspace")

                Text(OnboardingDemoData.sampleResumeJSON)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(DesignSystem.Colors.surface(colorScheme))
                    )

                ForEach(OnboardingDemoData.resumeHighlights) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                        Text(item.detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .frame(width: 360, alignment: .topLeading)
        }
        .padding(28)
    }

    private var launchStep: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 16) {
                Text("You do not need to configure everything on day one.")
                    .font(.title.weight(.bold))

                Text("The essentials are simple: add one real application, connect AI when you want parsing or tailoring, and save one master resume revision. Everything else can come later.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                OnboardingChecklistCard(
                    title: "Core setup checklist",
                    progress: progress,
                    onAction: completeAndRun,
                    showsReplayAction: false
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                demoPanelTitle("Jump straight into the live app")

                quickActionButton(
                    title: "Add First Application",
                    subtitle: "Open the real add-application flow now.",
                    icon: "plus.circle.fill",
                    action: .addApplication
                )

                quickActionButton(
                    title: "Configure AI",
                    subtitle: "Open the provider setup screen for parsing and tailoring.",
                    icon: "brain.head.profile",
                    action: .openAISettings
                )

                quickActionButton(
                    title: "Open Resume Workspace",
                    subtitle: "Import or draft the master resume that tailoring builds from.",
                    icon: "doc.badge.plus",
                    action: .openResumeWorkspace
                )

                quickActionButton(
                    title: "Review Integrations",
                    subtitle: "See browser and workflow tools when you are ready.",
                    icon: "puzzlepiece.extension",
                    action: .openIntegrations
                )

                Spacer()
            }
            .frame(width: 320, alignment: .topLeading)
        }
        .padding(28)
    }

    private func introMetric(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DesignSystem.Colors.surface(colorScheme))
        )
    }

    private func demoApplicationCard(_ application: OnboardingDemoData.DemoApplication) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(application.role)
                        .font(.headline)
                    Text("\(application.company) • \(application.location)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(application.score)")
                    .font(.headline.weight(.bold))
                    .foregroundColor(DesignSystem.Colors.accent)
            }

            HStack {
                Text(application.status)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.18 : 0.10))
                    )
                Spacer()
                Text("Match score")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }

    private func quickActionButton(
        title: String,
        subtitle: String,
        icon: String,
        action: OnboardingAction
    ) -> some View {
        Button {
            completeAndRun(action)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.accent)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DesignSystem.Colors.surface(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func demoPanelTitle(_ value: String) -> some View {
        Text(value)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }

    private func bullet(_ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(DesignSystem.Colors.accent)
                .padding(.top, 1)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func move(_ delta: Int) {
        guard let currentIndex = steps.firstIndex(of: selectedStep) else { return }
        let nextIndex = min(max(currentIndex + delta, 0), steps.count - 1)
        selectedStep = steps[nextIndex]
    }

    private func completeAndRun(_ action: OnboardingAction) {
        onComplete()
        onAction(action)
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.2).ignoresSafeArea()
        OnboardingFlowView(
            progress: .preview,
            onAction: { _ in },
            onComplete: {},
            onSkip: {}
        )
    }
}
