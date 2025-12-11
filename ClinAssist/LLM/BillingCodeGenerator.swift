import Foundation

/// Generates billing and diagnostic codes using LLM analysis of SOAP notes
@MainActor
class BillingCodeGenerator: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isGenerating: Bool = false
    @Published var suggestedCodes: BillingSuggestion?
    @Published var error: String?
    
    // MARK: - Dependencies
    
    private var diagnosticCodes: [DiagnosticCode] = []
    private var comprehensiveBillingData: ComprehensiveBillingData?
    
    // MARK: - Initialization
    
    init() {
        loadReferenceData()
    }
    
    // Legacy init for compatibility
    init(llmProvider: LLMProvider) {
        loadReferenceData()
    }
    
    // MARK: - Reference Data Loading
    
    private func loadReferenceData() {
        // Load diagnostic codes
        if let url = Bundle.main.url(forResource: "moh-diagnostic-codes", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            diagnosticCodes = (try? JSONDecoder().decode([DiagnosticCode].self, from: data)) ?? []
            debugLog("Loaded \(diagnosticCodes.count) diagnostic codes", component: "Billing")
        } else {
            debugLog("⚠️ Could not load diagnostic codes from bundle", component: "Billing")
        }
        
        // Load comprehensive billing codes (new format with 759 codes)
        if let url = Bundle.main.url(forResource: "moh-billing-codes-comprehensive", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            comprehensiveBillingData = try? JSONDecoder().decode(ComprehensiveBillingData.self, from: data)
            debugLog("Loaded \(comprehensiveBillingData?.billingCodes.count ?? 0) comprehensive billing codes", component: "Billing")
        } else {
            debugLog("⚠️ Could not load comprehensive billing codes from bundle", component: "Billing")
        }
    }
    
    // MARK: - Code Generation
    
    /// Generate billing suggestions from a SOAP note
    func generateCodes(from soapNote: String, encounterDuration: TimeInterval? = nil) async {
        guard !soapNote.isEmpty else {
            error = "No SOAP note provided"
            return
        }
        
        isGenerating = true
        error = nil
        
        do {
            let prompt = buildPrompt(soapNote: soapNote, duration: encounterDuration)
            let response = try await callLLM(systemPrompt: billingSystemPrompt, userContent: prompt)
            
            // Parse the LLM response
            if let suggestion = parseLLMResponse(response) {
                suggestedCodes = suggestion
            } else {
                error = "Could not parse billing suggestions"
            }
        } catch {
            self.error = "Failed to generate codes: \(error.localizedDescription)"
            debugLog("❌ Billing code generation failed: \(error)", component: "Billing")
        }
        
        isGenerating = false
    }
    
    /// Call the configured LLM for billing code generation
    private func callLLM(systemPrompt: String, userContent: String) async throws -> String {
        guard let config = ConfigManager.shared.config else {
            throw BillingError.noConfig
        }
        
        // Get the configured model for billing
        let model = ConfigManager.shared.getModel(for: .billing, scenario: .standard)
        debugLog("💰 Billing using model: \(model.displayName)", component: "Billing")
        
        // Determine API endpoint based on provider
        let url: URL
        var headers: [String: String] = [:]
        var requestBody: [String: Any]
        
        switch model.provider {
        case .groq:
            guard let groqConfig = config.groq, !groqConfig.apiKey.isEmpty else {
                throw BillingError.noApiKey
            }
            url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
            headers["Authorization"] = "Bearer \(groqConfig.apiKey)"
            headers["Content-Type"] = "application/json"
            
        case .openRouter:
            url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
            headers["Authorization"] = "Bearer \(config.openrouterApiKey)"
            headers["Content-Type"] = "application/json"
            headers["HTTP-Referer"] = "https://clinassist.local"
            headers["X-Title"] = "ClinAssist"
            
        case .ollama:
            let baseURL = config.ollama?.baseUrl ?? "http://localhost:11434"
            url = URL(string: "\(baseURL)/api/chat")!
            headers["Content-Type"] = "application/json"
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.timeoutInterval = 120
        
        // Build request body based on provider
        if model.provider == .ollama {
            requestBody = [
                "model": model.modelId,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userContent]
                ],
                "stream": false
            ]
        } else {
            requestBody = [
                "model": model.modelId,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userContent]
                ],
                "temperature": 0.3,
                "max_tokens": 4096
            ]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BillingError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            debugLog("❌ Billing API error: HTTP \(httpResponse.statusCode): \(errorText)", component: "Billing")
            throw BillingError.apiError(httpResponse.statusCode)
        }
        
        // Parse response based on provider
        if model.provider == .ollama {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw BillingError.invalidResponse
            }
            return content
        } else {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw BillingError.invalidResponse
            }
            return content
        }
    }
    
    enum BillingError: Error, LocalizedError {
        case noConfig
        case noApiKey
        case invalidResponse
        case apiError(Int)
        
        var errorDescription: String? {
            switch self {
            case .noConfig: return "No configuration found"
            case .noApiKey: return "API key not configured"
            case .invalidResponse: return "Invalid response from server"
            case .apiError(let code): return "API error (status: \(code))"
            }
        }
    }
    
    // MARK: - Prompt Building
    
    private var billingSystemPrompt: String {
        """
        You are an expert medical billing assistant for Ontario, Canada. You help family physicians in FHO (Family Health Organization) practices determine appropriate OHIP diagnostic codes and billing codes.

        CONTEXT:
        - Practice Type: FHO (Family Health Organization) - Outpatient
        - Physician: General Practitioner / Family Physician
        - All patients are rostered
        - Province: Ontario, Canada

        Your task is to analyze SOAP notes and suggest:
        1. The most appropriate MOH 3-digit diagnostic code(s)
        2. The most appropriate OHIP billing code(s) that can be billed together

        IMPORTANT RULES:
        - Only suggest codes that are compatible and can be billed together
        - For FHO practices, most A-codes are still billable for rostered patients
        - Consider visit duration when suggesting consultation vs assessment codes
        - A004 (General re-assessment) is limited to 2 per 12 months per patient
        - Special/Comprehensive consultations (A911/A912) require documented start/stop times
        
        Always respond in the exact JSON format specified.
        """
    }
    
    private func buildPrompt(soapNote: String, duration: TimeInterval?) -> String {
        // Build diagnostic code reference (subset for context window efficiency)
        let relevantDxCodes = getRelevantDiagnosticCodes(for: soapNote)
        let dxReference = relevantDxCodes.map { "\($0.code): \($0.description)" }.joined(separator: "\n")
        
        // Build billing code reference from comprehensive data
        let relevantBillingCodes = getRelevantBillingCodes(for: soapNote)
        let billingReference = relevantBillingCodes.map { (code, data) in
            var entry = "\(code): \(data.description) ($\(String(format: "%.2f", data.fee))) [\(data.category)]"
            if let restrictions = data.restrictions, !restrictions.isEmpty {
                entry += " - \(restrictions.joined(separator: "; "))"
            }
            return entry
        }.joined(separator: "\n")
        
        // Build compatibility rules reference
        let compatibilityReference = buildCompatibilityReference()
        
        let durationText = duration.map { "Encounter duration: \(Int($0 / 60)) minutes" } ?? "Duration not specified"
        
        return """
        Analyze the following SOAP note and suggest appropriate billing codes.

        === SOAP NOTE ===
        \(soapNote)
        
        === ENCOUNTER INFO ===
        \(durationText)
        
        === AVAILABLE DIAGNOSTIC CODES (MOH 3-digit) ===
        \(dxReference)
        
        === AVAILABLE BILLING CODES (OHIP) ===
        \(billingReference)
        
        === COMPATIBILITY RULES ===
        \(compatibilityReference)
        
        === INSTRUCTIONS ===
        Based on the SOAP note, provide:
        1. Primary diagnostic code (the main reason for the visit)
        2. Secondary diagnostic codes (if applicable, other conditions addressed)
        3. Recommended billing codes (ensure all can be billed together for same visit)
        4. Alternative billing codes:
           - Up to 3 alternatives for the visit itself (e.g., if A001 is primary, A007 might be an alternative if more comprehensive assessment was done)
           - If a procedure was performed, include an additional 2-3 alternatives focused on procedure codes and associated technical/professional fees
        5. Brief rationale for your selections
        
        Respond ONLY with valid JSON in this exact format:
        {
            "primary_diagnosis": {
                "code": "XXX",
                "description": "Description"
            },
            "secondary_diagnoses": [
                {"code": "XXX", "description": "Description"}
            ],
            "billing_codes": [
                {"code": "AXXX", "description": "Description", "fee": 0.00}
            ],
            "alternative_billing_codes": [
                {"code": "AXXX", "description": "Description", "fee": 0.00, "when_to_use": "Use this if..."}
            ],
            "total_billable": 0.00,
            "rationale": "Brief explanation of code selection",
            "compatibility_note": "Note about code compatibility if relevant"
        }
        """
    }
    
    /// Get billing codes relevant to the SOAP note content
    private func getRelevantBillingCodes(for soapNote: String) -> [(String, ComprehensiveBillingCode)] {
        guard let data = comprehensiveBillingData else { return [] }
        
        let soapLower = soapNote.lowercased()
        var relevantCodes: [(String, ComprehensiveBillingCode)] = []
        
        // Always include common assessment codes
        let alwaysInclude = ["A001", "A003", "A004", "A007", "A005", "A006", "A911", "A912",
                            "K131", "K132", "K013", "E430", "E431"]
        
        for code in alwaysInclude {
            if let billingCode = data.billingCodes[code] {
                relevantCodes.append((code, billingCode))
            }
        }
        
        // Add codes based on SOAP content keywords
        let keywordMappings: [(keywords: [String], categories: [String])] = [
            (["injection", "epidural", "steroid", "cortisone", "nerve block", "lumbar", "cervical", "thoracic"],
             ["Nerve Blocks & Epidural Injections", "Injections", "Joint & Soft Tissue Injections"]),
            (["laceration", "wound", "suture", "cut", "repair"],
             ["Minor Surgical Procedures"]),
            (["excision", "biopsy", "lesion", "cyst", "abscess", "skin"],
             ["Minor Surgical Procedures"]),
            (["ecg", "electrocardiogram", "heart rhythm", "chest pain"],
             ["Diagnostic Tests"]),
            (["spirometry", "pulmonary", "lung function", "asthma", "copd"],
             ["Diagnostic Tests"]),
            (["iud", "intrauterine", "colposcopy", "pap", "cervical screening"],
             ["Women's Health Procedures"]),
            (["diabetes", "glucose", "hba1c", "diabetic"],
             ["Chronic Disease Management"]),
            (["counselling", "counseling", "mental health", "depression", "anxiety", "psychotherapy"],
             ["Counselling & Mental Health"]),
            (["palliative", "end of life", "terminal"],
             ["Palliative Care"]),
            (["house call", "home visit"],
             ["House Calls"]),
            (["hospital", "admission", "discharge", "inpatient"],
             ["Hospital Services"]),
            (["virtual", "telephone", "video visit", "telemedicine"],
             ["Virtual Care"]),
        ]
        
        for (keywords, categories) in keywordMappings {
            if keywords.contains(where: { soapLower.contains($0) }) {
                for (code, billingCode) in data.billingCodes {
                    if categories.contains(billingCode.category) &&
                       !relevantCodes.contains(where: { $0.0 == code }) {
                        relevantCodes.append((code, billingCode))
                    }
                }
            }
        }
        
        // Sort by category and code for readability
        relevantCodes.sort { $0.1.category < $1.1.category || ($0.1.category == $1.1.category && $0.0 < $1.0) }
        
        // Limit to reasonable size
        return Array(relevantCodes.prefix(150))
    }
    
    /// Build compatibility rules reference string
    private func buildCompatibilityReference() -> String {
        guard let rules = comprehensiveBillingData?.compatibilityRules else {
            return "No specific compatibility rules loaded."
        }
        
        var reference = ""
        
        if let notes = rules.notes {
            reference += "General Rules:\n"
            for note in notes {
                reference += "- \(note)\n"
            }
        }
        
        if let cannotBillSameDay = rules.cannotBillSameDay {
            reference += "\nCannot bill same day:\n"
            for group in cannotBillSameDay {
                reference += "- \(group.joined(separator: ", "))\n"
            }
        }
        
        return reference
    }
    
    /// Get diagnostic codes relevant to the SOAP note content
    private func getRelevantDiagnosticCodes(for soapNote: String) -> [DiagnosticCode] {
        let soapLower = soapNote.lowercased()
        
        // Keywords to match against diagnostic code descriptions
        let keywords = extractKeywords(from: soapLower)
        
        // Filter codes that might be relevant
        var relevantCodes = diagnosticCodes.filter { code in
            let descLower = code.description.lowercased()
            return keywords.contains { keyword in
                descLower.contains(keyword)
            }
        }
        
        // If we found too few or too many, adjust
        if relevantCodes.count < 20 {
            // Add some common codes
            let commonCodes = ["009", "346", "250", "401", "490", "724", "780", "786", "789"]
            for codeNum in commonCodes {
                if let code = diagnosticCodes.first(where: { $0.code == codeNum }) {
                    if !relevantCodes.contains(where: { $0.code == code.code }) {
                        relevantCodes.append(code)
                    }
                }
            }
        }
        
        // Limit to reasonable size for context window
        return Array(relevantCodes.prefix(100))
    }
    
    private func extractKeywords(from text: String) -> [String] {
        // Common medical terms to look for
        let medicalTerms = [
            "pain", "headache", "migraine", "fever", "cough", "cold", "flu", "infection",
            "diabetes", "hypertension", "blood pressure", "heart", "chest", "respiratory",
            "stomach", "abdominal", "nausea", "vomiting", "diarrhea", "constipation",
            "anxiety", "depression", "mental", "stress", "sleep", "insomnia",
            "skin", "rash", "eczema", "dermatitis", "acne",
            "back", "joint", "arthritis", "muscle", "sprain", "fracture",
            "urinary", "kidney", "bladder", "uti",
            "pregnancy", "prenatal", "menstrual", "gynecological",
            "thyroid", "hormone", "endocrine",
            "allergy", "allergic", "asthma", "bronchitis", "pneumonia",
            "ear", "nose", "throat", "sinus", "hearing",
            "eye", "vision", "conjunctivitis",
            "fatigue", "weakness", "dizziness", "syncope",
            "wound", "laceration", "injury", "trauma"
        ]
        
        return medicalTerms.filter { text.contains($0) }
    }
    
    // MARK: - Response Parsing
    
    private func parseLLMResponse(_ response: String) -> BillingSuggestion? {
        // Extract JSON from response (handle markdown code blocks)
        var jsonString = response
        
        // Safely extract JSON object from response
        if let jsonStart = response.firstIndex(of: "{"),
           let jsonEnd = response.lastIndex(of: "}") {
            // Ensure valid range
            if jsonStart <= jsonEnd {
                jsonString = String(response[jsonStart...jsonEnd])
            }
        }
        
        guard let data = jsonString.data(using: .utf8) else { return nil }
        
        do {
            let parsed = try JSONDecoder().decode(LLMBillingResponse.self, from: data)
            return BillingSuggestion(
                primaryDiagnosis: parsed.primaryDiagnosis,
                secondaryDiagnoses: parsed.secondaryDiagnoses ?? [],
                billingCodes: parsed.billingCodes,
                alternativeBillingCodes: parsed.alternativeBillingCodes ?? [],
                totalBillable: parsed.totalBillable,
                rationale: parsed.rationale,
                compatibilityNote: parsed.compatibilityNote
            )
        } catch {
            debugLog("❌ Failed to parse billing response: \(error)", component: "Billing")
            return nil
        }
    }
}

// MARK: - Data Models

struct DiagnosticCode: Codable, Identifiable {
    var id: String { code }
    let code: String
    let description: String
}

// MARK: - Comprehensive Billing Data Models (new format with 759 codes)

struct ComprehensiveBillingData: Codable {
    let metadata: BillingMetadata
    let billingCodes: [String: ComprehensiveBillingCode]
    let compatibilityRules: CompatibilityRules
    
    enum CodingKeys: String, CodingKey {
        case metadata
        case billingCodes = "billing_codes"
        case compatibilityRules = "compatibility_rules"
    }
}

struct BillingMetadata: Codable {
    let source: String
    let effectiveDate: String
    let extractedFrom: String
    let totalCodes: Int
    let practiceContext: PracticeContext
    
    enum CodingKeys: String, CodingKey {
        case source
        case effectiveDate = "effective_date"
        case extractedFrom = "extracted_from"
        case totalCodes = "total_codes"
        case practiceContext = "practice_context"
    }
}

struct PracticeContext: Codable {
    let practiceType: String
    let physicianType: String
    let setting: String
    let patientStatus: String
    let province: String
    
    enum CodingKeys: String, CodingKey {
        case practiceType = "practice_type"
        case physicianType = "physician_type"
        case setting
        case patientStatus = "patient_status"
        case province
    }
}

struct ComprehensiveBillingCode: Codable {
    let description: String
    let fee: Double
    let isAddon: Bool
    let category: String
    let restrictions: [String]?
    
    enum CodingKeys: String, CodingKey {
        case description, fee, category, restrictions
        case isAddon = "is_addon"
    }
}

struct CompatibilityRules: Codable {
    let cannotBillSameDay: [[String]]?
    let canAddTo: [String: [String]]?
    let notes: [String]?
    
    enum CodingKeys: String, CodingKey {
        case cannotBillSameDay = "cannot_bill_same_day"
        case canAddTo = "can_add_to"
        case notes
    }
}

// LLM Response structures
struct LLMBillingResponse: Codable {
    let primaryDiagnosis: CodeSuggestion
    let secondaryDiagnoses: [CodeSuggestion]?
    let billingCodes: [CodeSuggestion]
    let alternativeBillingCodes: [CodeSuggestion]?
    let totalBillable: Double
    let rationale: String
    let compatibilityNote: String?
    
    enum CodingKeys: String, CodingKey {
        case primaryDiagnosis = "primary_diagnosis"
        case secondaryDiagnoses = "secondary_diagnoses"
        case billingCodes = "billing_codes"
        case alternativeBillingCodes = "alternative_billing_codes"
        case totalBillable = "total_billable"
        case rationale
        case compatibilityNote = "compatibility_note"
    }
}

struct CodeSuggestion: Codable, Identifiable {
    var id: String { code }
    let code: String
    let description: String
    var fee: Double?
    var whenToUse: String?
    
    enum CodingKeys: String, CodingKey {
        case code, description, fee
        case whenToUse = "when_to_use"
    }
}

/// The final billing suggestion presented to the user
struct BillingSuggestion: Identifiable, Codable {
    let id: UUID
    let primaryDiagnosis: CodeSuggestion
    let secondaryDiagnoses: [CodeSuggestion]
    let billingCodes: [CodeSuggestion]
    let alternativeBillingCodes: [CodeSuggestion]
    let totalBillable: Double
    let rationale: String
    let compatibilityNote: String?
    
    init(
        id: UUID = UUID(),
        primaryDiagnosis: CodeSuggestion,
        secondaryDiagnoses: [CodeSuggestion],
        billingCodes: [CodeSuggestion],
        alternativeBillingCodes: [CodeSuggestion],
        totalBillable: Double,
        rationale: String,
        compatibilityNote: String?
    ) {
        self.id = id
        self.primaryDiagnosis = primaryDiagnosis
        self.secondaryDiagnoses = secondaryDiagnoses
        self.billingCodes = billingCodes
        self.alternativeBillingCodes = alternativeBillingCodes
        self.totalBillable = totalBillable
        self.rationale = rationale
        self.compatibilityNote = compatibilityNote
    }
}

