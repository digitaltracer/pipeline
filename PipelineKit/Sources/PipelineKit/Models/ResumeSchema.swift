import Foundation

public struct ResumeSchema: Codable, Sendable, Equatable {
    public struct Contact: Codable, Sendable, Equatable {
        public let phone: String
        public let email: String
        public let linkedin: String
        public let github: String

        public init(phone: String, email: String, linkedin: String, github: String) {
            self.phone = phone
            self.email = email
            self.linkedin = linkedin
            self.github = github
        }
    }

    public struct EducationEntry: Codable, Sendable, Equatable {
        public let university: String
        public let location: String
        public let degree: String
        public let date: String

        public init(university: String, location: String, degree: String, date: String) {
            self.university = university
            self.location = location
            self.degree = degree
            self.date = date
        }
    }

    public struct ExperienceEntry: Codable, Sendable, Equatable {
        public let title: String
        public let company: String
        public let location: String
        public let dates: String
        public let responsibilities: [String]

        public init(
            title: String,
            company: String,
            location: String,
            dates: String,
            responsibilities: [String]
        ) {
            self.title = title
            self.company = company
            self.location = location
            self.dates = dates
            self.responsibilities = responsibilities
        }
    }

    public struct ProjectEntry: Codable, Sendable, Equatable {
        public let name: String
        public let url: String?
        public let technologies: [String]
        public let date: String
        public let description: [String]

        public init(
            name: String,
            url: String?,
            technologies: [String],
            date: String,
            description: [String]
        ) {
            self.name = name
            self.url = url
            self.technologies = technologies
            self.date = date
            self.description = description
        }
    }

    public let name: String
    public let contact: Contact
    public let education: [EducationEntry]
    public let summary: String?
    public let experience: [ExperienceEntry]
    public let projects: [ProjectEntry]
    public let skills: [String: [String]]

    public init(
        name: String,
        contact: Contact,
        education: [EducationEntry],
        summary: String? = nil,
        experience: [ExperienceEntry],
        projects: [ProjectEntry],
        skills: [String: [String]]
    ) {
        self.name = name
        self.contact = contact
        self.education = education
        self.summary = summary
        self.experience = experience
        self.projects = projects
        self.skills = skills
    }
}
