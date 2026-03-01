import SwiftUI
import PipelineKit

struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField(
                "",
                text: $text,
                prompt: Text(placeholder).foregroundColor(DesignSystem.Colors.placeholder(colorScheme))
            )
                .textFieldStyle(.plain)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .appInput()
    }
}

#Preview {
    VStack(spacing: 20) {
        SearchBar(text: .constant(""))
        SearchBar(text: .constant("Apple"))
    }
    .padding()
    .frame(width: 300)
}
