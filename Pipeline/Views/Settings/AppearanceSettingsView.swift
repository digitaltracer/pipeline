import SwiftUI

struct AppearanceSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Theme") {
                AppearanceSettingsContent(viewModel: viewModel)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
    }
}

struct AppearanceSettingsContent: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        HStack(spacing: 16) {
            ForEach(AppearanceMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.appearanceMode = mode
                    }
                } label: {
                    ThemeCard(
                        mode: mode,
                        isSelected: viewModel.appearanceMode == mode
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ThemeCard: View {
    let mode: AppearanceMode
    let isSelected: Bool

    private var backgroundColor: Color {
        switch mode {
        case .light: return .white
        case .dark: return Color(white: 0.15)
        case .system:
            #if os(macOS)
            return Color(.textBackgroundColor)
            #else
            return Color(.systemBackground)
            #endif
        }
    }

    private var foregroundColor: Color {
        switch mode {
        case .light: return .black
        case .dark: return .white
        case .system: return .primary
        }
    }

    private var iconName: String {
        switch mode {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .system: return "desktopcomputer"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Preview area
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
                .frame(height: 70)
                .overlay {
                    Image(systemName: iconName)
                        .font(.system(size: 28))
                        .foregroundColor(mode == .light ? .orange : (mode == .dark ? .yellow : DesignSystem.Colors.accent))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                }

            // Label
            Text(mode.rawValue)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .blue : .primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? DesignSystem.Colors.accent : Color.clear, lineWidth: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// Legacy preview card for iOS (if needed)
struct ThemePreviewCard: View {
    let mode: AppearanceMode
    let isSelected: Bool

    private var backgroundColor: Color {
        switch mode {
        case .light: return .white
        case .dark: return Color(white: 0.15)
        case .system:
            #if os(macOS)
            return Color(.textBackgroundColor)
            #else
            return Color(.systemBackground)
            #endif
        }
    }

    private var foregroundColor: Color {
        switch mode {
        case .light: return .black
        case .dark: return .white
        case .system: return .primary
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
                .frame(height: 60)
                .overlay {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(foregroundColor.opacity(0.3))
                            .frame(width: 40, height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(foregroundColor.opacity(0.2))
                            .frame(width: 30, height: 4)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                }

            Text(mode.rawValue)
                .font(.caption)
                .foregroundColor(isSelected ? .blue : .secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    VStack {
        AppearanceSettingsContent(viewModel: SettingsViewModel())
            .padding()

        Divider()

        AppearanceSettingsView(viewModel: SettingsViewModel())
    }
}
