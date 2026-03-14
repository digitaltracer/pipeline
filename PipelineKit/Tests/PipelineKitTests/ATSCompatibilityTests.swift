import Foundation
import SwiftData
import Testing
@testable import PipelineKit

@Test func atsPrepareDraftBlocksWhenResumeSourceMissing() throws {
    let application = JobApplication(
        companyName: "Acme",
        role: "Platform Engineer",
        location: "Remote"
    )

    let draft = try ATSCompatibilityScoringService.prepareDraft(
        application: application,
        resumeSource: nil
    )

    #expect(draft.status == .blocked)
    #expect(draft.blockedReason == .missingResumeSource)
}

@Test func atsFallsBackToMasterResumeWhenNoSnapshotExists() throws {
    let container = try makeATSContainer()
    let context = ModelContext(container)
    let application = JobApplication(
        companyName: "Acme",
        role: "Platform Engineer",
        location: "Remote",
        jobDescription: sampleATSJobDescription
    )
    context.insert(application)

    let masterRevision = try ResumeStoreService.saveMasterRevision(
        rawJSON: sampleATSResumeJSON,
        unknownFieldPaths: [],
        in: context
    )

    let source = try ResumeStoreService.preferredResumeSource(for: application, in: context)
    let draft = try ATSCompatibilityScoringService.prepareDraft(
        application: application,
        resumeSource: source
    )

    #expect(source?.kind == .masterResume)
    #expect(source?.masterRevisionID == masterRevision.id)
    #expect(draft.status == .ready)
    #expect(draft.resumeSourceKind == .masterResume)
}

@Test func atsPrefersLatestTailoredSnapshotWhenAvailable() throws {
    let container = try makeATSContainer()
    let context = ModelContext(container)
    let application = JobApplication(
        companyName: "Acme",
        role: "Platform Engineer",
        location: "Remote",
        jobDescription: sampleATSJobDescription
    )
    context.insert(application)

    let masterRevision = try ResumeStoreService.saveMasterRevision(
        rawJSON: sampleATSResumeJSON,
        unknownFieldPaths: [],
        in: context
    )
    let snapshot = try ResumeStoreService.createJobSnapshot(
        for: application,
        rawJSON: sampleATSResumeJSON,
        acceptedPatchIDs: [],
        rejectedPatchIDs: [],
        sectionGaps: [],
        sourceMasterRevisionID: masterRevision.id,
        in: context
    )

    let source = try ResumeStoreService.preferredResumeSource(for: application, in: context)
    let draft = try ATSCompatibilityScoringService.prepareDraft(
        application: application,
        resumeSource: source
    )

    #expect(source?.kind == .tailoredSnapshot)
    #expect(source?.snapshotID == snapshot.id)
    #expect(draft.resumeSourceKind == .tailoredSnapshot)
    #expect(draft.resumeSourceSnapshotID == snapshot.id)
}

@Test func atsMatchesExactTechTokensAndAliases() throws {
    let application = JobApplication(
        companyName: "Acme",
        role: "Platform Engineer",
        location: "Remote",
        jobDescription: "Build CI/CD pipelines and distributed systems with gRPC, .NET, C++, Kubernetes, and DataDog."
    )

    let source = ResumeSourceSelection(
        kind: .masterResume,
        rawJSON: """
        {
          "name": "Taylor Candidate",
          "contact": {
            "phone": "+1 555 123 4567",
            "email": "taylor@example.com",
            "linkedin": "linkedin.com/in/taylor",
            "github": "github.com/taylor"
          },
          "education": [{"university":"State University","location":"CA","degree":"BS","date":"2020"}],
          "summary": "Platform engineer focused on continuous integration and distributed systems.",
          "experience": [{
            "title":"Software Engineer",
            "company":"Example",
            "location":"Remote",
            "dates":"2021-Present",
            "responsibilities":[
              "Built grpc services in dotnet and maintained c++ integrations.",
              "Scaled k8s deployments and Datadog observability across CI CD workflows."
            ]
          }],
          "projects": [],
          "skills": {"Platforms":["dotnet","grpc","k8s","Datadog","c++","CI/CD"]}
        }
        """,
        snapshotID: nil,
        masterRevisionID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"),
        createdAt: Date(timeIntervalSince1970: 1_000)
    )

    let draft = try ATSCompatibilityScoringService.prepareDraft(
        application: application,
        resumeSource: source
    )

    #expect(draft.status == .ready)
    #expect(draft.matchedKeywords.contains("CI/CD"))
    #expect(draft.matchedKeywords.contains("gRPC"))
    #expect(draft.matchedKeywords.contains(".NET"))
    #expect(draft.matchedKeywords.contains("C++"))
    #expect(draft.matchedKeywords.contains("Kubernetes"))
    #expect(draft.matchedKeywords.contains("DataDog"))
}

@Test func atsTracksEvidenceBackedSkillPromotionCandidates() throws {
    let application = JobApplication(
        companyName: "Acme",
        role: "Platform Engineer",
        location: "Remote",
        jobDescription: "Lead Kubernetes platform work, improve Kubernetes reliability, and ship CI/CD automation."
    )

    let source = ResumeSourceSelection(
        kind: .masterResume,
        rawJSON: """
        {
          "name": "Taylor Candidate",
          "contact": {
            "phone": "+1 555 123 4567",
            "email": "taylor@example.com",
            "linkedin": "linkedin.com/in/taylor",
            "github": "github.com/taylor"
          },
          "education": [{"university":"State University","location":"CA","degree":"BS","date":"2020"}],
          "summary": "Platform engineer improving developer workflows.",
          "experience": [{
            "title":"Software Engineer",
            "company":"Example",
            "location":"Remote",
            "dates":"2021-Present",
            "responsibilities":[
              "Scaled Kubernetes clusters and improved Kubernetes deployment reliability.",
              "Maintained CI/CD automation for production rollouts."
            ]
          }],
          "projects": [],
          "skills": {"Platforms":["AWS"],"Practices":["CI/CD"]}
        }
        """,
        snapshotID: nil,
        masterRevisionID: UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB"),
        createdAt: Date(timeIntervalSince1970: 1_000)
    )

    let draft = try ATSCompatibilityScoringService.prepareDraft(
        application: application,
        resumeSource: source
    )

    #expect(draft.matchedKeywords.contains("Kubernetes"))
    #expect(!draft.missingKeywords.contains("Kubernetes"))
    #expect(draft.skillsPromotionKeywords.contains("Kubernetes"))
    #expect(draft.keywordEvidenceSummary.contains(where: { $0.contains("Kubernetes appears") }))
}

@Test func atsFlagsUnknownRenderedFieldsInFormatWarnings() throws {
    let application = JobApplication(
        companyName: "Acme",
        role: "Backend Engineer",
        location: "Remote",
        jobDescription: sampleATSJobDescription
    )

    let source = ResumeSourceSelection(
        kind: .masterResume,
        rawJSON: """
        {
          "name": "Taylor Candidate",
          "contact": {
            "phone": "+1 555 123 4567",
            "email": "taylor@example.com",
            "linkedin": "linkedin.com/in/taylor",
            "github": "github.com/taylor"
          },
          "education": [{
            "university":"State University",
            "location":"CA",
            "degree":"BS Computer Science",
            "date":"2020"
          }],
          "summary": "Backend engineer improving platform reliability and API performance.",
          "experience": [{
            "title":"Software Engineer",
            "company":"Example",
            "location":"Remote",
            "dates":"2021-Present",
            "responsibilities":[
              "Built Kubernetes services and improved CI/CD pipelines for API deployments."
            ],
            "internalNotes":"Not rendered"
          }],
          "projects": [],
          "skills": {
            "Platforms":["Kubernetes","Terraform","CI/CD","DataDog","gRPC"]
          },
          "metadata": {
            "favoriteColor": "blue"
          }
        }
        """,
        snapshotID: nil,
        masterRevisionID: UUID(uuidString: "EFEFEFEF-EFEF-EFEF-EFEF-EFEFEFEFEFEF"),
        createdAt: Date(timeIntervalSince1970: 1_000)
    )

    let draft = try ATSCompatibilityScoringService.prepareDraft(
        application: application,
        resumeSource: source
    )

    #expect(draft.formatWarningFindings.contains(where: { $0.contains("not rendered by Pipeline exports") }))
}

@Test func atsQuickFixServiceBuildsEvidenceBackedSkillPatches() throws {
    let assessment = ATSCompatibilityAssessment(
        skillsPromotionKeywords: ["Kubernetes"]
    )

    let result = try ATSCompatibilityQuickFixService.makeSkillPromotionPatches(
        assessment: assessment,
        resumeJSON: """
        {
          "name": "Taylor Candidate",
          "contact": {
            "phone": "+1 555 123 4567",
            "email": "taylor@example.com",
            "linkedin": "linkedin.com/in/taylor",
            "github": "github.com/taylor"
          },
          "education": [{"university":"State University","location":"CA","degree":"BS","date":"2020"}],
          "summary": "Platform engineer focused on reliability.",
          "experience": [{
            "title":"Software Engineer",
            "company":"Example",
            "location":"Remote",
            "dates":"2021-Present",
            "responsibilities":[
              "Scaled Kubernetes clusters for internal platforms."
            ]
          }],
          "projects": [],
          "skills": {"Platforms":["AWS"]}
        }
        """
    )

    #expect(result.unsupportedKeywords.isEmpty)
    #expect(result.patches.count == 1)
    #expect(result.patches[0].path == "/skills/Platforms")
    #expect(result.patches[0].evidencePaths.contains("/experience/0/responsibilities/0"))
    #expect(result.patches[0].risk == .low)
}

@Test func atsQuickFixServiceSkipsUnsupportedKeywordsWithoutEvidence() throws {
    let assessment = ATSCompatibilityAssessment(
        skillsPromotionKeywords: ["Terraform"]
    )

    let result = try ATSCompatibilityQuickFixService.makeSkillPromotionPatches(
        assessment: assessment,
        resumeJSON: sampleATSResumeJSON.replacingOccurrences(of: "Terraform", with: "Docker")
    )

    #expect(result.patches.isEmpty)
    #expect(result.unsupportedKeywords == ["Terraform"])
}

@Test func atsScoresAreDeterministicAndWeighted() throws {
    let application = JobApplication(
        companyName: "Acme",
        role: "Backend Engineer",
        location: "Remote",
        jobDescription: sampleATSJobDescription
    )
    let source = ResumeSourceSelection(
        kind: .masterResume,
        rawJSON: sampleATSResumeJSON,
        snapshotID: nil,
        masterRevisionID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"),
        createdAt: Date(timeIntervalSince1970: 1_000)
    )

    let first = try ATSCompatibilityScoringService.prepareDraft(
        application: application,
        resumeSource: source,
        referenceDate: Date(timeIntervalSince1970: 2_000)
    )
    let second = try ATSCompatibilityScoringService.prepareDraft(
        application: application,
        resumeSource: source,
        referenceDate: Date(timeIntervalSince1970: 2_000)
    )

    let weightedKeyword = Double(first.keywordScore ?? 0) * 0.55
    let weightedSections = Double(first.sectionScore ?? 0) * 0.20
    let weightedContact = Double(first.contactScore ?? 0) * 0.15
    let weightedFormat = Double(first.formatScore ?? 0) * 0.10
    let expectedOverall = Int(
        (weightedKeyword + weightedSections + weightedContact + weightedFormat).rounded()
    )

    #expect(first == second)
    #expect(first.overallScore == expectedOverall)
}

@Test func atsStaleDetectionTracksJobDescriptionSourceAndVersion() throws {
    let application = JobApplication(
        companyName: "Acme",
        role: "Backend Engineer",
        location: "Remote",
        jobDescription: sampleATSJobDescription
    )
    let source = ResumeSourceSelection(
        kind: .masterResume,
        rawJSON: sampleATSResumeJSON,
        snapshotID: nil,
        masterRevisionID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"),
        createdAt: Date(timeIntervalSince1970: 1_000)
    )
    let draft = try ATSCompatibilityScoringService.prepareDraft(
        application: application,
        resumeSource: source,
        referenceDate: Date(timeIntervalSince1970: 2_000)
    )

    let assessment = ATSCompatibilityAssessment()
    assessment.applyReadyState(
        overallScore: draft.overallScore ?? 0,
        keywordScore: draft.keywordScore ?? 0,
        sectionScore: draft.sectionScore ?? 0,
        contactScore: draft.contactScore ?? 0,
        formatScore: draft.formatScore ?? 0,
        summary: draft.summary ?? "",
        matchedKeywords: draft.matchedKeywords,
        missingKeywords: draft.missingKeywords,
        skillsPromotionKeywords: draft.skillsPromotionKeywords,
        keywordEvidenceSummary: draft.keywordEvidenceSummary,
        criticalFindings: draft.criticalFindings,
        warningFindings: draft.warningFindings,
        sectionFindings: draft.sectionFindings,
        contactWarningFindings: draft.contactWarningFindings,
        contactCriticalFindings: draft.contactCriticalFindings,
        formatWarningFindings: draft.formatWarningFindings,
        formatCriticalFindings: draft.formatCriticalFindings,
        hasExperienceSection: draft.hasExperienceSection,
        hasEducationSection: draft.hasEducationSection,
        hasSkillsSection: draft.hasSkillsSection,
        resumeSourceKind: draft.resumeSourceKind ?? .masterResume,
        resumeSourceSnapshotID: draft.resumeSourceSnapshotID,
        resumeSourceRevisionID: draft.resumeSourceRevisionID,
        resumeSourceFingerprint: draft.resumeSourceFingerprint,
        jobDescriptionHash: draft.jobDescriptionHash,
        scoringVersion: draft.scoringVersion,
        scoredAt: draft.scoredAt
    )

    #expect(!ATSCompatibilityScoringService.isStale(
        assessment,
        application: application,
        resumeSource: source
    ))

    application.jobDescription = "Updated JD with Terraform."
    #expect(ATSCompatibilityScoringService.isStale(
        assessment,
        application: application,
        resumeSource: source
    ))

    application.jobDescription = sampleATSJobDescription
    let snapshotSource = ResumeSourceSelection(
        kind: .tailoredSnapshot,
        rawJSON: sampleATSResumeJSON,
        snapshotID: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"),
        masterRevisionID: source.masterRevisionID,
        createdAt: source.createdAt
    )
    #expect(ATSCompatibilityScoringService.isStale(
        assessment,
        application: application,
        resumeSource: snapshotSource
    ))

    assessment.scoringVersion = "ats-compat-v0"
    #expect(ATSCompatibilityScoringService.isStale(
        assessment,
        application: application,
        resumeSource: source
    ))
}

private let sampleATSJobDescription = """
Design and maintain backend services with Kubernetes, Terraform, CI/CD, gRPC, and DataDog. Build scalable APIs and support production reliability.
"""

private let sampleATSResumeJSON = """
{
  "name": "Taylor Candidate",
  "contact": {
    "phone": "+1 555 123 4567",
    "email": "taylor@example.com",
    "linkedin": "linkedin.com/in/taylor",
    "github": "github.com/taylor"
  },
  "education": [{
    "university":"State University",
    "location":"CA",
    "degree":"BS Computer Science",
    "date":"2020"
  }],
  "summary": "Backend engineer improving platform reliability and API performance.",
  "experience": [{
    "title":"Software Engineer",
    "company":"Example",
    "location":"Remote",
    "dates":"2021-Present",
    "responsibilities":[
      "Built Kubernetes services and improved CI/CD pipelines for API deployments.",
      "Added Terraform modules and DataDog dashboards for production systems.",
      "Implemented grpc endpoints supporting internal platform tooling."
    ]
  }],
  "projects": [{
    "name":"Platform Toolkit",
    "url":"https://example.com",
    "technologies":["Swift","Terraform"],
    "date":"2024",
    "description":["Created tooling for deployment workflows."]
  }],
  "skills": {
    "Platforms":["Kubernetes","Terraform","CI/CD","DataDog","gRPC"],
    "Languages":["Swift","Go"]
  }
}
"""

private func makeATSContainer() throws -> ModelContainer {
    let schema = Schema([
        JobApplication.self,
        JobSearchCycle.self,
        SearchGoal.self,
        InterviewLog.self,
        CompanyProfile.self,
        CompanyResearchSnapshot.self,
        CompanyResearchSource.self,
        CompanySalarySnapshot.self,
        Contact.self,
        ApplicationContactLink.self,
        ApplicationActivity.self,
        InterviewDebrief.self,
        RejectionLog.self,
        InterviewQuestionEntry.self,
        InterviewLearningSnapshot.self,
        RejectionLearningSnapshot.self,
        ApplicationTask.self,
        FollowUpStep.self,
        ApplicationChecklistSuggestion.self,
        ApplicationAttachment.self,
        CoverLetterDraft.self,
        ATSCompatibilityAssessment.self,
        ATSCompatibilityScanRun.self,
        ResumeMasterRevision.self,
        ResumeJobSnapshot.self,
        AIUsageRecord.self,
        AIModelRate.self
    ])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}
