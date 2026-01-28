import SwiftUI

struct CompanyAvatar: View {
    let companyName: String
    let logoURL: String?
    var size: CGFloat = 48

    private var initial: String {
        String(companyName.prefix(1)).uppercased()
    }

    private var backgroundColor: Color {
        // Generate consistent color based on company name
        let colors: [Color] = [
            .blue, .purple, .orange, .green, .pink, .cyan, .indigo, .mint, .teal
        ]
        let hash = abs(companyName.hashValue)
        return colors[hash % colors.count]
    }

    var body: some View {
        Group {
            if let logoURL = logoURL, let url = URL(string: logoURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        initialAvatar
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        initialAvatar
                    @unknown default:
                        initialAvatar
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size / 4))
            } else {
                initialAvatar
            }
        }
    }

    private var initialAvatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size / 4)
                .fill(backgroundColor.gradient)

            Text(initial)
                .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

struct CompanyAvatarWithDomain: View {
    let companyName: String
    let domain: String?
    var size: CGFloat = 48

    private var logoURL: String? {
        guard let domain = domain else { return nil }
        return "https://logo.clearbit.com/\(domain)"
    }

    var body: some View {
        CompanyAvatar(companyName: companyName, logoURL: logoURL, size: size)
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            CompanyAvatar(companyName: "Apple", logoURL: "https://logo.clearbit.com/apple.com", size: 48)
            CompanyAvatar(companyName: "Google", logoURL: "https://logo.clearbit.com/google.com", size: 48)
            CompanyAvatar(companyName: "Microsoft", logoURL: "https://logo.clearbit.com/microsoft.com", size: 48)
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
