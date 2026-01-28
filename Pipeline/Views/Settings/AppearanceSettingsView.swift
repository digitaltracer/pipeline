import SwiftUI

struct AppearanceSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $viewModel.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
                .pickerStyle(.inline)
            }

            Section {
                HStack {
                    ForEach(AppearanceMode.allCases) { mode in
                        ThemePreviewCard(
                            mode: mode,
                            isSelected: viewModel.appearanceMode == mode
                        )
                        .onTapGesture {
                            withAnimation {
                                viewModel.appearanceMode = mode
                            }
                        }
                    }
                }
            } header: {
                Text("Preview")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
    }
}

struct ThemePreviewCard: View {
    let mode: AppearanceMode
    let isSelected: Bool

    private var backgroundColor: Color {
        switch mode {
        case .light: return .white
        case .dark: return Color(white: 0.15)
        case .system: return Color(.textBackgroundColor)
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
    AppearanceSettingsView(viewModel: SettingsViewModel())
}
