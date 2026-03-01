import SwiftUI
import PipelineKit

struct StatusBadge: View {
    let status: ApplicationStatus
    var showIcon: Bool = false
    var size: BadgeSize = .regular

    enum BadgeSize {
        case small
        case regular
        case large

        var fontSize: CGFloat {
            switch self {
            case .small: return 10
            case .regular: return 12
            case .large: return 14
            }
        }

        var padding: EdgeInsets {
            switch self {
            case .small: return EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6)
            case .regular: return EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            case .large: return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .small: return 8
            case .regular: return 10
            case .large: return 12
            }
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if showIcon {
                Image(systemName: status.icon)
                    .font(.system(size: size.iconSize))
            }
            Text(status.displayName)
                .font(.system(size: size.fontSize, weight: .medium))
        }
        .padding(size.padding)
        .foregroundColor(status.color)
        .background(status.color.opacity(0.15))
        .clipShape(Capsule())
    }
}

struct TagBadge: View {
    let text: String
    let color: Color
    var icon: String? = nil
    var size: StatusBadge.BadgeSize = .small

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: size.iconSize))
            }
            Text(text)
                .font(.system(size: size.fontSize, weight: .medium))
        }
        .padding(size.padding)
        .foregroundColor(color)
        .background(color.opacity(0.16))
        .clipShape(Capsule())
    }
}

#Preview {
    VStack(spacing: 12) {
        ForEach(ApplicationStatus.allCases) { status in
            HStack {
                StatusBadge(status: status, size: .small)
                StatusBadge(status: status)
                StatusBadge(status: status, showIcon: true)
                StatusBadge(status: status, showIcon: true, size: .large)
            }
        }

        TagBadge(text: "Technical Round 2", color: .orange, icon: "laptopcomputer", size: .regular)
    }
    .padding()
}
