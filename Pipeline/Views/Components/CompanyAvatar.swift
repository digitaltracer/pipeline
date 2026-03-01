import SwiftUI
import PipelineKit

struct CompanyAvatar: View {
    let companyName: String
    let logoURL: String?
    var size: CGFloat = 48
    var cornerRadius: CGFloat = 14

    private var initial: String {
        String(companyName.prefix(1)).uppercased()
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(DesignSystem.Colors.inputBackground(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
                )

            if let logoURL, let url = URL(string: logoURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        initialContent
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(size * 0.18)
                    case .failure:
                        initialContent
                    @unknown default:
                        initialContent
                    }
                }
            } else {
                initialContent
            }
        }
        .frame(width: size, height: size)
    }

    private var initialContent: some View {
        Text(initial)
            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
            .foregroundColor(.secondary)
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            CompanyAvatar(companyName: "Apple", logoURL: nil, size: 48)
            CompanyAvatar(companyName: "Google", logoURL: nil, size: 48)
            CompanyAvatar(companyName: "Microsoft", logoURL: nil, size: 48)
        }

        HStack(spacing: 16) {
            CompanyAvatar(companyName: "Apple", logoURL: nil, size: 48)
            CompanyAvatar(companyName: "Google", logoURL: nil, size: 48)
            CompanyAvatar(companyName: "Startup XYZ", logoURL: nil, size: 48)
        }

        HStack(spacing: 16) {
            CompanyAvatar(companyName: "Small", logoURL: nil, size: 32)
            CompanyAvatar(companyName: "Medium", logoURL: nil, size: 48)
            CompanyAvatar(companyName: "Large", logoURL: nil, size: 64)
        }
    }
    .padding()
}
