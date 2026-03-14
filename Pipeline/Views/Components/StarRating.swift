import SwiftUI
import PipelineKit

struct StarRating: View {
    @Binding var rating: Int
    var maxRating: Int = 5
    var minRating: Int = 1
    var size: CGFloat = 20
    var spacing: CGFloat = 4
    var isEditable: Bool = true

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...maxRating, id: \.self) { index in
                Image(systemName: index <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundColor(index <= rating ? .yellow : .gray.opacity(0.3))
                    .onTapGesture {
                        if isEditable {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                if rating == index {
                                    // Tapping same star toggles between that rating and one less
                                    rating = index - 1
                                } else {
                                    rating = index
                                }
                                if rating < minRating {
                                    rating = minRating
                                }
                            }
                        }
                    }
            }
        }
    }
}

struct StarRatingDisplay: View {
    let rating: Int
    var maxRating: Int = 5
    var size: CGFloat = 14
    var spacing: CGFloat = 2

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...maxRating, id: \.self) { index in
                Image(systemName: index <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundColor(index <= rating ? .yellow : .gray.opacity(0.3))
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        StarRating(rating: .constant(3))
        StarRating(rating: .constant(5), size: 24)
        StarRatingDisplay(rating: 4)
        StarRatingDisplay(rating: 2, size: 12)
    }
    .padding()
}
