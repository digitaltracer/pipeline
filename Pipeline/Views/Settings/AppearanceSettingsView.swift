import SwiftUI
import PipelineKit

struct AppearanceSettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var showsDarkThemeStyle: Bool {
        switch viewModel.appearanceMode {
        case .dark: return true
        case .light: return false
        case .system: return colorScheme == .dark
        }
    }

    private var showsLightThemeStyle: Bool {
        switch viewModel.appearanceMode {
        case .light: return true
        case .dark: return false
        case .system: return colorScheme == .light
        }
    }

    var body: some View {
        Form {
            Section("Theme") {
                AppearanceSettingsContent(viewModel: viewModel)
            }
            if showsDarkThemeStyle {
                Section("Dark Theme Style") {
                    DarkThemeStyleSection(viewModel: viewModel)
                }
            }
            if showsLightThemeStyle {
                Section("Light Theme Style") {
                    LightThemeStyleSection(viewModel: viewModel)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
    }
}

struct AppearanceSettingsContent: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        SettingsFormSectionCard(
            title: "Theme",
            subtitle: "Pick how Pipeline should appear during your workflow.",
            icon: "paintbrush.fill"
        ) {
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
}

struct DarkThemeStyleSection: View {
    @Bindable var viewModel: SettingsViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        SettingsFormSectionCard(
            title: "Dark Theme Style",
            subtitle: "Choose the color palette used in dark mode.",
            icon: "moon.stars.fill"
        ) {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(DarkThemeStyle.allCases) { style in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.darkThemeStyle = style
                        }
                    } label: {
                        DarkThemeStyleCard(
                            style: style,
                            isSelected: viewModel.darkThemeStyle == style
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct DarkThemeStyleCard: View {
    let style: DarkThemeStyle
    let isSelected: Bool

    private var palette: DarkThemePalette { style.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview
                .frame(height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                }

            VStack(spacing: 2) {
                Text(style.displayName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? DesignSystem.Colors.accent : .primary)

                Text(style.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
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

    private var preview: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(palette.sidebarBackground.color)
                .frame(width: 22)
                .overlay(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(palette.surfaceElevated.color)
                                .frame(width: 12, height: 3)
                        }
                    }
                    .padding(.leading, 5)
                }

            ZStack {
                palette.contentBackground.color

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.surface.color)
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.surface.color)
                            .frame(height: 6)
                    }

                    Spacer(minLength: 0)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(palette.primary.color)
                        .frame(width: 36, height: 4)
                }
                .padding(8)
            }
        }
    }
}

struct LightThemeStyleSection: View {
    @Bindable var viewModel: SettingsViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        SettingsFormSectionCard(
            title: "Light Theme Style",
            subtitle: "Choose the color palette used in light mode.",
            icon: "sun.max.fill"
        ) {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(LightThemeStyle.allCases) { style in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.lightThemeStyle = style
                        }
                    } label: {
                        LightThemeStyleCard(
                            style: style,
                            isSelected: viewModel.lightThemeStyle == style
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct LightThemeStyleCard: View {
    let style: LightThemeStyle
    let isSelected: Bool

    private var palette: LightThemePalette { style.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview
                .frame(height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                }

            VStack(spacing: 2) {
                Text(style.displayName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? DesignSystem.Colors.accent : .primary)

                Text(style.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
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

    private var preview: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(palette.sidebarBackground.color)
                .frame(width: 22)
                .overlay(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(palette.surfaceElevated.color)
                                .frame(width: 12, height: 3)
                        }
                    }
                    .padding(.leading, 5)
                }

            ZStack {
                palette.contentBackground.color

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.surface.color)
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.surface.color)
                            .frame(height: 6)
                    }

                    Spacer(minLength: 0)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(palette.primary.color)
                        .frame(width: 36, height: 4)
                }
                .padding(8)
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
                .foregroundColor(isSelected ? DesignSystem.Colors.accent : .primary)
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
