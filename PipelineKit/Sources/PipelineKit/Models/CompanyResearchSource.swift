import Foundation
import SwiftData

@Model
public final class CompanyResearchSource {
    public var id: UUID = UUID()
    public var title: String = ""
    public var urlString: String = ""
    public var sourceKindRawValue: String = CompanyResearchSourceKind.manual.rawValue
    public var fetchStatusRawValue: String = CompanyResearchFetchStatus.skipped.rawValue
    public var contentExcerpt: String?
    public var errorMessage: String?
    public var orderIndex: Int = 0
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var company: CompanyProfile?
    public var snapshot: CompanyResearchSnapshot?

    public init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        sourceKind: CompanyResearchSourceKind,
        fetchStatus: CompanyResearchFetchStatus,
        contentExcerpt: String? = nil,
        errorMessage: String? = nil,
        orderIndex: Int = 0,
        company: CompanyProfile? = nil,
        snapshot: CompanyResearchSnapshot? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.urlString = CompanyProfile.normalizedURLString(urlString) ?? urlString
        self.sourceKindRawValue = sourceKind.rawValue
        self.fetchStatusRawValue = fetchStatus.rawValue
        self.contentExcerpt = CompanyProfile.normalizedText(contentExcerpt)
        self.errorMessage = CompanyProfile.normalizedText(errorMessage)
        self.orderIndex = orderIndex
        self.company = company
        self.snapshot = snapshot
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var sourceKind: CompanyResearchSourceKind {
        get { CompanyResearchSourceKind(rawValue: sourceKindRawValue) ?? .manual }
        set {
            guard sourceKindRawValue != newValue.rawValue else { return }
            sourceKindRawValue = newValue.rawValue
            updateTimestamp()
        }
    }

    public var fetchStatus: CompanyResearchFetchStatus {
        get { CompanyResearchFetchStatus(rawValue: fetchStatusRawValue) ?? .skipped }
        set {
            guard fetchStatusRawValue != newValue.rawValue else { return }
            fetchStatusRawValue = newValue.rawValue
            updateTimestamp()
        }
    }

    public var normalizedURL: URL? {
        URL(string: CompanyProfile.normalizedURLString(urlString) ?? urlString)
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }
}
