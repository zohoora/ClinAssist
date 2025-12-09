import Foundation

/// Manages the Ontario Drug Benefit (ODB) Formulary data
/// Parses XML data and provides search functionality
class ODBFormularyManager: NSObject, XMLParserDelegate {
    
    static let shared = ODBFormularyManager()
    
    private var entries: [ODBEntry] = []
    private var isLoaded = false
    private let loadLock = NSLock()
    
    // Index for fast lookup by DIN
    private var dinIndex: [String: ODBEntry] = [:]
    
    // Index for LU criteria by lccId
    private var lccCriteriaIndex: [String: [LimitedUseCriterion]] = [:]
    
    // Manufacturer lookup
    private var manufacturers: [String: String] = [:] // id -> name
    
    // XML Parsing state
    private var currentElement = ""
    private var currentDrug: ODBEntry?
    private var currentGenericName = ""
    private var currentDosageForm = ""
    private var currentStrength = ""
    private var currentText = ""
    private var currentManufacturerId = ""
    private var currentManufacturerName = ""
    
    // LCC (Limited Clinical Criteria) parsing state
    private var currentLccId: String? = nil
    private var currentLccNotes: [LimitedUseCriterion] = []
    private var currentLccNoteSeq: Int = 0
    private var currentLccNoteReasonId: String? = nil
    private var currentLccNoteType: String? = nil
    private var drugsInCurrentPcgGroup: [String] = [] // DINs of drugs in current pcgGroup
    
    private override init() {
        super.init()
    }
    
    // MARK: - Data Loading
    
    /// Load the ODB data from bundled XML file
    func loadData() {
        loadLock.lock()
        defer { loadLock.unlock() }
        
        guard !isLoaded else { return }
        
        guard let url = Bundle.main.url(forResource: "odb-formulary", withExtension: "xml") else {
            debugLog("ODB XML file not found in bundle", component: "ODB")
            return
        }
        
        parseXML(from: url)
        isLoaded = true
        debugLog("Loaded \(entries.count) ODB entries", component: "ODB")
    }
    
    /// Load from a specific file path (for testing or custom data)
    func loadData(from path: String) {
        loadLock.lock()
        defer { loadLock.unlock() }
        
        let url = URL(fileURLWithPath: path)
        parseXML(from: url)
        isLoaded = true
        debugLog("Loaded \(entries.count) ODB entries from \(path)", component: "ODB")
    }
    
    private func parseXML(from url: URL) {
        entries.removeAll()
        dinIndex.removeAll()
        manufacturers.removeAll()
        
        guard let parser = XMLParser(contentsOf: url) else {
            debugLog("Failed to create XML parser for ODB", component: "ODB")
            return
        }
        
        parser.delegate = self
        parser.parse()
        
        if let error = parser.parserError {
            debugLog("XML parsing error: \(error)", component: "ODB")
        }
    }
    
    // MARK: - XMLParserDelegate
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentText = ""
        
        switch elementName {
        case "manufacturer":
            currentManufacturerId = attributeDict["id"] ?? ""
            currentManufacturerName = ""
            
        case "genericName":
            currentGenericName = ""
            
        case "pcgGroup":
            // Check if this pcgGroup has LU criteria (lccId attribute)
            currentLccId = attributeDict["lccId"]
            currentLccNotes = []
            drugsInCurrentPcgGroup = []
            
        case "pcg9":
            currentDosageForm = ""
            currentStrength = ""
            
        case "lccNote":
            // Parse lccNote attributes
            if let seqStr = attributeDict["seq"], let seq = Int(seqStr) {
                currentLccNoteSeq = seq
            } else {
                currentLccNoteSeq = currentLccNotes.count + 1
            }
            currentLccNoteReasonId = attributeDict["reasonForUseId"]
            currentLccNoteType = attributeDict["type"]
            
        case "drug":
            let din = attributeDict["id"] ?? ""
            
            // Parse coverage attributes
            let notABenefit = attributeDict["notABenefit"] == "Y"
            let sec3 = attributeDict["sec3"] == "Y"
            let sec3b = attributeDict["sec3b"] == "Y"
            let sec3bEAP = attributeDict["sec3bEAP"] == "Y"
            let sec3c = attributeDict["sec3c"] == "Y"
            let sec6 = attributeDict["sec6"] == "Y"
            let sec9 = attributeDict["sec9"] == "Y"
            let sec12 = attributeDict["sec12"] == "Y"
            _ = attributeDict["insOH"] == "Y" // insOH flag (not used currently)
            
            // Collect limited use codes
            var limitedUseCodes: [String] = []
            if sec3b { limitedUseCodes.append("3b") }
            if sec3bEAP { limitedUseCodes.append("3b-EAP") }
            if sec3c { limitedUseCodes.append("3c") }
            if sec6 { limitedUseCodes.append("6") }
            if sec9 { limitedUseCodes.append("9") }
            if sec12 { limitedUseCodes.append("12") }
            
            currentDrug = ODBEntry(
                din: din,
                brandName: "",
                genericName: currentGenericName,
                dosageForm: currentDosageForm,
                strength: currentStrength,
                manufacturerId: "",
                manufacturerName: "",
                price: nil,
                listingDate: nil,
                isCovered: !notABenefit,
                isLimitedUse: !limitedUseCodes.isEmpty,
                limitedUseCodes: limitedUseCodes,
                limitedUseCriteria: [],
                lccId: currentLccId,
                isGeneralBenefit: sec3 && !notABenefit && limitedUseCodes.isEmpty
            )
            
            // Track this drug's DIN for associating with lccNotes later
            if currentLccId != nil {
                drugsInCurrentPcgGroup.append(din)
            }
            
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmedText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch elementName {
        case "manufacturer":
            if !currentManufacturerId.isEmpty {
                manufacturers[currentManufacturerId] = currentManufacturerName.isEmpty ? trimmedText : currentManufacturerName
            }
            
        case "name":
            // Could be generic name, drug name, or manufacturer name depending on context
            if currentDrug != nil {
                currentDrug?.brandName = trimmedText
            } else if currentGenericName.isEmpty && currentElement == "name" {
                currentGenericName = trimmedText
            } else if currentManufacturerId.isEmpty == false && currentManufacturerName.isEmpty {
                currentManufacturerName = trimmedText
            }
            
        case "genericName":
            // Reset for next genericName section
            break
            
        case "dosageForm":
            currentDosageForm = trimmedText
            currentDrug?.dosageForm = trimmedText
            
        case "strength":
            currentStrength = trimmedText
            currentDrug?.strength = trimmedText
            
        case "manufacturerId":
            currentDrug?.manufacturerId = trimmedText
            currentDrug?.manufacturerName = manufacturers[trimmedText] ?? trimmedText
            
        case "individualPrice":
            currentDrug?.price = trimmedText
            
        case "listingDate":
            currentDrug?.listingDate = trimmedText
            
        case "lccNote":
            // Create and store the LU criterion
            let isAuthPeriodNote = currentLccNoteType == "R"
            var authPeriod: String? = nil
            var criteriaText = trimmedText
            
            // Extract authorization period from notes like "LU Authorization Period: 14 days"
            if isAuthPeriodNote && trimmedText.lowercased().contains("authorization period") {
                authPeriod = trimmedText
                    .replacingOccurrences(of: "LU Authorization Period:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
                criteriaText = "" // Don't duplicate the auth period as criteria
            }
            
            let criterion = LimitedUseCriterion(
                sequence: currentLccNoteSeq,
                reasonForUseId: currentLccNoteReasonId,
                criteria: criteriaText,
                authorizationPeriod: authPeriod,
                isAuthPeriodNote: isAuthPeriodNote
            )
            
            // Only add non-empty criteria
            if !criteriaText.isEmpty || authPeriod != nil {
                currentLccNotes.append(criterion)
            }
            
            // Reset
            currentLccNoteReasonId = nil
            currentLccNoteType = nil
            
        case "pcgGroup":
            // Associate lccNotes with all drugs in this pcgGroup
            if let lccId = currentLccId, !currentLccNotes.isEmpty {
                lccCriteriaIndex[lccId] = currentLccNotes
                
                // Update all drugs in this pcgGroup with the criteria
                for din in drugsInCurrentPcgGroup {
                    if var entry = dinIndex[din] {
                        entry.limitedUseCriteria = currentLccNotes
                        dinIndex[din] = entry
                        // Also update in entries array
                        if let index = entries.firstIndex(where: { $0.din == din }) {
                            entries[index].limitedUseCriteria = currentLccNotes
                        }
                    }
                }
            }
            currentLccId = nil
            currentLccNotes = []
            drugsInCurrentPcgGroup = []
            
        case "drug":
            if var drug = currentDrug {
                // Update generic name if it wasn't set
                if drug.genericName.isEmpty {
                    drug.genericName = currentGenericName
                }
                entries.append(drug)
                dinIndex[drug.din] = drug
            }
            currentDrug = nil
            
        default:
            break
        }
    }
    
    // MARK: - Search
    
    /// Get coverage by DIN
    func getCoverage(din: String) -> ODBCoverage? {
        ensureLoaded()
        
        guard let entry = dinIndex[din] else { return nil }
        return entry.toODBCoverage()
    }
    
    /// Search by drug name (generic or brand)
    func search(query: String) -> [ODBCoverage] {
        ensureLoaded()
        
        let lowercaseQuery = query.lowercased()
        
        let matches = entries.filter { entry in
            entry.genericName.lowercased().contains(lowercaseQuery) ||
            entry.brandName.lowercased().contains(lowercaseQuery)
        }
        
        return matches.map { $0.toODBCoverage() }
    }
    
    /// Search with limit for better performance
    func search(query: String, limit: Int) -> [ODBCoverage] {
        ensureLoaded()
        
        let lowercaseQuery = query.lowercased()
        var results: [ODBCoverage] = []
        
        for entry in entries {
            if entry.genericName.lowercased().contains(lowercaseQuery) ||
               entry.brandName.lowercased().contains(lowercaseQuery) {
                results.append(entry.toODBCoverage())
                if results.count >= limit {
                    break
                }
            }
        }
        
        return results
    }
    
    /// Get all coverage entries (for database building)
    func getAllCoverage() -> [ODBCoverage] {
        ensureLoaded()
        return entries.map { $0.toODBCoverage() }
    }
    
    private func ensureLoaded() {
        if !isLoaded {
            loadData()
        }
    }
}

// MARK: - ODB Entry (Internal)

private struct ODBEntry {
    let din: String
    var brandName: String
    var genericName: String
    var dosageForm: String
    var strength: String
    var manufacturerId: String
    var manufacturerName: String
    var price: String?
    var listingDate: String?
    let isCovered: Bool
    let isLimitedUse: Bool
    let limitedUseCodes: [String]
    var limitedUseCriteria: [LimitedUseCriterion]
    var lccId: String?
    let isGeneralBenefit: Bool
    
    func toODBCoverage() -> ODBCoverage {
        ODBCoverage(
            din: din,
            isCovered: isCovered,
            isLimitedUse: isLimitedUse,
            limitedUseCodes: limitedUseCodes,
            limitedUseCriteria: limitedUseCriteria,
            price: price,
            listingDate: listingDate
        )
    }
}

