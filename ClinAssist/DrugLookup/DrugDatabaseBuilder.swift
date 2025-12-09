import Foundation

/// Builds and updates the local drug database from various sources
/// - Health Canada Drug Product Database (DPD) API
/// - Ontario Drug Benefit (ODB) Formulary XML
/// - NIHB Drug Benefit List CSV
@MainActor
class DrugDatabaseBuilder: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isBuilding: Bool = false
    @Published var currentPhase: BuildPhase = .idle
    @Published var progress: Double = 0.0 // 0.0 to 1.0
    @Published var statusMessage: String = ""
    @Published var errorMessage: String?
    
    // Statistics
    @Published var drugsProcessed: Int = 0
    @Published var variantsProcessed: Int = 0
    
    enum BuildPhase: String {
        case idle = "Idle"
        case fetchingDPD = "Fetching Health Canada drugs..."
        case processingODB = "Processing ODB formulary..."
        case processingNIHB = "Processing NIHB formulary..."
        case consolidating = "Consolidating data..."
        case writingDatabase = "Writing database..."
        case complete = "Complete"
        case error = "Error"
    }
    
    // MARK: - Private Properties
    
    private let database: DrugDatabase
    private let dpdClient = HealthCanadaDPDClient()
    private let odbManager = ODBFormularyManager.shared
    private let nihbManager = NIHBFormularyManager.shared
    
    // Data containers during build
    private var drugsByGeneric: [String: DrugBuildData] = [:]
    
    // Track DINs we've seen
    private var processedDINs: Set<String> = []
    
    init(database: DrugDatabase = .shared) {
        self.database = database
    }
    
    // MARK: - Build Process
    
    /// Build or rebuild the entire drug database
    func buildDatabase() async {
        guard !isBuilding else { return }
        
        isBuilding = true
        errorMessage = nil
        drugsProcessed = 0
        variantsProcessed = 0
        drugsByGeneric = [:]
        processedDINs = []
        
        do {
            // Phase 1: Fetch Health Canada DPD data
            currentPhase = .fetchingDPD
            progress = 0.0
            try await fetchHealthCanadaData()
            
            // Phase 2: Process ODB formulary
            currentPhase = .processingODB
            progress = 0.4
            await processODBFormulary()
            
            // Phase 3: Process NIHB formulary  
            currentPhase = .processingNIHB
            progress = 0.6
            await processNIHBFormulary()
            
            // Phase 4: Write to database
            currentPhase = .writingDatabase
            progress = 0.8
            await writeToDatabase()
            
            // Complete
            currentPhase = .complete
            progress = 1.0
            statusMessage = "Database updated: \(drugsProcessed) drugs, \(variantsProcessed) variants"
            
            debugLog("✅ Database build complete: \(drugsProcessed) drugs, \(variantsProcessed) variants", component: "DBBuilder")
            
        } catch {
            currentPhase = .error
            errorMessage = error.localizedDescription
            debugLog("❌ Database build failed: \(error)", component: "DBBuilder")
        }
        
        isBuilding = false
    }
    
    // MARK: - Phase 1: Health Canada DPD
    
    private func fetchHealthCanadaData() async throws {
        statusMessage = "Fetching drug list from Health Canada..."
        
        // Fetch all active drug products from DPD
        // The API has pagination, so we need to fetch all pages
        var allProducts: [DPDDrugProduct] = []
        var page = 1
        let pageSize = 5000  // Max allowed by API
        var hasMore = true
        
        while hasMore {
            statusMessage = "Fetching Health Canada drugs (page \(page))..."
            
            let products = try await fetchDPDPage(page: page, pageSize: pageSize)
            allProducts.append(contentsOf: products)
            
            // Update progress (estimate 5 pages max)
            progress = min(0.35, Double(page) * 0.07)
            
            hasMore = products.count == pageSize
            page += 1
            
            // Brief delay to avoid rate limiting
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        statusMessage = "Processing \(allProducts.count) Health Canada products..."
        debugLog("📦 Fetched \(allProducts.count) products from Health Canada", component: "DBBuilder")
        
        // Process each product
        for (index, product) in allProducts.enumerated() {
            await processHealthCanadaProduct(product)
            
            if index % 1000 == 0 {
                statusMessage = "Processing Health Canada drugs... \(index)/\(allProducts.count)"
                progress = 0.35 + (Double(index) / Double(allProducts.count)) * 0.05
            }
        }
    }
    
    private func fetchDPDPage(page: Int, pageSize: Int) async throws -> [DPDDrugProduct] {
        let offset = (page - 1) * pageSize
        let urlString = "https://health-products.canada.ca/api/drug/drugproduct/?lang=en&type=json&status=1&offset=\(offset)&limit=\(pageSize)"
        
        guard let url = URL(string: urlString) else {
            throw BuildError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BuildError.apiError("Failed to fetch DPD data")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode([DPDDrugProduct].self, from: data)
    }
    
    private func processHealthCanadaProduct(_ product: DPDDrugProduct) async {
        guard let din = product.drugIdentificationNumber, !din.isEmpty else { return }
        guard !processedDINs.contains(din) else { return }
        
        processedDINs.insert(din)
        
        // Extract generic name from brand name
        let brandName = product.brandName ?? "Unknown"
        let genericName = extractGenericName(from: brandName).uppercased()
        
        // Get or create drug entry
        if drugsByGeneric[genericName] == nil {
            drugsByGeneric[genericName] = DrugBuildData(
                genericName: genericName,
                therapeuticClass: nil,
                atcCode: nil
            )
        }
        
        // Add variant
        let variant = VariantBuildData(
            din: din,
            brandName: brandName,
            strength: "",
            strengthValue: nil,
            strengthUnit: nil,
            dosageForm: "",
            route: nil,
            manufacturer: product.companyName ?? ""
        )
        
        drugsByGeneric[genericName]?.variants.append(variant)
        variantsProcessed += 1
    }
    
    // MARK: - Phase 2: ODB Formulary
    
    private func processODBFormulary() async {
        statusMessage = "Loading ODB formulary data..."
        
        // Ensure ODB data is loaded
        odbManager.loadData()
        
        let odbDrugs = odbManager.getAllCoverage()
        statusMessage = "Processing \(odbDrugs.count) ODB entries..."
        
        for (index, odb) in odbDrugs.enumerated() {
            processODBEntry(odb)
            
            if index % 500 == 0 {
                progress = 0.4 + (Double(index) / Double(odbDrugs.count)) * 0.2
            }
        }
        
        debugLog("📦 Processed \(odbDrugs.count) ODB entries", component: "DBBuilder")
    }
    
    private func processODBEntry(_ odb: ODBCoverage) {
        let din = odb.din
        
        // Try to find existing drug by DIN
        var foundGeneric: String?
        
        for (genericName, drug) in drugsByGeneric {
            if drug.variants.contains(where: { $0.din == din }) {
                foundGeneric = genericName
                break
            }
        }
        
        if let genericName = foundGeneric {
            // Update existing variant with ODB coverage
            if let variantIndex = drugsByGeneric[genericName]?.variants.firstIndex(where: { $0.din == din }) {
                drugsByGeneric[genericName]?.variants[variantIndex].odbCovered = odb.isCovered
                drugsByGeneric[genericName]?.variants[variantIndex].odbLimitedUse = odb.isLimitedUse
                drugsByGeneric[genericName]?.variants[variantIndex].odbLuCodes = odb.limitedUseCodes.joined(separator: ",")
            }
        } else if !processedDINs.contains(din) {
            // New drug not in Health Canada data - try to get info from NIHB
            processedDINs.insert(din)
            
            if let nihb = nihbManager.getCoverage(din: din) {
                let genericName = nihb.chemicalName.uppercased()
                
                if drugsByGeneric[genericName] == nil {
                    drugsByGeneric[genericName] = DrugBuildData(
                        genericName: genericName,
                        therapeuticClass: nihb.ahfsDescription,
                        atcCode: nil
                    )
                }
                
                var variant = VariantBuildData(
                    din: din,
                    brandName: nihb.itemName,
                    strength: "",
                    strengthValue: nil,
                    strengthUnit: nil,
                    dosageForm: "",
                    route: nil,
                    manufacturer: nihb.manufacturer
                )
                variant.odbCovered = odb.isCovered
                variant.odbLimitedUse = odb.isLimitedUse
                variant.odbLuCodes = odb.limitedUseCodes.joined(separator: ",")
                
                drugsByGeneric[genericName]?.variants.append(variant)
                variantsProcessed += 1
            }
        }
    }
    
    // MARK: - Phase 3: NIHB Formulary
    
    private func processNIHBFormulary() async {
        statusMessage = "Loading NIHB formulary data..."
        
        // Ensure NIHB data is loaded
        nihbManager.loadData()
        
        let nihbDrugs = nihbManager.getAllCoverage()
        statusMessage = "Processing \(nihbDrugs.count) NIHB entries..."
        
        for (index, nihb) in nihbDrugs.enumerated() {
            processNIHBEntry(nihb)
            
            if index % 500 == 0 {
                progress = 0.6 + (Double(index) / Double(nihbDrugs.count)) * 0.2
            }
        }
        
        debugLog("📦 Processed \(nihbDrugs.count) NIHB entries", component: "DBBuilder")
    }
    
    private func processNIHBEntry(_ nihb: NIHBCoverage) {
        let din = nihb.din
        let genericName = nihb.chemicalName.uppercased()
        
        // Try to find existing drug by DIN or generic name
        var foundGeneric: String?
        
        for (existingGeneric, drug) in drugsByGeneric {
            if drug.variants.contains(where: { $0.din == din }) || existingGeneric == genericName {
                foundGeneric = existingGeneric
                break
            }
        }
        
        if let existingGeneric = foundGeneric {
            // Update existing variant with NIHB coverage
            if let variantIndex = drugsByGeneric[existingGeneric]?.variants.firstIndex(where: { $0.din == din }) {
                drugsByGeneric[existingGeneric]?.variants[variantIndex].nihbCovered = nihb.isCovered
                drugsByGeneric[existingGeneric]?.variants[variantIndex].nihbLimitedUse = nihb.isLimitedUse
                drugsByGeneric[existingGeneric]?.variants[variantIndex].nihbStatus = nihb.ontarioStatus
            } else {
                // DIN not found but generic name matches - add as new variant
                var variant = VariantBuildData(
                    din: din,
                    brandName: nihb.itemName,
                    strength: "",
                    strengthValue: nil,
                    strengthUnit: nil,
                    dosageForm: "",
                    route: nil,
                    manufacturer: nihb.manufacturer
                )
                variant.nihbCovered = nihb.isCovered
                variant.nihbLimitedUse = nihb.isLimitedUse
                variant.nihbStatus = nihb.ontarioStatus
                
                drugsByGeneric[existingGeneric]?.variants.append(variant)
                variantsProcessed += 1
                processedDINs.insert(din)
            }
            
            // Update therapeutic class if not set
            if drugsByGeneric[existingGeneric]?.therapeuticClass == nil && !nihb.ahfsDescription.isEmpty {
                drugsByGeneric[existingGeneric]?.therapeuticClass = nihb.ahfsDescription
            }
        } else if !processedDINs.contains(din) {
            // Completely new drug
            processedDINs.insert(din)
            
            if drugsByGeneric[genericName] == nil {
                drugsByGeneric[genericName] = DrugBuildData(
                    genericName: genericName,
                    therapeuticClass: nihb.ahfsDescription,
                    atcCode: nil
                )
            }
            
            var variant = VariantBuildData(
                din: din,
                brandName: nihb.itemName,
                strength: "",
                strengthValue: nil,
                strengthUnit: nil,
                dosageForm: "",
                route: nil,
                manufacturer: nihb.manufacturer
            )
            variant.nihbCovered = nihb.isCovered
            variant.nihbLimitedUse = nihb.isLimitedUse
            variant.nihbStatus = nihb.ontarioStatus
            
            drugsByGeneric[genericName]?.variants.append(variant)
            variantsProcessed += 1
        }
    }
    
    // MARK: - Phase 4: Write Database
    
    private func writeToDatabase() async {
        statusMessage = "Creating database schema..."
        
        // Drop and recreate tables
        database.dropAllTables()
        database.createSchema()
        
        statusMessage = "Writing drug data..."
        
        database.beginTransaction()
        
        let drugs = Array(drugsByGeneric.values)
        for (index, drug) in drugs.enumerated() {
            // Insert drug
            guard let drugId = database.insertDrug(
                genericName: drug.genericName,
                therapeuticClass: drug.therapeuticClass,
                atcCode: drug.atcCode
            ) else {
                continue
            }
            
            drugsProcessed += 1
            
            // Insert variants
            for variant in drug.variants {
                database.insertVariant(
                    drugId: drugId,
                    din: variant.din,
                    brandName: variant.brandName,
                    strength: variant.strength.isEmpty ? nil : variant.strength,
                    strengthValue: variant.strengthValue,
                    strengthUnit: variant.strengthUnit,
                    dosageForm: variant.dosageForm.isEmpty ? nil : variant.dosageForm,
                    route: variant.route,
                    manufacturer: variant.manufacturer.isEmpty ? nil : variant.manufacturer,
                    odbCovered: variant.odbCovered,
                    odbLimitedUse: variant.odbLimitedUse,
                    odbLuCodes: variant.odbLuCodes,
                    odbPrice: nil,
                    nihbCovered: variant.nihbCovered,
                    nihbLimitedUse: variant.nihbLimitedUse,
                    nihbStatus: variant.nihbStatus
                )
            }
            
            if index % 500 == 0 {
                statusMessage = "Writing drugs... \(index)/\(drugs.count)"
                progress = 0.8 + (Double(index) / Double(drugs.count)) * 0.2
            }
        }
        
        database.commitTransaction()
        
        // Set metadata
        let now = ISO8601DateFormatter().string(from: Date())
        database.setMetadata(key: "last_update", value: now)
        database.setMetadata(key: "drug_count", value: String(drugsProcessed))
        database.setMetadata(key: "variant_count", value: String(variantsProcessed))
        
        debugLog("✅ Database written: \(drugsProcessed) drugs, \(variantsProcessed) variants", component: "DBBuilder")
    }
    
    // MARK: - Helpers
    
    /// Extract the generic ingredient name from a brand name
    private func extractGenericName(from brandName: String) -> String {
        let name = brandName.uppercased()
        
        // Common manufacturer prefixes that appear before a hyphen
        let hyphenPrefixes = ["APO", "TEVA", "ACH", "AURO", "BIO", "JAMP", "MAR", "MINT", "NAT", "NRA", "RIVA", "SANDOZ", "TARO", "PRO", "AG", "NB", "M", "PMS", "RATIO", "NOVO", "MYLAN", "ACT", "DOM", "CO", "RAN", "ZYM", "SANIS", "PHARMASCIENCE", "SIVEM"]
        
        // Check for MANUFACTURER-DRUGNAME pattern
        if let hyphenIndex = name.firstIndex(of: "-") {
            let prefix = String(name[..<hyphenIndex])
            if hyphenPrefixes.contains(prefix) {
                let afterHyphen = String(name[name.index(after: hyphenIndex)...])
                return afterHyphen.trimmingCharacters(in: .whitespaces)
            }
        }
        
        // Common manufacturer prefixes that appear before a space
        let spacePrefixes = ["JAMP", "RIVA", "SANDOZ", "MINT", "MAR", "TARO", "RATIO", "NOVO"]
        
        // Check for MANUFACTURER DRUGNAME pattern
        let words = name.split(separator: " ").map { String($0) }
        if words.count >= 2 {
            if spacePrefixes.contains(words[0]) {
                // Remove manufacturer prefix and suffixes
                let suffixesToRemove = ["SDZ", "TABLET", "TAB", "TABLETS", "CAPS", "CAPSULE", "CAPSULES", "INJ", "INJECTION", "SOLN", "SOLUTION", "SUSP", "SUSPENSION"]
                var drugWords = Array(words.dropFirst())
                drugWords = drugWords.filter { !suffixesToRemove.contains($0) }
                if !drugWords.isEmpty {
                    return drugWords.joined(separator: " ")
                }
            }
        }
        
        // No recognized pattern, return as-is but remove common suffixes
        let suffixesToRemove = [" SDZ", " TABLET", " TAB", " TABLETS", " CAPS", " CAPSULE", " CAPSULES", " INJ", " INJECTION"]
        var cleaned = name
        for suffix in suffixesToRemove {
            if cleaned.hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count))
            }
        }
        
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Build Data Structures

private struct DrugBuildData {
    var genericName: String
    var therapeuticClass: String?
    var atcCode: String?
    var variants: [VariantBuildData] = []
}

private struct VariantBuildData {
    var din: String
    var brandName: String
    var strength: String
    var strengthValue: Double?
    var strengthUnit: String?
    var dosageForm: String
    var route: String?
    var manufacturer: String
    var odbCovered: Bool = false
    var odbLimitedUse: Bool = false
    var odbLuCodes: String?
    var nihbCovered: Bool = false
    var nihbLimitedUse: Bool = false
    var nihbStatus: String?
}

// MARK: - Build Errors

enum BuildError: Error, LocalizedError {
    case invalidURL
    case apiError(String)
    case databaseError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .apiError(let message):
            return "API Error: \(message)"
        case .databaseError(let message):
            return "Database Error: \(message)"
        }
    }
}

