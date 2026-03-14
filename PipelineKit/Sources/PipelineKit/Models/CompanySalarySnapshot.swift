import Foundation
import SwiftData

@Model
public final class CompanySalarySnapshot {
    public var id: UUID = UUID()
    public var roleTitle: String = ""
    public var normalizedRoleTitle: String = ""
    public var location: String = ""
    public var normalizedLocation: String = ""
    public var sourceName: String = ""
    public var sourceURLString: String?
    public var notes: String?
    public var confidenceNotes: String?
    public var currencyRawValue: String = Currency.usd.rawValue
    public var seniorityRawValue: String?
    public var minBaseCompensation: Int?
    public var maxBaseCompensation: Int?
    public var minTotalCompensation: Int?
    public var maxTotalCompensation: Int?
    public var isUserEdited: Bool = false
    public var capturedAt: Date = Date()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var company: CompanyProfile?
    public var snapshot: CompanyResearchSnapshot?

    public init(
        id: UUID = UUID(),
        roleTitle: String,
        location: String,
        sourceName: String,
        sourceURLString: String? = nil,
        notes: String? = nil,
        confidenceNotes: String? = nil,
        currency: Currency = .usd,
        seniority: SeniorityBand? = nil,
        minBaseCompensation: Int? = nil,
        maxBaseCompensation: Int? = nil,
        minTotalCompensation: Int? = nil,
        maxTotalCompensation: Int? = nil,
        isUserEdited: Bool = false,
        capturedAt: Date = Date(),
        company: CompanyProfile? = nil,
        snapshot: CompanyResearchSnapshot? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.roleTitle = CompanyProfile.normalizedText(roleTitle) ?? roleTitle
        self.normalizedRoleTitle = CompanyProfile.normalizedRoleTitle(roleTitle)
        self.location = CompanyProfile.normalizedText(location) ?? location
        self.normalizedLocation = CompanyProfile.normalizedLocation(location)
        self.sourceName = CompanyProfile.normalizedText(sourceName) ?? sourceName
        self.sourceURLString = CompanyProfile.normalizedURLString(sourceURLString)
        self.notes = CompanyProfile.normalizedText(notes)
        self.confidenceNotes = CompanyProfile.normalizedText(confidenceNotes)
        self.currencyRawValue = currency.rawValue
        self.seniorityRawValue = seniority?.rawValue
        self.minBaseCompensation = minBaseCompensation
        self.maxBaseCompensation = maxBaseCompensation
        self.minTotalCompensation = minTotalCompensation
        self.maxTotalCompensation = maxTotalCompensation
        self.isUserEdited = isUserEdited
        self.capturedAt = capturedAt
        self.company = company
        self.snapshot = snapshot
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var currency: Currency {
        get { Currency(rawValue: currencyRawValue) ?? .usd }
        set {
            guard currencyRawValue != newValue.rawValue else { return }
            currencyRawValue = newValue.rawValue
            updateTimestamp()
        }
    }

    public var seniority: SeniorityBand? {
        get {
            guard let seniorityRawValue,
                  !seniorityRawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return SeniorityBand(rawValue: seniorityRawValue)
        }
        set {
            let newRawValue = newValue?.rawValue
            guard seniorityRawValue != newRawValue else { return }
            seniorityRawValue = newRawValue
            updateTimestamp()
        }
    }

    public var effectiveSeniority: SeniorityBand? {
        seniority ?? SeniorityBand.inferred(from: roleTitle)
    }

    public var baseRangeText: String? {
        currency.formatRange(min: minBaseCompensation, max: maxBaseCompensation)
    }

    public var totalRangeText: String? {
        currency.formatRange(min: minTotalCompensation, max: maxTotalCompensation)
    }

    public func update(
        roleTitle: String,
        location: String,
        sourceName: String,
        sourceURLString: String?,
        notes: String?,
        confidenceNotes: String?,
        currency: Currency,
        seniority: SeniorityBand?,
        minBaseCompensation: Int?,
        maxBaseCompensation: Int?,
        minTotalCompensation: Int?,
        maxTotalCompensation: Int?,
        isUserEdited: Bool
    ) {
        self.roleTitle = CompanyProfile.normalizedText(roleTitle) ?? self.roleTitle
        self.normalizedRoleTitle = CompanyProfile.normalizedRoleTitle(roleTitle)
        self.location = CompanyProfile.normalizedText(location) ?? self.location
        self.normalizedLocation = CompanyProfile.normalizedLocation(location)
        self.sourceName = CompanyProfile.normalizedText(sourceName) ?? self.sourceName
        self.sourceURLString = CompanyProfile.normalizedURLString(sourceURLString)
        self.notes = CompanyProfile.normalizedText(notes)
        self.confidenceNotes = CompanyProfile.normalizedText(confidenceNotes)
        self.currencyRawValue = currency.rawValue
        self.seniorityRawValue = seniority?.rawValue
        self.minBaseCompensation = minBaseCompensation
        self.maxBaseCompensation = maxBaseCompensation
        self.minTotalCompensation = minTotalCompensation
        self.maxTotalCompensation = maxTotalCompensation
        self.isUserEdited = isUserEdited
        updateTimestamp()
    }

    public func matches(roleTitle: String, location: String) -> Bool {
        let normalizedRole = CompanyProfile.normalizedRoleTitle(roleTitle)
        let normalizedLocation = CompanyProfile.normalizedLocation(location)

        if !normalizedRole.isEmpty, normalizedRoleTitle == normalizedRole {
            return normalizedLocation.isEmpty || self.normalizedLocation == normalizedLocation
        }

        if !normalizedLocation.isEmpty, self.normalizedLocation == normalizedLocation {
            return normalizedRole.isEmpty || normalizedRoleTitle.contains(normalizedRole) || normalizedRole.contains(normalizedRoleTitle)
        }

        return normalizedRoleTitle.contains(normalizedRole) || normalizedRole.contains(normalizedRoleTitle)
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }
}
