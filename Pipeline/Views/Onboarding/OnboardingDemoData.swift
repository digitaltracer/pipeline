import Foundation

enum OnboardingDemoData {
    struct DemoApplication: Identifiable {
        let id: String
        let company: String
        let role: String
        let location: String
        let status: String
        let score: Int
    }

    struct DemoColumn: Identifiable {
        let id: String
        let title: String
        let count: Int
        let companies: [String]
    }

    struct DemoMetric: Identifiable {
        let id: String
        let title: String
        let value: String
        let change: String
    }

    struct DemoResumeHighlight: Identifiable {
        let id: String
        let title: String
        let detail: String
    }

    struct DemoCalendarSource: Identifiable {
        let id: String
        let title: String
        let detail: String
        let isSelected: Bool
        let isWriteTarget: Bool
    }

    struct DemoCalendarReviewItem: Identifiable {
        let id: String
        let company: String
        let title: String
        let timing: String
        let status: String
    }

    struct DemoConnection: Identifiable {
        let id: String
        let name: String
        let title: String
        let company: String
        let relationship: String
    }

    static let applications: [DemoApplication] = [
        DemoApplication(
            id: "demo-openai",
            company: "OpenAI",
            role: "Product Engineer",
            location: "San Francisco, CA",
            status: "Applied",
            score: 92
        ),
        DemoApplication(
            id: "demo-figma",
            company: "Figma",
            role: "Platform Engineer",
            location: "Remote",
            status: "Interviewing",
            score: 88
        ),
        DemoApplication(
            id: "demo-stripe",
            company: "Stripe",
            role: "Software Engineer",
            location: "Seattle, WA",
            status: "Saved",
            score: 85
        )
    ]

    static let kanbanColumns: [DemoColumn] = [
        DemoColumn(id: "saved", title: "Saved", count: 6, companies: ["Stripe", "Ramp", "Scale"]),
        DemoColumn(id: "applied", title: "Applied", count: 4, companies: ["OpenAI", "Notion", "Vanta"]),
        DemoColumn(id: "interviewing", title: "Interviewing", count: 2, companies: ["Figma", "Linear"])
    ]

    static let metrics: [DemoMetric] = [
        DemoMetric(id: "response-rate", title: "Response Rate", value: "31%", change: "+8 pts"),
        DemoMetric(id: "avg-match", title: "Average Match", value: "87", change: "+6"),
        DemoMetric(id: "follow-ups", title: "Follow-ups Due", value: "5", change: "2 overdue")
    ]

    static let resumeHighlights: [DemoResumeHighlight] = [
        DemoResumeHighlight(
            id: "impact",
            title: "Keep a master resume",
            detail: "Tailoring runs start from one canonical JSON resume and produce job-specific revisions."
        ),
        DemoResumeHighlight(
            id: "ats",
            title: "Review ATS fixes",
            detail: "Pipeline surfaces missing keywords and structural issues before you export."
        ),
        DemoResumeHighlight(
            id: "evidence",
            title: "Carry evidence forward",
            detail: "Paste strong bullets once, then reuse them across tailored revisions."
        )
    ]

    static let googleCalendarSources: [DemoCalendarSource] = [
        DemoCalendarSource(
            id: "primary",
            title: "Avery Candidate",
            detail: "Primary interview calendar",
            isSelected: true,
            isWriteTarget: true
        ),
        DemoCalendarSource(
            id: "work",
            title: "Recruiting Prep",
            detail: "Read for recruiter holds and prep blocks",
            isSelected: true,
            isWriteTarget: false
        ),
        DemoCalendarSource(
            id: "personal",
            title: "Personal",
            detail: "Ignored by Pipeline",
            isSelected: false,
            isWriteTarget: false
        )
    ]

    static let googleCalendarReviewItems: [DemoCalendarReviewItem] = [
        DemoCalendarReviewItem(
            id: "figma-onsite",
            company: "Figma",
            title: "Panel interview",
            timing: "Tue 10:00 AM",
            status: "Needs review"
        ),
        DemoCalendarReviewItem(
            id: "openai-recruiter",
            company: "OpenAI",
            title: "Recruiter sync",
            timing: "Wed 1:30 PM",
            status: "Update"
        )
    ]

    static let linkedInImportSteps: [(title: String, detail: String)] = [
        (
            "Export first-degree connections",
            "Download the official LinkedIn connections CSV from LinkedIn Settings."
        ),
        (
            "Import the file into Pipeline",
            "Pipeline keeps the raw network in a separate layer instead of auto-adding everyone as a contact."
        ),
        (
            "Review matches when companies overlap",
            "Promote the right people into contacts only when they become useful for a live application."
        )
    ]

    static let linkedInConnections: [DemoConnection] = [
        DemoConnection(
            id: "maya",
            name: "Maya Chen",
            title: "Staff Product Designer",
            company: "Figma",
            relationship: "Referral likely"
        ),
        DemoConnection(
            id: "daniel",
            name: "Daniel Park",
            title: "Engineering Manager",
            company: "OpenAI",
            relationship: "Warm intro"
        ),
        DemoConnection(
            id: "nina",
            name: "Nina Patel",
            title: "Recruiting Ops",
            company: "Stripe",
            relationship: "Keep in network"
        )
    ]

    static let linkedInImportHighlights: [DemoResumeHighlight] = [
        DemoResumeHighlight(
            id: "referral-match",
            title: "Find referral angles per application",
            detail: "When an imported connection shares a company with a job, Pipeline can surface that match inside Job Details."
        ),
        DemoResumeHighlight(
            id: "contact-promotion",
            title: "Keep contacts curated",
            detail: "Useful network rows can be promoted into saved contacts instead of flooding your contact list on import."
        ),
        DemoResumeHighlight(
            id: "outreach-history",
            title: "Track referral outreach",
            detail: "Pipeline can draft referral requests, log attempts, and reflect referral wins back in dashboard analytics."
        )
    ]

    static let sampleParseURL = "https://boards.greenhouse.io/example/jobs/12345"

    static let sampleParseFields: [(label: String, value: String)] = [
        ("Company", "Example AI"),
        ("Role", "Senior iOS Engineer"),
        ("Location", "Remote"),
        ("Salary", "$180K - $220K"),
        ("Platform", "Greenhouse")
    ]

    static let sampleResumeJSON = """
    {
      "name": "Avery Candidate",
      "summary": "Builds polished product experiences and reliable application tooling.",
      "experience": [
        {
          "company": "Northwind",
          "title": "Senior Engineer",
          "dates": "2022 - Present"
        }
      ],
      "skills": {
        "Languages": ["Swift", "TypeScript", "Python"]
      }
    }
    """
}
