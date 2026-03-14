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
