import SwiftUI
import PipelineKit

struct SalaryRangeDisplay: View {
    let currency: Currency
    let min: Int?
    let max: Int?
    var style: SalaryStyle = .full

    enum SalaryStyle {
        case full
        case compact
        case badge
    }

    var salaryText: String? {
        currency.formatRange(min: min, max: max)
    }

    var body: some View {
        if let text = salaryText {
            switch style {
            case .full:
                fullStyle(text)
            case .compact:
                compactStyle(text)
            case .badge:
                badgeStyle(text)
            }
        }
    }

    private func fullStyle(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "banknote")
                .foregroundColor(.green)
            Text(text)
                .foregroundColor(.primary)
        }
        .font(.subheadline)
    }

    private func compactStyle(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private func badgeStyle(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "banknote")
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundColor(.green)
        .background(Color.green.opacity(0.1))
        .clipShape(Capsule())
    }
}

#Preview {
    VStack(spacing: 20) {
        SalaryRangeDisplay(currency: .usd, min: 150000, max: 200000)
        SalaryRangeDisplay(currency: .usd, min: 150000, max: 200000, style: .compact)
        SalaryRangeDisplay(currency: .usd, min: 150000, max: 200000, style: .badge)

        SalaryRangeDisplay(currency: .inr, min: 2500000, max: 4000000)
        SalaryRangeDisplay(currency: .eur, min: 80000, max: nil)
        SalaryRangeDisplay(currency: .gbp, min: nil, max: 100000)
    }
    .padding()
}
