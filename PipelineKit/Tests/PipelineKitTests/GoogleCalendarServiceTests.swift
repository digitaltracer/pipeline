import Foundation
import Testing
@testable import PipelineKit

@Test func googleCalendarCreateEventEncodesMutationPayloadAndParsesResponse() async throws {
    let session = makeMockSession { request in
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString.contains("/calendars/primary/events") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-123")

        let bodyData = try #require(request.httpBody ?? request.httpBodyStream.flatMap(readHTTPBody))
        let json = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(json["summary"] as? String == "Interview — Stripe — Phone Screen")
        #expect(json["description"] as? String == "Tracked in Pipeline")
        let extendedProperties = try #require(json["extendedProperties"] as? [String: Any])
        let privateValues = try #require(extendedProperties["private"] as? [String: String])
        #expect(privateValues["pipelineEventKind"] == "interview")

        let responseJSON = """
        {
          "id": "evt-123",
          "etag": "etag-123",
          "status": "confirmed",
          "summary": "Interview — Stripe — Phone Screen",
          "description": "Tracked in Pipeline",
          "start": { "dateTime": "2026-03-15T09:00:00Z" },
          "end": { "dateTime": "2026-03-15T10:00:00Z" },
          "extendedProperties": {
            "private": {
              "pipelineEventKind": "interview",
              "pipelineActivityID": "activity-1"
            }
          }
        }
        """

        return (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            Data(responseJSON.utf8)
        )
    }

    let service = GoogleCalendarService(session: session)
    let payload = try await service.createEvent(
        calendarID: "primary",
        calendarName: "Primary",
        accessToken: "token-123",
        draft: GoogleCalendarEventDraft(
            summary: "Interview — Stripe — Phone Screen",
            details: "Tracked in Pipeline",
            startDate: Date(timeIntervalSince1970: 1_773_571_200),
            endDate: Date(timeIntervalSince1970: 1_773_574_800),
            timeZoneIdentifier: "UTC",
            privateMetadata: [
                "pipelineEventKind": "interview",
                "pipelineActivityID": "activity-1"
            ]
        )
    )

    #expect(payload.eventID == "evt-123")
    #expect(payload.etag == "etag-123")
    #expect(payload.privateMetadata["pipelineEventKind"] == "interview")
}

@Test func googleCalendarDeleteEventUsesDeleteMethod() async throws {
    let session = makeMockSession { request in
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.absoluteString.contains("/events/evt-999") == true)
        return (
            HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!,
            Data()
        )
    }

    let service = GoogleCalendarService(session: session)
    try await service.deleteEvent(
        calendarID: "primary",
        eventID: "evt-999",
        accessToken: "token-123"
    )
}

private func makeMockSession(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    MockGoogleCalendarURLProtocol.handler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockGoogleCalendarURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class MockGoogleCalendarURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func readHTTPBody(from stream: InputStream) -> Data? {
    stream.open()
    defer { stream.close() }

    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    var data = Data()
    while stream.hasBytesAvailable {
        let bytesRead = stream.read(buffer, maxLength: bufferSize)
        guard bytesRead > 0 else { break }
        data.append(buffer, count: bytesRead)
    }

    return data.isEmpty ? nil : data
}
