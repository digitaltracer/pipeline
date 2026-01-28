import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search..."

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField(placeholder, text: $text)
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
        .padding(8)
        #if os(macOS)
        .background(Color(.textBackgroundColor).opacity(0.5))
        #else
        .background(Color(.systemGray6))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
