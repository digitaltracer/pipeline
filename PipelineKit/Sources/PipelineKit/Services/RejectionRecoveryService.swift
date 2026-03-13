import Foundation

public struct RejectionRecoverySuggestion: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let applicationID: UUID?
    public let companyName: String?

    public init(
        id: String,
        title: String,
        body: String,
        applicationID: UUID? = nil,
        companyName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.applicationID = applicationID
        self.companyName = companyName
    }
}

public enum RejectionRecoveryService {
    public static func suggestions(
        for application: JobApplication,
        among applications: [JobApplication],
        cooldownDays: Int = 90,
        referenceDate: Date = Date()
    ) -> [RejectionRecoverySuggestion] {
        guard application.status == .rejected else { return [] }
        guard shouldAllowReapplySuggestions(for: application, among: applications) else { return [] }

        var suggestions: [RejectionRecoverySuggestion] = []

        if let referralSuggestion = referralRecovery(for: application, among: applications) {
            suggestions.append(referralSuggestion)
        }

        if let technicalSuggestion = technicalRecovery(for: application, among: applications) {
            suggestions.append(technicalSuggestion)
        }

        if let senioritySuggestion = seniorityRecovery(for: application, among: applications) {
            suggestions.append(senioritySuggestion)
        }

        if let similarRoleSuggestion = similarRoleRecovery(for: application, among: applications) {
            suggestions.append(similarRoleSuggestion)
        }

        if let companyRetrySuggestion = companyRetryRecovery(
            for: application,
            among: applications,
            cooldownDays: cooldownDays,
            referenceDate: referenceDate
        ) {
            suggestions.append(companyRetrySuggestion)
        }

        var seen = Set<String>()
        return suggestions.filter { seen.insert($0.id).inserted }
    }

    public static func topActionableSuggestion(
        among applications: [JobApplication],
        referenceDate: Date = Date()
    ) -> RejectionRecoverySuggestion? {
        let candidates = applications
            .filter { $0.status == .rejected }
            .sorted { $0.updatedAt > $1.updatedAt }

        for application in candidates {
            if let suggestion = suggestions(for: application, among: applications, referenceDate: referenceDate).first {
                return suggestion
            }
        }

        return nil
    }

    private static func referralRecovery(
        for application: JobApplication,
        among applications: [JobApplication]
    ) -> RejectionRecoverySuggestion? {
        let submitted = applications.filter { $0.submittedAt != nil && $0.status != .archived }
        let referralApps = submitted.filter { $0.source == .referral }
        let coldApps = submitted.filter { $0.source != .referral }

        guard referralApps.count >= 3, coldApps.count >= 3 else { return nil }

        let referralRate = responseRate(for: referralApps)
        let coldRate = responseRate(for: coldApps)
        guard referralRate - coldRate >= 0.15 else { return nil }

        return RejectionRecoverySuggestion(
            id: "referral-\(application.id.uuidString)",
            title: "Retry similar roles with a warmer intro.",
            body: "Your response rate is stronger on referral-led applications than on cold outreach. Secure a referral before retrying similar roles.",
            companyName: application.companyName
        )
    }

    private static func technicalRecovery(
        for application: JobApplication,
        among applications: [JobApplication]
    ) -> RejectionRecoverySuggestion? {
        let technicalRejections = applications.filter {
            $0.latestRejectionLog?.stageCategory == .technical
        }

        guard technicalRejections.count >= 3 else { return nil }

        return RejectionRecoverySuggestion(
            id: "technical-\(application.id.uuidString)",
            title: "Technical rounds are the current bottleneck.",
            body: "You have multiple rejections after technical stages. Prioritize technical practice before retrying similar roles.",
            companyName: application.companyName
        )
    }

    private static func seniorityRecovery(
        for application: JobApplication,
        among applications: [JobApplication]
    ) -> RejectionRecoverySuggestion? {
        let rejectedRoles = applications.filter { $0.status == .rejected }
        guard rejectedRoles.count >= 3 else { return nil }

        let rejectedLevels = rejectedRoles.compactMap { seniorityLevel(for: $0.role) }
        let positiveLevels = applications
            .filter { $0.status == .interviewing || $0.status == .offered }
            .compactMap { seniorityLevel(for: $0.role) }

        guard !rejectedLevels.isEmpty else { return nil }
        let rejectedAverage = Double(rejectedLevels.reduce(0, +)) / Double(rejectedLevels.count)
        let positiveBaseline = positiveLevels.isEmpty ? 2.0 : Double(positiveLevels.max() ?? 2)

        guard rejectedAverage - positiveBaseline >= 1 else { return nil }

        return RejectionRecoverySuggestion(
            id: "seniority-\(application.id.uuidString)",
            title: "Your current target set may be skewing too senior.",
            body: "Recent rejections cluster around more senior role titles than your recent positive traction. Bias new applications toward mid-level matches.",
            companyName: application.companyName
        )
    }

    private static func similarRoleRecovery(
        for application: JobApplication,
        among applications: [JobApplication]
    ) -> RejectionRecoverySuggestion? {
        let targetRole = CompanyProfile.normalizedRoleTitle(application.role)
        let targetLevel = seniorityLevel(for: application.role) ?? 0

        guard let betterFit = applications.first(where: { candidate in
            guard candidate.id != application.id else { return false }
            guard candidate.status != .rejected, candidate.status != .archived else { return false }
            guard candidate.source != .referral || application.source != .referral else { return false }
            let candidateRole = CompanyProfile.normalizedRoleTitle(candidate.role)
            guard !candidateRole.isEmpty else { return false }
            let sameCompany = CompanyProfile.normalizedName(from: candidate.companyName) == CompanyProfile.normalizedName(from: application.companyName)
            let sharedRoleStem = candidateRole.contains(targetRole) || targetRole.contains(candidateRole)
            guard sameCompany || sharedRoleStem else { return false }
            let candidateLevel = seniorityLevel(for: candidate.role) ?? targetLevel
            return candidateLevel <= targetLevel
        }) else {
            return nil
        }

        return RejectionRecoverySuggestion(
            id: "similar-role-\(betterFit.id.uuidString)",
            title: "A better-fit role already exists in Pipeline.",
            body: "\(betterFit.companyName) has a similar role in your pipeline that appears closer to your current fit. Redirect effort there before broadening out again.",
            applicationID: betterFit.id,
            companyName: betterFit.companyName
        )
    }

    private static func companyRetryRecovery(
        for application: JobApplication,
        among applications: [JobApplication],
        cooldownDays: Int,
        referenceDate: Date
    ) -> RejectionRecoverySuggestion? {
        let companyKey = CompanyProfile.normalizedName(from: application.companyName)
        guard !companyKey.isEmpty else { return nil }

        guard let latestRejection = applications
            .filter({ CompanyProfile.normalizedName(from: $0.companyName) == companyKey && $0.status == .rejected })
            .compactMap({ $0.latestRejectionActivity?.occurredAt })
            .max()
        else {
            return nil
        }

        let elapsedDays = Int(referenceDate.timeIntervalSince(latestRejection) / 86_400)
        guard elapsedDays >= cooldownDays else { return nil }

        return RejectionRecoverySuggestion(
            id: "retry-\(companyKey)",
            title: "This company may be worth revisiting later.",
            body: "Your last rejection at \(application.companyName) was \(elapsedDays) days ago. Consider a retry only if the role scope or your approach has changed.",
            companyName: application.companyName
        )
    }

    private static func shouldAllowReapplySuggestions(
        for application: JobApplication,
        among applications: [JobApplication]
    ) -> Bool {
        let companyKey = CompanyProfile.normalizedName(from: application.companyName)
        let companyRejections = applications.filter {
            CompanyProfile.normalizedName(from: $0.companyName) == companyKey
        }

        return !companyRejections.contains { $0.latestRejectionLog?.doNotReapply == true }
    }

    private static func responseRate(for applications: [JobApplication]) -> Double {
        guard !applications.isEmpty else { return 0 }
        let responded = applications.filter {
            $0.status == .interviewing || $0.status == .offered || $0.status == .rejected
        }.count
        return Double(responded) / Double(applications.count)
    }

    private static func seniorityLevel(for role: String) -> Int? {
        let normalized = role.lowercased()
        if normalized.contains("intern") {
            return 0
        }
        if normalized.contains("junior") || normalized.contains("associate") {
            return 1
        }
        if normalized.contains("senior") || normalized.contains("lead") {
            return 3
        }
        if normalized.contains("staff") || normalized.contains("principal") {
            return 4
        }
        if normalized.contains("director") || normalized.contains("manager") || normalized.contains("head") {
            return 5
        }
        if normalized.contains("engineer") || normalized.contains("developer") || normalized.contains("designer") || normalized.contains("devrel") {
            return 2
        }
        return nil
    }
}
