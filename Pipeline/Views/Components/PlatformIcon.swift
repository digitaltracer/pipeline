import SwiftUI

struct PlatformIcon: View {
    let platform: Platform
    var showLabel: Bool = false
    var size: CGFloat = 16

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: platform.icon)
                .font(.system(size: size))
                .foregroundColor(platform.color)

            if showLabel {
                Text(platform.displayName)
                    .font(.system(size: size - 2, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct PlatformBadge: View {
    let platform: Platform

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: platform.icon)
                .font(.system(size: 10))
            Text(platform.displayName)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundColor(platform.color)
        .background(platform.color.opacity(0.1))
        .clipShape(Capsule())
    }
}

struct PlatformDotLabel: View {
    let platform: Platform
    var fontSize: CGFloat = 12

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(platform.color)
                .frame(width: 8, height: 8)
            Text(platform.displayName)
                .font(.system(size: fontSize))
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ForEach(Platform.allCases) { platform in
            HStack(spacing: 20) {
                PlatformIcon(platform: platform)
                PlatformIcon(platform: platform, showLabel: true)
                PlatformBadge(platform: platform)
            }
        }
    }
    .padding()
}
