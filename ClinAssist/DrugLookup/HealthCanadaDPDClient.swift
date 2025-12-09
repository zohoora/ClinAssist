import Foundation

/// Client for Health Canada's Drug Product Database (DPD) API
/// API Documentation: https://health-products.canada.ca/api/documentation/dpd-documentation-en.html
class HealthCanadaDPDClient {
    
    private let baseURL = "https://health-products.canada.ca/api/drug"
    private let session: URLSession
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    // MARK: - Public API
    
    /// Search for drugs by brand name
    func searchByBrandName(_ name: String) async throws -> [DPDDrugProduct] {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let url = "\(baseURL)/drugproduct/?brandname=\(encodedName)&lang=en&type=json"
        return try await fetchArray(from: url)
    }
    
    /// Search for drugs by active ingredient name
    func searchByIngredient(_ ingredientName: String) async throws -> [DPDActiveIngredient] {
        let encodedName = ingredientName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ingredientName
        let url = "\(baseURL)/activeingredient/?ingredientname=\(encodedName)&lang=en&type=json"
        return try await fetchArray(from: url)
    }
    
    /// Get drug product by DIN (Drug Identification Number)
    func getByDIN(_ din: String) async throws -> [DPDDrugProduct] {
        let url = "\(baseURL)/drugproduct/?din=\(din)&lang=en&type=json"
        return try await fetchArray(from: url)
    }
    
    /// Get active ingredients for a specific drug code
    func getActiveIngredients(drugCode: Int) async throws -> [DPDActiveIngredient] {
        let url = "\(baseURL)/activeingredient/?id=\(drugCode)&lang=en&type=json"
        return try await fetchArray(from: url)
    }
    
    /// Get dosage forms for a specific drug code
    func getDosageForms(drugCode: Int) async throws -> [DPDDosageForm] {
        let url = "\(baseURL)/form/?id=\(drugCode)&lang=en&type=json"
        return try await fetchArray(from: url)
    }
    
    /// Get routes of administration for a specific drug code
    func getRoutes(drugCode: Int) async throws -> [DPDRoute] {
        let url = "\(baseURL)/route/?id=\(drugCode)&lang=en&type=json"
        return try await fetchArray(from: url)
    }
    
    /// Get therapeutic class for a specific drug code
    func getTherapeuticClass(drugCode: Int) async throws -> [DPDTherapeuticClass] {
        let url = "\(baseURL)/therapeuticclass/?id=\(drugCode)&lang=en&type=json"
        return try await fetchArray(from: url)
    }
    
    /// Get company info for a specific drug code
    func getCompany(drugCode: Int) async throws -> [DPDCompany] {
        let url = "\(baseURL)/company/?id=\(drugCode)&lang=en&type=json"
        return try await fetchArray(from: url)
    }
    
    /// Get product status for a specific drug code
    func getStatus(drugCode: Int) async throws -> [DPDStatus] {
        let url = "\(baseURL)/status/?id=\(drugCode)&lang=en&type=json"
        return try await fetchArray(from: url)
    }
    
    // MARK: - Comprehensive Search
    
    /// Search and return DrugProduct objects (basic info only for speed)
    func searchDrugs(query: String) async throws -> [DrugProduct] {
        debugLog("Searching DPD for: \(query)", component: "DPD")
        
        // Try searching by brand name first
        var products = try await searchByBrandName(query)
        
        // If no results, try searching by ingredient
        if products.isEmpty {
            let ingredients = try await searchByIngredient(query)
            let drugCodes = Set(ingredients.map { $0.drugCode })
            
            // Fetch drug products for each unique drug code (limit to 10)
            for drugCode in drugCodes.prefix(10) {
                if let product = try? await getDrugProductByCode(drugCode) {
                    products.append(product)
                }
            }
        }
        
        // Convert to basic DrugProduct objects (no additional API calls for speed)
        let results = products.prefix(30).map { dpdProduct in
            let din = dpdProduct.drugIdentificationNumber ?? String(dpdProduct.drugCode)
            return DrugProduct(
                id: din,
                brandName: dpdProduct.brandName ?? "Unknown",
                genericName: dpdProduct.brandName ?? "Unknown", // Will be updated when selected
                strength: "",
                dosageForm: "",
                manufacturer: dpdProduct.companyName ?? "Unknown",
                therapeuticClass: nil,
                activeIngredients: [],
                odbCoverage: nil,
                nihbCoverage: nil,
                variants: []
            )
        }
        
        debugLog("Found \(results.count) drugs from DPD", component: "DPD")
        return Array(results)
    }
    
    /// Get full details for a single drug (called when user selects a drug)
    func getFullDrugDetails(din: String) async throws -> DrugProduct? {
        let products = try await getByDIN(din)
        guard let dpdProduct = products.first else { return nil }
        return try await buildDrugProduct(from: dpdProduct)
    }
    
    /// Get a single drug product by drug code
    private func getDrugProductByCode(_ drugCode: Int) async throws -> DPDDrugProduct? {
        let url = "\(baseURL)/drugproduct/?id=\(drugCode)&lang=en&type=json"
        let products: [DPDDrugProduct] = try await fetchArray(from: url)
        return products.first
    }
    
    /// Build a complete DrugProduct from DPD data
    private func buildDrugProduct(from dpdProduct: DPDDrugProduct) async throws -> DrugProduct {
        let drugCode = dpdProduct.drugCode
        
        // Fetch additional details in parallel
        async let ingredientsTask = getActiveIngredients(drugCode: drugCode)
        async let formsTask = getDosageForms(drugCode: drugCode)
        async let therapeuticTask = getTherapeuticClass(drugCode: drugCode)
        async let companyTask = getCompany(drugCode: drugCode)
        
        let ingredients = (try? await ingredientsTask) ?? []
        let forms = (try? await formsTask) ?? []
        let therapeutic = (try? await therapeuticTask) ?? []
        let companies = (try? await companyTask) ?? []
        
        // Build active ingredients list
        let activeIngredients = ingredients.map { ingredient in
            ActiveIngredient(
                name: ingredient.ingredientName,
                strength: ingredient.strength,
                strengthUnit: ingredient.strengthUnit
            )
        }
        
        // Build strength string from ingredients
        let strengthString = ingredients.map { "\($0.strength) \($0.strengthUnit)" }.joined(separator: " / ")
        
        // Get generic name from first ingredient or use brand name
        let genericName = ingredients.first?.ingredientName ?? dpdProduct.brandName ?? "Unknown"
        
        let din = dpdProduct.drugIdentificationNumber ?? String(drugCode)
        return DrugProduct(
            id: din,
            brandName: dpdProduct.brandName ?? "Unknown",
            genericName: genericName,
            strength: strengthString.isEmpty ? "N/A" : strengthString,
            dosageForm: forms.first?.pharmaceuticalForm ?? "N/A",
            manufacturer: companies.first?.companyName ?? dpdProduct.companyName ?? "Unknown",
            therapeuticClass: therapeutic.first?.tcAtc,
            activeIngredients: activeIngredients,
            odbCoverage: nil,
            nihbCoverage: nil,
            variants: []
        )
    }
    
    // MARK: - Network Helpers
    
    private func fetchArray<T: Decodable>(from urlString: String, retryCount: Int = 0) async throws -> [T] {
        guard let url = URL(string: urlString) else {
            throw DPDError.invalidURL
        }
        
        var request = URLRequest(url: url)
        // Health Canada API can be very slow - use 60s timeout
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DPDError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw DPDError.httpError(statusCode: httpResponse.statusCode)
            }
            
            // Handle empty response
            if data.isEmpty {
                return []
            }
            
            do {
                let decoder = JSONDecoder()
                return try decoder.decode([T].self, from: data)
            } catch {
                // API sometimes returns empty object {} instead of empty array
                if let jsonString = String(data: data, encoding: .utf8),
                   jsonString.trimmingCharacters(in: .whitespacesAndNewlines) == "{}" {
                    return []
                }
                debugLog("DPD decode error: \(error)", component: "DPD")
                throw DPDError.decodingError(error)
            }
        } catch let error as URLError where error.code == .timedOut && retryCount < 1 {
            // Retry once on timeout
            debugLog("DPD request timed out, retrying... (attempt \(retryCount + 2))", component: "DPD")
            return try await fetchArray(from: urlString, retryCount: retryCount + 1)
        }
    }
}

// MARK: - Errors

enum DPDError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
    case noResults
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from Health Canada API"
        case .httpError(let statusCode):
            return "HTTP error \(statusCode) from Health Canada API"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .noResults:
            return "No results found"
        }
    }
}

