import Foundation

public protocol ExchangeRateProviding: Sendable {
    func convert(amount: Int, from: Currency, to: Currency, on date: Date) async -> ExchangeRateService.ConversionResult?
}

public final class ExchangeRateService: ExchangeRateProviding, @unchecked Sendable {
    public struct ConversionResult: Sendable {
        public let amount: Double
        public let rateDate: Date
        public let usedFallback: Bool

        public init(amount: Double, rateDate: Date, usedFallback: Bool) {
            self.amount = amount
            self.rateDate = rateDate
            self.usedFallback = usedFallback
        }
    }

    private struct CachedRateEntry: Codable, Sendable {
        let date: String
        let base: String
        let rates: [String: Double]
    }

    private struct FrankfurterResponse: Decodable {
        let date: String
        let rates: [String: Double]
    }

    public static let shared = ExchangeRateService()

    private let session: URLSession
    private let userDefaults: UserDefaults
    private let calendar: Calendar
    private let cacheKey = "ExchangeRateService.cachedRates"

    public init(
        session: URLSession = .shared,
        userDefaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.session = session
        self.userDefaults = userDefaults
        self.calendar = calendar
    }

    public func convert(amount: Int, from: Currency, to: Currency, on date: Date) async -> ConversionResult? {
        if from == to {
            return ConversionResult(amount: Double(amount), rateDate: date, usedFallback: false)
        }

        let normalizedDate = normalizedDayString(for: date)

        if let exactRate = cachedRate(for: normalizedDate, base: from, target: to) {
            return ConversionResult(
                amount: Double(amount) * exactRate.rate,
                rateDate: exactRate.date,
                usedFallback: exactRate.usedFallback
            )
        }

        if let fetched = await fetchRate(for: normalizedDate, base: from, target: to) {
            return ConversionResult(
                amount: Double(amount) * fetched.rate,
                rateDate: fetched.date,
                usedFallback: false
            )
        }

        if let fallbackRate = bestOfflineCachedRate(for: date, base: from, target: to) {
            return ConversionResult(
                amount: Double(amount) * fallbackRate.rate,
                rateDate: fallbackRate.date,
                usedFallback: true
            )
        }

        return nil
    }

    private func fetchRate(
        for normalizedDate: String,
        base: Currency,
        target: Currency
    ) async -> (rate: Double, date: Date)? {
        guard var components = URLComponents(string: "https://api.frankfurter.app/\(normalizedDate)") else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "from", value: base.rawValue),
            URLQueryItem(name: "to", value: target.rawValue)
        ]

        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                return nil
            }

            let payload = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
            let rateValue = payload.rates[target.rawValue]
            guard let rateValue else { return nil }
            cacheRates(date: payload.date, base: base, rates: payload.rates)
            return (rateValue, dateFromDayString(payload.date) ?? Date())
        } catch {
            return nil
        }
    }

    private func cachedRate(
        for normalizedDate: String,
        base: Currency,
        target: Currency
    ) -> (rate: Double, date: Date, usedFallback: Bool)? {
        let entries = cachedEntries()
        guard let entry = entries.first(where: { $0.date == normalizedDate && $0.base == base.rawValue }),
              let rate = entry.rates[target.rawValue],
              let date = dateFromDayString(entry.date)
        else {
            return nil
        }
        return (rate, date, false)
    }

    private func bestOfflineCachedRate(
        for date: Date,
        base: Currency,
        target: Currency
    ) -> (rate: Double, date: Date)? {
        let entries = cachedEntries()
            .filter { $0.base == base.rawValue }
            .compactMap { entry -> (rate: Double, date: Date)? in
                guard let cachedDate = dateFromDayString(entry.date),
                      let rate = entry.rates[target.rawValue]
                else {
                    return nil
                }
                return (rate, cachedDate)
            }
            .sorted { $0.date > $1.date }

        if let prior = entries.first(where: { $0.date <= date }) {
            return prior
        }

        return entries.first
    }

    private func cachedEntries() -> [CachedRateEntry] {
        guard let data = userDefaults.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([CachedRateEntry].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private func cacheRates(date: String, base: Currency, rates: [String: Double]) {
        var entries = cachedEntries().filter { !($0.date == date && $0.base == base.rawValue) }
        entries.append(CachedRateEntry(date: date, base: base.rawValue, rates: rates))
        if let data = try? JSONEncoder().encode(entries.suffix(120)) {
            userDefaults.set(data, forKey: cacheKey)
        }
    }

    private func normalizedDayString(for date: Date) -> String {
        let normalizedDate = calendar.startOfDay(for: date)
        return Self.dayFormatter.string(from: normalizedDate)
    }

    private func dateFromDayString(_ value: String) -> Date? {
        Self.dayFormatter.date(from: value)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
