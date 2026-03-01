import SwiftUI
import PipelineKit

struct PriorityFlag: View {
    let priority: Priority
    var showLabel: Bool = false
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: priority.icon)
                .font(.system(size: size))
                .foregroundColor(priority.color)

            if showLabel {
                Text(priority.displayName)
                    .font(.system(size: size - 2, weight: .medium))
                    .foregroundColor(priority.color)
            }
        }
    }
}

struct PriorityPicker: View {
    @Binding var selection: Priority

    var body: some View {
        Picker("Priority", selection: $selection) {
            ForEach(Priority.allCases) { priority in
                HStack {
                    Image(systemName: priority.icon)
                        .foregroundColor(priority.color)
                    Text(priority.displayName)
                }
                .tag(priority)
            }
        }
    }
}

struct PriorityBadge: View {
    let priority: Priority

    var body: some View {
        if priority == .high {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                Text("High Priority")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.yellow)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.yellow.opacity(0.15))
            .clipShape(Capsule())
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ForEach(Priority.allCases) { priority in
            HStack {
                PriorityFlag(priority: priority)
                PriorityFlag(priority: priority, showLabel: true)
                PriorityFlag(priority: priority, showLabel: true, size: 18)
            }
        }
    }
    .padding()
}
