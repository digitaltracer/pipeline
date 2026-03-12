import Foundation
import SwiftData

@Model
public final class CompanyResearchSource {
    public var id: UUID = UUID()
    public var title: String = ""
    public var urlString: String = ""
    public var sourceKindRawValue: String = CompanyResearchSourceKind.manual.rawValue
    public var fetchStatusRawValue: String = CompanyResearchFetchStatus.skipped.rawValue
    public var validationStatusRawValue: String = ResearchValidationStatus.skipped.rawValue
    public var acquisitionMethodRawValue: String = ResearchAcquisitionMethod.none.rawValue
    public var contentExcerpt: String?
    public var resolvedURLString: String?
    public var errorMessage: String?
    public var validationReason: String?
    public var confidenceRawValue: String?
    public var citationPayload: String?
    public var orderIndex: Int = 0
    public var fetchedAt: Date?
    public var validatedAt: Date?
    public var isExcludedFromResearch: Bool = false
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
        resolvedURLString: String? = nil,
        errorMessage: String? = nil,
        validationStatus: ResearchValidationStatus = .skipped,
        acquisitionMethod: ResearchAcquisitionMethod = .none,
        validationReason: String? = nil,
        confidence: ResearchConfidence? = nil,
        citationPayload: String? = nil,
        orderIndex: Int = 0,
        fetchedAt: Date? = nil,
        validatedAt: Date? = nil,
        isExcludedFromResearch: Bool = false,
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
        self.validationStatusRawValue = validationStatus.rawValue
        self.acquisitionMethodRawValue = acquisitionMethod.rawValue
        self.contentExcerpt = CompanyProfile.normalizedText(contentExcerpt)
        self.resolvedURLString = CompanyProfile.normalizedURLString(resolvedURLString)
        self.errorMessage = CompanyProfile.normalizedText(errorMessage)
        self.validationReason = CompanyProfile.normalizedText(validationReason)
        self.confidenceRawValue = confidence?.rawValue
        self.citationPayload = CompanyProfile.normalizedText(citationPayload)
        self.orderIndex = orderIndex
        self.fetchedAt = fetchedAt
        self.validatedAt = validatedAt
        self.isExcludedFromResearch = isExcludedFromResearch
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
        get {
            if let status = CompanyResearchFetchStatus(rawValue: fetchStatusRawValue) {
                return status
            }
            if fetchStatusRawValue == "fetched" {
                return .partial
            }
            if fetchStatusRawValue == "failed" {
                return .failed
            }
            return .skipped
        }
        set {
            guard fetchStatusRawValue != newValue.rawValue else { return }
            fetchStatusRawValue = newValue.rawValue
            updateTimestamp()
        }
    }

    public var validationStatus: ResearchValidationStatus {
        get {
            if let status = ResearchValidationStatus(rawValue: validationStatusRawValue) {
                return status
            }
            switch fetchStatus {
            case .verified:
                return .verified
            case .partial, .fetched:
                return .partial
            case .blocked:
                return .blocked
            case .invalid:
                return .invalid
            case .manual:
                return .manual
            case .failed:
                return .blocked
            case .skipped:
                return .skipped
            }
        }
        set {
            guard validationStatusRawValue != newValue.rawValue else { return }
            validationStatusRawValue = newValue.rawValue
            updateTimestamp()
        }
    }

    public var acquisitionMethod: ResearchAcquisitionMethod {
        get { ResearchAcquisitionMethod(rawValue: acquisitionMethodRawValue) ?? .none }
        set {
            guard acquisitionMethodRawValue != newValue.rawValue else { return }
            acquisitionMethodRawValue = newValue.rawValue
            updateTimestamp()
        }
    }

    public var confidence: ResearchConfidence? {
        get { confidenceRawValue.flatMap(ResearchConfidence.init(rawValue:)) }
        set {
            let rawValue = newValue?.rawValue
            guard confidenceRawValue != rawValue else { return }
            confidenceRawValue = rawValue
            updateTimestamp()
        }
    }

    public var normalizedURL: URL? {
        URL(string: CompanyProfile.normalizedURLString(urlString) ?? urlString)
    }

    public var resolvedURL: URL? {
        guard let resolvedURLString else { return nil }
        return URL(string: CompanyProfile.normalizedURLString(resolvedURLString) ?? resolvedURLString)
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }
}
