import Foundation

public struct GoogleCalendarListEntry: Equatable {
    public let id: String
    public let title: String
    public let colorHex: String?
    public let isPrimary: Bool
}

public struct GoogleCalendarEventPayload: Equatable {
    public let calendarID: String
    public let calendarName: String
    public let eventID: String
    public let etag: String?
    public let status: String
    public let htmlLink: String?
    public let summary: String?
    public let location: String?
    public let details: String?
    public let organizerEmail: String?
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let privateMetadata: [String: String]

    public init(
        calendarID: String,
        calendarName: String,
        eventID: String,
        etag: String?,
        status: String,
        htmlLink: String?,
        summary: String?,
        location: String?,
        details: String?,
        organizerEmail: String?,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        privateMetadata: [String: String] = [:]
    ) {
        self.calendarID = calendarID
        self.calendarName = calendarName
        self.eventID = eventID
        self.etag = etag
        self.status = status
        self.htmlLink = htmlLink
        self.summary = summary
        self.location = location
        self.details = details
        self.organizerEmail = organizerEmail
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.privateMetadata = privateMetadata
    }
}

public struct GoogleCalendarEventDraft: Equatable, Sendable {
    public let summary: String
    public let location: String?
    public let details: String?
    public let startDate: Date
    public let endDate: Date
    public let timeZoneIdentifier: String
    public let privateMetadata: [String: String]

    public init(
        summary: String,
        location: String? = nil,
        details: String? = nil,
        startDate: Date,
        endDate: Date,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        privateMetadata: [String: String] = [:]
    ) {
        self.summary = summary
        self.location = location
        self.details = details
        self.startDate = startDate
        self.endDate = endDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.privateMetadata = privateMetadata
    }
}

public struct GoogleCalendarSyncResponse: Equatable {
    public let events: [GoogleCalendarEventPayload]
    public let nextSyncToken: String?
}

public enum GoogleCalendarServiceError: LocalizedError {
    case invalidResponse
    case transport(statusCode: Int, message: String?)
    case invalidSyncToken
    case missingEventDate

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Google Calendar returned a response Pipeline could not understand."
        case .transport(let statusCode, let message):
            return message ?? "Google Calendar request failed with status \(statusCode)."
        case .invalidSyncToken:
            return "Google Calendar rejected the saved sync token. Pipeline needs a bounded re-sync."
        case .missingEventDate:
            return "Google Calendar returned an event without a valid start or end date."
        }
    }
}

public actor GoogleCalendarService {
    public static let shared = GoogleCalendarService()

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let iso8601Formatter: ISO8601DateFormatter
    private let fractionalFormatter: ISO8601DateFormatter

    public init(session: URLSession = .shared) {
        self.session = session
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime]
        self.iso8601Formatter = iso8601Formatter

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.fractionalFormatter = fractionalFormatter
    }

    public func fetchCalendars(accessToken: String) async throws -> [GoogleCalendarListEntry] {
        let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
        let response: CalendarListResponse = try await request(url: url, accessToken: accessToken)
        return response.items.map { item in
            GoogleCalendarListEntry(
                id: item.id,
                title: item.summaryOverride ?? item.summary,
                colorHex: item.backgroundColor,
                isPrimary: item.primary ?? false
            )
        }
    }

    public func syncEvents(
        calendarID: String,
        calendarName: String,
        accessToken: String,
        syncToken: String?,
        referenceDate: Date = Date()
    ) async throws -> GoogleCalendarSyncResponse {
        var collected: [GoogleCalendarEventPayload] = []
        var pageToken: String?
        var resolvedNextSyncToken: String?

        repeat {
            let url = try eventsURL(
                calendarID: calendarID,
                syncToken: syncToken,
                pageToken: pageToken,
                referenceDate: referenceDate
            )

            let response: EventsListResponse
            do {
                response = try await request(url: url, accessToken: accessToken)
            } catch let serviceError as GoogleCalendarServiceError {
                if serviceError == .invalidSyncToken {
                    throw serviceError
                }
                throw serviceError
            }

            let pageEvents = try response.items.map { item in
                try payload(from: item, calendarID: calendarID, calendarName: calendarName)
            }
            collected.append(contentsOf: pageEvents)
            pageToken = response.nextPageToken
            resolvedNextSyncToken = response.nextSyncToken ?? resolvedNextSyncToken
        } while pageToken != nil

        return GoogleCalendarSyncResponse(events: collected, nextSyncToken: resolvedNextSyncToken)
    }

    public func fetchEvent(
        calendarID: String,
        calendarName: String,
        eventID: String,
        accessToken: String
    ) async throws -> GoogleCalendarEventPayload {
        let url = eventURL(calendarID: calendarID, eventID: eventID)
        let item: EventItem = try await request(url: url, accessToken: accessToken)
        return try payload(from: item, calendarID: calendarID, calendarName: calendarName)
    }

    public func createEvent(
        calendarID: String,
        calendarName: String,
        accessToken: String,
        draft: GoogleCalendarEventDraft
    ) async throws -> GoogleCalendarEventPayload {
        let url = try eventsMutationURL(calendarID: calendarID)
        let body = try JSONEncoder().encode(EventMutationRequest(draft: draft))
        let item: EventItem = try await request(
            url: url,
            accessToken: accessToken,
            method: "POST",
            body: body
        )
        return try payload(from: item, calendarID: calendarID, calendarName: calendarName)
    }

    public func updateEvent(
        calendarID: String,
        calendarName: String,
        eventID: String,
        accessToken: String,
        draft: GoogleCalendarEventDraft
    ) async throws -> GoogleCalendarEventPayload {
        let url = eventURL(calendarID: calendarID, eventID: eventID)
        let body = try JSONEncoder().encode(EventMutationRequest(draft: draft))
        let item: EventItem = try await request(
            url: url,
            accessToken: accessToken,
            method: "PUT",
            body: body
        )
        return try payload(from: item, calendarID: calendarID, calendarName: calendarName)
    }

    public func deleteEvent(
        calendarID: String,
        eventID: String,
        accessToken: String
    ) async throws {
        let url = eventURL(calendarID: calendarID, eventID: eventID)
        try await requestWithoutResponse(
            url: url,
            accessToken: accessToken,
            method: "DELETE"
        )
    }

    private func eventsURL(
        calendarID: String,
        syncToken: String?,
        pageToken: String?,
        referenceDate: Date
    ) throws -> URL {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID)/events")!

        var queryItems = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "showDeleted", value: "true"),
            URLQueryItem(name: "maxResults", value: "2500")
        ]

        if let syncToken, !syncToken.isEmpty {
            queryItems.append(URLQueryItem(name: "syncToken", value: syncToken))
        } else {
            queryItems.append(URLQueryItem(name: "orderBy", value: "startTime"))
            queryItems.append(URLQueryItem(name: "timeMin", value: iso8601Formatter.string(from: Calendar.current.date(byAdding: .day, value: -30, to: referenceDate) ?? referenceDate)))
            queryItems.append(URLQueryItem(name: "timeMax", value: iso8601Formatter.string(from: Calendar.current.date(byAdding: .day, value: 180, to: referenceDate) ?? referenceDate)))
        }

        if let pageToken, !pageToken.isEmpty {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }

        components.queryItems = queryItems
        guard let url = components.url else {
            throw GoogleCalendarServiceError.invalidResponse
        }
        return url
    }

    private func payload(
        from item: EventItem,
        calendarID: String,
        calendarName: String
    ) throws -> GoogleCalendarEventPayload {
        let start = try resolveEventDate(item.start)
        let end = try resolveEventDate(item.end)
        return GoogleCalendarEventPayload(
            calendarID: calendarID,
            calendarName: calendarName,
            eventID: item.id,
            etag: item.etag,
            status: item.status ?? "confirmed",
            htmlLink: item.htmlLink,
            summary: item.summary,
            location: item.location,
            details: item.description,
            organizerEmail: item.organizer?.email,
            startDate: start.date,
            endDate: max(end.date, start.date),
            isAllDay: start.isAllDay,
            privateMetadata: item.extendedProperties?.privateValues ?? [:]
        )
    }

    private func eventsMutationURL(calendarID: String) throws -> URL {
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID)/events") else {
            throw GoogleCalendarServiceError.invalidResponse
        }
        return url
    }

    private func eventURL(calendarID: String, eventID: String) -> URL {
        URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID)/events/\(eventID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventID)")!
    }

    private func resolveEventDate(_ value: EventDateValue?) throws -> (date: Date, isAllDay: Bool) {
        guard let value else { throw GoogleCalendarServiceError.missingEventDate }

        if let dateTime = value.dateTime {
            if let parsed = fractionalFormatter.date(from: dateTime) ?? iso8601Formatter.date(from: dateTime) {
                return (parsed, false)
            }
        }

        if let date = value.date {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            if let parsed = formatter.date(from: date) {
                return (parsed, true)
            }
        }

        throw GoogleCalendarServiceError.missingEventDate
    }

    private func request<Response: Decodable>(
        url: URL,
        accessToken: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleCalendarServiceError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let apiError = try? decoder.decode(GoogleAPIErrorEnvelope.self, from: data)
            if httpResponse.statusCode == 410 {
                throw GoogleCalendarServiceError.invalidSyncToken
            }
            throw GoogleCalendarServiceError.transport(
                statusCode: httpResponse.statusCode,
                message: apiError?.error.message
            )
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw GoogleCalendarServiceError.invalidResponse
        }
    }

    private func requestWithoutResponse(
        url: URL,
        accessToken: String,
        method: String
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleCalendarServiceError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let apiError = try? decoder.decode(GoogleAPIErrorEnvelope.self, from: data)
            throw GoogleCalendarServiceError.transport(
                statusCode: httpResponse.statusCode,
                message: apiError?.error.message
            )
        }
    }
}

private struct CalendarListResponse: Decodable {
    let items: [CalendarListItem]
}

private struct CalendarListItem: Decodable {
    let id: String
    let summary: String
    let summaryOverride: String?
    let backgroundColor: String?
    let primary: Bool?
}

private struct EventsListResponse: Decodable {
    let items: [EventItem]
    let nextPageToken: String?
    let nextSyncToken: String?
}

private struct EventItem: Decodable {
    let id: String
    let etag: String?
    let status: String?
    let htmlLink: String?
    let summary: String?
    let location: String?
    let description: String?
    let organizer: EventOrganizer?
    let start: EventDateValue?
    let end: EventDateValue?
    let extendedProperties: EventExtendedProperties?
}

private struct EventOrganizer: Decodable {
    let email: String?
}

private struct EventDateValue: Decodable {
    let date: String?
    let dateTime: String?
    let timeZone: String?
}

private struct EventExtendedProperties: Decodable {
    let privateValues: [String: String]

    enum CodingKeys: String, CodingKey {
        case privateValues = "private"
    }
}

private struct EventMutationRequest: Encodable {
    let summary: String
    let location: String?
    let description: String?
    let start: EventMutationDateValue
    let end: EventMutationDateValue
    let extendedProperties: EventMutationExtendedProperties?

    init(draft: GoogleCalendarEventDraft) {
        summary = draft.summary
        location = draft.location
        description = draft.details
        start = EventMutationDateValue(dateTime: draft.startDate, timeZone: draft.timeZoneIdentifier)
        end = EventMutationDateValue(dateTime: draft.endDate, timeZone: draft.timeZoneIdentifier)
        extendedProperties = draft.privateMetadata.isEmpty
            ? nil
            : EventMutationExtendedProperties(privateValues: draft.privateMetadata)
    }
}

private struct EventMutationDateValue: Encodable {
    let dateTime: String
    let timeZone: String

    init(dateTime: Date, timeZone: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        self.dateTime = formatter.string(from: dateTime)
        self.timeZone = timeZone
    }
}

private struct EventMutationExtendedProperties: Encodable {
    let privateValues: [String: String]

    enum CodingKeys: String, CodingKey {
        case privateValues = "private"
    }
}

private struct GoogleAPIErrorEnvelope: Decodable {
    let error: GoogleAPIErrorDetail
}

private struct GoogleAPIErrorDetail: Decodable {
    let message: String?
}

extension GoogleCalendarServiceError: Equatable {
    public static func == (lhs: GoogleCalendarServiceError, rhs: GoogleCalendarServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidResponse, .invalidResponse), (.invalidSyncToken, .invalidSyncToken), (.missingEventDate, .missingEventDate):
            return true
        case let (.transport(lhsStatus, lhsMessage), .transport(rhsStatus, rhsMessage)):
            return lhsStatus == rhsStatus && lhsMessage == rhsMessage
        default:
            return false
        }
    }
}
