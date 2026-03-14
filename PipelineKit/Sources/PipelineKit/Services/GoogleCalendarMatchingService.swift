import Foundation

public struct GoogleCalendarMatchSuggestion: Equatable {
    public let application: JobApplication
    public let score: Int
}

public enum GoogleCalendarMatchingService {
    public static func bestMatch(
        for event: GoogleCalendarEventPayload,
        among applications: [JobApplication]
    ) -> GoogleCalendarMatchSuggestion? {
        suggestions(for: event, among: applications).first
    }

    public static func suggestions(
        for event: GoogleCalendarEventPayload,
        among applications: [JobApplication]
    ) -> [GoogleCalendarMatchSuggestion] {
        applications.compactMap { application in
            let score = score(for: event, application: application)
            guard score > 0 else { return nil }
            return GoogleCalendarMatchSuggestion(application: application, score: score)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.application.updatedAt > rhs.application.updatedAt
        }
    }

    public static func inferInterviewStage(for event: GoogleCalendarEventPayload) -> InterviewStage? {
        let haystack = [event.summary, event.location, event.details]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        let mappings: [(InterviewStage, [String])] = [
            (.phoneScreen, ["phone screen", "screening", "recruiter screen", "intro call"]),
            (.technicalRound1, ["technical", "coding", "leetcode", "pair programming", "online assessment"]),
            (.technicalRound2, ["technical round 2", "technical ii", "coding round 2"]),
            (.designChallenge, ["design challenge", "take home"]),
            (.systemDesign, ["system design", "architecture", "design round"]),
            (.hrRound, ["hiring manager", "manager chat", "manager round", "behavioral", "culture", "leadership", "hr"]),
            (.finalRound, ["final round", "final interview"]),
            (.offerExtended, ["offer", "offer review"])
        ]

        for (stage, tokens) in mappings {
            if tokens.contains(where: { haystack.contains($0) }) {
                return stage
            }
        }

        return nil
    }

    private static func score(for event: GoogleCalendarEventPayload, application: JobApplication) -> Int {
        let haystack = [event.summary, event.location, event.details, event.organizerEmail]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        var score = 0

        let company = application.companyName.lowercased()
        if haystack.contains(company) {
            score += 70
        } else {
            let companyTokens = tokenize(company)
            if companyTokens.contains(where: haystack.contains) {
                score += 30
            }
        }

        let roleTokens = tokenize(application.role.lowercased()).filter { $0.count > 3 }
        let roleMatches = roleTokens.filter { haystack.contains($0) }
        score += min(roleMatches.count * 12, 36)

        let locationTokens = tokenize(application.location.lowercased()).filter { $0.count > 3 }
        let locationMatches = locationTokens.filter { haystack.contains($0) }
        score += min(locationMatches.count * 6, 18)

        let contactNames = application.sortedContactLinks
            .compactMap { $0.contact?.fullName.lowercased() }
        if contactNames.contains(where: haystack.contains) {
            score += 24
        }

        if let domain = event.organizerEmail?.split(separator: "@").last?.lowercased(),
           !domain.isEmpty,
           haystack.contains(domain) {
            score += 16
        }

        return score
    }

    private static func tokenize(_ value: String) -> [String] {
        value
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
