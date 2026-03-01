import Foundation

public enum Currency: String, Codable, CaseIterable, Identifiable, Sendable {
    case usd = "USD"
    case inr = "INR"
    case eur = "EUR"
    case gbp = "GBP"

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    public var symbol: String {
        switch self {
        case .usd: return "$"
        case .inr: return "₹"
        case .eur: return "€"
        case .gbp: return "£"
        }
    }

    public var locale: Locale {
        switch self {
        case .usd: return Locale(identifier: "en_US")
        case .inr: return Locale(identifier: "en_IN")
        case .eur: return Locale(identifier: "de_DE")
        case .gbp: return Locale(identifier: "en_GB")
        }
    }

    /// Format a salary value with the currency symbol
    public func format(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = symbol
        formatter.maximumFractionDigits = 0
        formatter.locale = locale

        return formatter.string(from: NSNumber(value: value)) ?? "\(symbol)\(value)"
    }

    /// Format a salary range
    public func formatRange(min: Int?, max: Int?) -> String? {
        guard min != nil || max != nil else { return nil }

        if let min = min, let max = max {
            if min == max {
                return format(min)
            }
            return "\(format(min)) - \(format(max))"
        } else if let min = min {
            return "\(format(min))+"
        } else if let max = max {
            return "Up to \(format(max))"
        }

        return nil
    }
}
