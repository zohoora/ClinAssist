import Foundation

/// Manages the NIHB (Non-Insured Health Benefits) Drug Benefit List
/// Parses CSV data and provides search functionality
class NIHBFormularyManager {
    
    static let shared = NIHBFormularyManager()
    
    private var entries: [NIHBEntry] = []
    private var isLoaded = false
    private let loadLock = NSLock()
    
    // Index for fast lookup by DIN
    private var dinIndex: [String: NIHBEntry] = [:]
    
    private init() {}
    
    // MARK: - Data Loading
    
    /// Load the NIHB data from bundled CSV file
    func loadData() {
        loadLock.lock()
        defer { loadLock.unlock() }
        
        guard !isLoaded else { return }
        
        guard let url = Bundle.main.url(forResource: "nihb-drug-benefit-list", withExtension: "csv") else {
            debugLog("NIHB CSV file not found in bundle", component: "NIHB")
            return
        }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            parseCSV(content)
            isLoaded = true
            debugLog("Loaded \(entries.count) NIHB entries", component: "NIHB")
        } catch {
            debugLog("Failed to load NIHB CSV: \(error)", component: "NIHB")
        }
    }
    
    /// Load from a specific file path (for testing or custom data)
    func loadData(from path: String) {
        loadLock.lock()
        defer { loadLock.unlock() }
        
        let url = URL(fileURLWithPath: path)
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            parseCSV(content)
            isLoaded = true
            debugLog("Loaded \(entries.count) NIHB entries from \(path)", component: "NIHB")
        } catch {
            debugLog("Failed to load NIHB CSV from \(path): \(error)", component: "NIHB")
        }
    }
    
    private func parseCSV(_ content: String) {
        entries.removeAll()
        dinIndex.removeAll()
        
        let lines = content.components(separatedBy: .newlines)
        
        // Skip header and disclaimer lines
        var headerIndex = -1
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("AHFS CODE,") {
                headerIndex = index
                break
            }
        }
        
        guard headerIndex >= 0 else {
            debugLog("Could not find NIHB CSV header", component: "NIHB")
            return
        }
        
        // Parse data rows
        for lineIndex in (headerIndex + 1)..<lines.count {
            let line = lines[lineIndex]
            guard !line.isEmpty else { continue }
            
            if let entry = parseCSVLine(line) {
                entries.append(entry)
                dinIndex[entry.din] = entry
            }
        }
    }
    
    private func parseCSVLine(_ line: String) -> NIHBEntry? {
        let fields = parseCSVFields(line)
        
        // Expected columns:
        // 0: AHFS CODE, 1: AHFS DESCRIPTION, 2: CHEMICAL NAME, 3: DOSAGE FORM,
        // 4: STRENGTH, 5: ITEM NAME, 6: DIN, 7: MANUFACTURER,
        // 8-20: Province columns (AB, BC, MB, NB, NF, NS, NT, NU, ON, PE, QC, SK, YT)
        
        guard fields.count >= 17 else { return nil }
        
        let din = fields[6].trimmingCharacters(in: .whitespaces)
        guard !din.isEmpty else { return nil }
        
        return NIHBEntry(
            ahfsCode: fields[0],
            ahfsDescription: fields[1],
            chemicalName: fields[2],
            dosageForm: fields[3],
            strength: fields[4],
            itemName: fields[5],
            din: din,
            manufacturer: fields[7],
            albertaStatus: fields.count > 8 ? fields[8] : "",
            bcStatus: fields.count > 9 ? fields[9] : "",
            manitobaStatus: fields.count > 10 ? fields[10] : "",
            newBrunswickStatus: fields.count > 11 ? fields[11] : "",
            newfoundlandStatus: fields.count > 12 ? fields[12] : "",
            novaScotiaStatus: fields.count > 13 ? fields[13] : "",
            nwtStatus: fields.count > 14 ? fields[14] : "",
            nunavutStatus: fields.count > 15 ? fields[15] : "",
            ontarioStatus: fields.count > 16 ? fields[16] : "",
            peiStatus: fields.count > 17 ? fields[17] : "",
            quebecStatus: fields.count > 18 ? fields[18] : "",
            saskatchewanStatus: fields.count > 19 ? fields[19] : "",
            yukonStatus: fields.count > 20 ? fields[20] : ""
        )
    }
    
    /// Parse CSV fields handling quoted values with commas
    private func parseCSVFields(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var inQuotes = false
        
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(currentField)
                currentField = ""
            } else {
                currentField.append(char)
            }
        }
        fields.append(currentField)
        
        return fields
    }
    
    // MARK: - Search
    
    /// Search by DIN
    func getCoverage(din: String) -> NIHBCoverage? {
        ensureLoaded()
        
        guard let entry = dinIndex[din] else { return nil }
        return entry.toNIHBCoverage()
    }
    
    /// Search by drug name (generic or brand)
    func search(query: String) -> [NIHBCoverage] {
        ensureLoaded()
        
        let lowercaseQuery = query.lowercased()
        
        let matches = entries.filter { entry in
            entry.chemicalName.lowercased().contains(lowercaseQuery) ||
            entry.itemName.lowercased().contains(lowercaseQuery)
        }
        
        return matches.map { $0.toNIHBCoverage() }
    }
    
    /// Search with limit for better performance
    func search(query: String, limit: Int) -> [NIHBCoverage] {
        ensureLoaded()
        
        let lowercaseQuery = query.lowercased()
        var results: [NIHBCoverage] = []
        
        for entry in entries {
            if entry.chemicalName.lowercased().contains(lowercaseQuery) ||
               entry.itemName.lowercased().contains(lowercaseQuery) {
                results.append(entry.toNIHBCoverage())
                if results.count >= limit {
                    break
                }
            }
        }
        
        return results
    }
    
    /// Get all coverage entries (for database building)
    func getAllCoverage() -> [NIHBCoverage] {
        ensureLoaded()
        return entries.map { $0.toNIHBCoverage() }
    }
    
    private func ensureLoaded() {
        if !isLoaded {
            loadData()
        }
    }
}

// MARK: - NIHB Entry (Internal)

private struct NIHBEntry {
    let ahfsCode: String
    let ahfsDescription: String
    let chemicalName: String
    let dosageForm: String
    let strength: String
    let itemName: String
    let din: String
    let manufacturer: String
    
    // Province coverage statuses
    let albertaStatus: String
    let bcStatus: String
    let manitobaStatus: String
    let newBrunswickStatus: String
    let newfoundlandStatus: String
    let novaScotiaStatus: String
    let nwtStatus: String
    let nunavutStatus: String
    let ontarioStatus: String
    let peiStatus: String
    let quebecStatus: String
    let saskatchewanStatus: String
    let yukonStatus: String
    
    func toNIHBCoverage() -> NIHBCoverage {
        NIHBCoverage(
            din: din,
            chemicalName: chemicalName,
            itemName: itemName,
            ahfsCode: ahfsCode,
            ahfsDescription: ahfsDescription,
            ontarioStatus: ontarioStatus,
            manufacturer: manufacturer
        )
    }
}

