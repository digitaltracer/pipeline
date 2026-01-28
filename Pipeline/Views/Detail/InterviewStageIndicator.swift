import SwiftUI

struct InterviewStageIndicator: View {
    let currentStage: InterviewStage?
    let onStageChange: (InterviewStage?) -> Void

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

                    ForEach(InterviewStage.orderedCases) { stage in
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

    private var backgroundColor: Color {
        if isCurrent {
            return stage.color
        } else if isCompleted {
            return .green
        } else {
            return Color(.textBackgroundColor)
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
    }
    .padding()
}
