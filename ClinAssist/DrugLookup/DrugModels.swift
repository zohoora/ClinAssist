import Foundation

// MARK: - Drug Search Result

/// Represents a consolidated drug (grouped by generic name)
struct DrugProduct: Identifiable, Hashable {
    let id: String // Primary DIN or generic name
    let brandName: String
    let genericName: String
    let strength: String
    let dosageForm: String
    let manufacturer: String
    let therapeuticClass: String?
    let activeIngredients: [ActiveIngredient]
    
    // Coverage information (best coverage among variants)
    var odbCoverage: ODBCoverage?
    var nihbCoverage: NIHBCoverage?
    
    // All available variants (different strengths, manufacturers, DINs)
    var variants: [DrugVariant]
    
    init(id: String, brandName: String, genericName: String, strength: String, dosageForm: String, manufacturer: String, therapeuticClass: String?, activeIngredients: [ActiveIngredient], odbCoverage: ODBCoverage? = nil, nihbCoverage: NIHBCoverage? = nil, variants: [DrugVariant] = []) {
        self.id = id
        self.brandName = brandName
        self.genericName = genericName
        self.strength = strength
        self.dosageForm = dosageForm
        self.manufacturer = manufacturer
        self.therapeuticClass = therapeuticClass
        self.activeIngredients = activeIngredients
        self.odbCoverage = odbCoverage
        self.nihbCoverage = nihbCoverage
        self.variants = variants
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: DrugProduct, rhs: DrugProduct) -> Bool {
        lhs.id == rhs.id
    }
    
    /// Available strengths for this drug
    var availableStrengths: [String] {
        let strengths = Set(variants.compactMap { $0.strength }.filter { !$0.isEmpty })
        return Array(strengths).sorted()
    }
    
    /// Available manufacturers for this drug
    var availableManufacturers: [String] {
        let manufacturers = Set(variants.compactMap { $0.manufacturer }.filter { !$0.isEmpty })
        return Array(manufacturers).sorted()
    }
    
    /// Has any ODB coverage among variants
    var hasODBCoverage: Bool {
        odbCoverage?.isCovered == true || variants.contains { $0.odbCoverage?.isCovered == true }
    }
    
    /// Has any NIHB coverage among variants
    var hasNIHBCoverage: Bool {
        nihbCoverage?.isCovered == true || variants.contains { $0.nihbCoverage?.isCovered == true }
    }
}

// MARK: - Drug Variant

/// Represents a specific variant of a drug (specific DIN, strength, manufacturer)
struct DrugVariant: Identifiable, Hashable {
    let id: String // DIN
    let din: String
    let brandName: String
    let strength: String
    let dosageForm: String
    let manufacturer: String
    var odbCoverage: ODBCoverage?
    var nihbCoverage: NIHBCoverage?
    
    init(din: String, brandName: String, strength: String, dosageForm: String, manufacturer: String, odbCoverage: ODBCoverage? = nil, nihbCoverage: NIHBCoverage? = nil) {
        self.id = din
        self.din = din
        self.brandName = brandName
        self.strength = strength
        self.dosageForm = dosageForm
        self.manufacturer = manufacturer
        self.odbCoverage = odbCoverage
        self.nihbCoverage = nihbCoverage
    }
}

// MARK: - Active Ingredient

struct ActiveIngredient: Identifiable, Hashable {
    var id: String { "\(name)-\(strength)" }
    let name: String
    let strength: String
    let strengthUnit: String
}

// MARK: - ODB Coverage

struct ODBCoverage: Hashable {
    let din: String
    let isCovered: Bool
    let isLimitedUse: Bool
    let limitedUseCodes: [String] // sec3b, sec3c, sec6, etc.
    let limitedUseCriteria: [LimitedUseCriterion] // Actual criteria from ODB formulary
    let price: String?
    let listingDate: String?
    
    init(din: String, isCovered: Bool, isLimitedUse: Bool, limitedUseCodes: [String], limitedUseCriteria: [LimitedUseCriterion] = [], price: String?, listingDate: String?) {
        self.din = din
        self.isCovered = isCovered
        self.isLimitedUse = isLimitedUse
        self.limitedUseCodes = limitedUseCodes
        self.limitedUseCriteria = limitedUseCriteria
        self.price = price
        self.listingDate = listingDate
    }
    
    var statusDescription: String {
        if !isCovered {
            return "Not Covered"
        } else if isLimitedUse {
            let codes = limitedUseCodes.joined(separator: ", ")
            return "Limited Use (\(codes))"
        } else {
            return "General Benefit"
        }
    }
    
    var statusColor: CoverageStatusColor {
        if !isCovered {
            return .notCovered
        } else if isLimitedUse {
            return .limitedUse
        } else {
            return .covered
        }
    }
}

// MARK: - Limited Use Criterion

/// Represents a Limited Use criterion from the ODB formulary
struct LimitedUseCriterion: Hashable, Identifiable {
    var id: String { "\(reasonForUseId ?? "note")-\(sequence)" }
    let sequence: Int
    let reasonForUseId: String?
    let criteria: String
    let authorizationPeriod: String?
    let isAuthPeriodNote: Bool // true if this is just an authorization period note (type="R")
}

// MARK: - NIHB Coverage

struct NIHBCoverage: Hashable {
    let din: String
    let chemicalName: String
    let itemName: String
    let ahfsCode: String
    let ahfsDescription: String
    let ontarioStatus: String // "Open Benefit", "Limited Use", "Not Determined"
    let manufacturer: String
    
    var isCovered: Bool {
        ontarioStatus == "Open Benefit" || ontarioStatus == "Limited Use"
    }
    
    var isLimitedUse: Bool {
        ontarioStatus == "Limited Use"
    }
    
    var statusDescription: String {
        ontarioStatus
    }
    
    var statusColor: CoverageStatusColor {
        switch ontarioStatus {
        case "Open Benefit":
            return .covered
        case "Limited Use":
            return .limitedUse
        case "Not Determined":
            return .notDetermined
        default:
            return .notCovered
        }
    }
}

// MARK: - Coverage Status Color

enum CoverageStatusColor {
    case covered
    case limitedUse
    case notCovered
    case notDetermined
}

// MARK: - Health Canada DPD API Response Models

struct DPDDrugProduct: Codable {
    let drugCode: Int
    let className: String?
    let drugIdentificationNumber: String?
    let brandName: String?
    let descriptor: String?
    let aiGroupNo: String?
    let companyName: String?
    let lastUpdate: String?
    
    enum CodingKeys: String, CodingKey {
        case drugCode = "drug_code"
        case className = "class_name"
        case drugIdentificationNumber = "drug_identification_number"
        case brandName = "brand_name"
        case descriptor
        case aiGroupNo = "ai_group_no"
        case companyName = "company_name"
        case lastUpdate = "last_update_date"
    }
}

struct DPDActiveIngredient: Codable {
    let drugCode: Int
    let ingredientName: String
    let strength: String
    let strengthUnit: String
    let dosageValue: String?
    let dosageUnit: String?
    
    enum CodingKeys: String, CodingKey {
        case drugCode = "drug_code"
        case ingredientName = "ingredient_name"
        case strength
        case strengthUnit = "strength_unit"
        case dosageValue = "dosage_value"
        case dosageUnit = "dosage_unit"
    }
}

struct DPDDosageForm: Codable {
    let drugCode: Int
    let pharmaceuticalForm: String
    
    enum CodingKeys: String, CodingKey {
        case drugCode = "drug_code"
        case pharmaceuticalForm = "pharmaceutical_form"
    }
}

struct DPDRoute: Codable {
    let drugCode: Int
    let routeOfAdministration: String
    
    enum CodingKeys: String, CodingKey {
        case drugCode = "drug_code"
        case routeOfAdministration = "route_of_administration"
    }
}

struct DPDTherapeuticClass: Codable {
    let drugCode: Int
    let tcAtc: String?
    let tcAtcNumber: String?
    
    enum CodingKeys: String, CodingKey {
        case drugCode = "drug_code"
        case tcAtc = "tc_atc"
        case tcAtcNumber = "tc_atc_number"
    }
}

struct DPDCompany: Codable {
    let drugCode: Int
    let companyName: String
    let companyCode: String?
    
    enum CodingKeys: String, CodingKey {
        case drugCode = "drug_code"
        case companyName = "company_name"
        case companyCode = "company_code"
    }
}

struct DPDStatus: Codable {
    let drugCode: Int
    let status: String
    let historyDate: String?
    
    enum CodingKeys: String, CodingKey {
        case drugCode = "drug_code"
        case status
        case historyDate = "history_date"
    }
}

// MARK: - Search Query

struct DrugSearchQuery {
    let searchText: String
    let searchType: SearchType
    
    enum SearchType {
        case brandName
        case genericName
        case din
        case any
    }
}

// MARK: - Search Result

struct DrugSearchResult {
    let query: String
    let products: [DrugProduct]
    let timestamp: Date
    let source: DataSource
    
    enum DataSource {
        case healthCanada
        case odb
        case nihb
        case combined
    }
}

