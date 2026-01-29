import SwiftUI

struct InterviewStageIndicator: View {
    let currentStage: InterviewStage?
    let onStageChange: (InterviewStage?) -> Void

    private var stageMenuOptions: [InterviewStage] {
        let defaults = InterviewStage.orderedCases
        let customs = CustomValuesStore.customInterviewStages()
            .map { InterviewStage(rawValue: $0) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        var seen = Set<String>()
        return (defaults + customs).filter { stage in
            let key = stage.rawValue.lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Interview Progress")
                    .font(.headline)

                Spacer()

                Menu {
                    Button("Clear Stage") {
                        onStageChange(nil)
                    }

                    Divider()

                    ForEach(stageMenuOptions) { stage in
                        Button {
                            onStageChange(stage)
                        } label: {
                            Label(stage.displayName, systemImage: stage.icon)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.secondary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(InterviewStage.orderedCases) { stage in
                        StageItem(
                            stage: stage,
                            isCompleted: isCompleted(stage),
                            isCurrent: currentStage == stage
                        )
                        .onTapGesture {
                            onStageChange(stage)
                        }

                        if stage != InterviewStage.orderedCases.last {
                            StageConnector(isCompleted: isCompleted(stage))
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func isCompleted(_ stage: InterviewStage) -> Bool {
        guard let current = currentStage else { return false }
        return stage.sortOrder < current.sortOrder
    }
}

struct StageItem: View {
    let stage: InterviewStage
    let isCompleted: Bool
    let isCurrent: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        if isCurrent {
            return stage.color
        } else if isCompleted {
            return .green
        } else {
            return DesignSystem.Colors.surfaceElevated(colorScheme)
        }
    }

    private var foregroundColor: Color {
        if isCurrent || isCompleted {
            return .white
        } else {
            return .secondary
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 36, height: 36)

                if isCompleted && !isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(foregroundColor)
                } else {
                    Image(systemName: stage.icon)
                        .font(.system(size: 14))
                        .foregroundColor(foregroundColor)
                }
            }

            Text(stage.shortName)
                .font(.system(size: 10))
                .foregroundColor(isCurrent ? stage.color : .secondary)
        }
        .contentShape(Rectangle())
    }
}

struct StageConnector: View {
    let isCompleted: Bool

    var body: some View {
        Rectangle()
            .fill(isCompleted ? Color.green : Color.secondary.opacity(0.3))
            .frame(width: 20, height: 2)
            .offset(y: -10)
    }
}

struct InterviewStageBannerView: View {
    let stage: InterviewStage
    let onStageChange: (InterviewStage?) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var stageMenuOptions: [InterviewStage] {
        let defaults = InterviewStage.orderedCases
        let customs = CustomValuesStore.customInterviewStages()
            .map { InterviewStage(rawValue: $0) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        var seen = Set<String>()
        return (defaults + customs).filter { stage in
            let key = stage.rawValue.lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            TagBadge(text: stage.displayName, color: stage.color, icon: stage.icon, size: .regular)

            Spacer()

            Menu {
                Button("Clear Stage") { onStageChange(nil) }
                Divider()
                ForEach(stageMenuOptions) { stage in
                    Button {
                        onStageChange(stage)
                    } label: {
                        Label(stage.displayName, systemImage: stage.icon)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(DesignSystem.Colors.surfaceElevated(colorScheme))
                    .clipShape(Circle())
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            #endif
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(stage.color.opacity(colorScheme == .dark ? 0.18 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }
}

#Preview {
    VStack(spacing: 40) {
        InterviewStageIndicator(
            currentStage: .technicalRound1,
            onStageChange: { _ in }
        )

        InterviewStageIndicator(
            currentStage: .systemDesign,
            onStageChange: { _ in }
        )

        InterviewStageIndicator(
            currentStage: nil,
            onStageChange: { _ in }
        )

        InterviewStageBannerView(stage: .technicalRound2, onStageChange: { _ in })
    }
    .padding()
}
