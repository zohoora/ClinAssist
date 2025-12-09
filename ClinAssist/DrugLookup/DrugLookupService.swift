import Foundation

/// Orchestrates drug lookups using the local SQLite database
/// Falls back to showing "database not ready" message if not built yet
@MainActor
class DrugLookupService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var searchResults: [DrugProduct] = []
    @Published var isSearching: Bool = false
    @Published var errorMessage: String?
    @Published var lastSearchQuery: String = ""
    
    // Database status
    @Published var isDatabaseReady: Bool = false
    @Published var lastDatabaseUpdate: Date?
    @Published var drugCount: Int = 0
    @Published var variantCount: Int = 0
    
    // MARK: - Private Properties
    
    private let database: DrugDatabase
    private var searchTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init(database: DrugDatabase = .shared) {
        self.database = database
        refreshDatabaseStatus()
    }
    
    // MARK: - Database Status
    
    /// Refresh the database status
    func refreshDatabaseStatus() {
        isDatabaseReady = database.isDatabaseReady
        lastDatabaseUpdate = database.lastUpdateDate
        drugCount = database.getDrugCount()
        variantCount = database.getVariantCount()
        
        if isDatabaseReady {
            debugLog("📊 Drug database ready: \(drugCount) drugs, \(variantCount) variants", component: "DrugLookup")
        } else {
            debugLog("⚠️ Drug database not ready - needs to be built", component: "DrugLookup")
        }
    }
    
    // MARK: - Public Methods
    
    /// Search for drugs in the local database
    /// - Parameters:
    ///   - query: Search term (drug name, generic name, or DIN)
    ///   - debounceMs: Delay before executing search (for typing debounce)
    func search(query: String, debounceMs: Int = 150) {
        // Cancel any pending search
        searchTask?.cancel()
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Clear results if query is too short
        guard trimmedQuery.count >= 2 else {
            searchResults = []
            lastSearchQuery = ""
            errorMessage = nil
            return
        }
        
        lastSearchQuery = trimmedQuery
        
        // Debounce the search
        searchTask = Task {
            // Wait for debounce period
            try? await Task.sleep(nanoseconds: UInt64(debounceMs) * 1_000_000)
            
            guard !Task.isCancelled else { return }
            
            await performSearch(query: trimmedQuery)
        }
    }
    
    /// Search immediately without debounce
    func searchImmediately(query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 2 else {
            searchResults = []
            return
        }
        
        lastSearchQuery = trimmedQuery
        await performSearch(query: trimmedQuery)
    }
    
    // MARK: - Private Methods
    
    private func performSearch(query: String) async {
        isSearching = true
        errorMessage = nil
        
        // Check database status
        guard isDatabaseReady else {
            errorMessage = "Drug database not available. Please build the database first."
            isSearching = false
            return
        }
        
        // Perform SQLite search
        let startTime = Date()
        let results = database.searchDrugs(query: query, limit: 50)
        let elapsed = Date().timeIntervalSince(startTime)
        
        guard !Task.isCancelled else { return }
        
        // Sort by relevance (exact matches first)
        var sortedResults = results.sorted { a, b in
            let aExact = a.genericName.lowercased() == query.lowercased() ||
                         a.brandName.lowercased() == query.lowercased()
            let bExact = b.genericName.lowercased() == query.lowercased() ||
                         b.brandName.lowercased() == query.lowercased()
            
            if aExact != bExact {
                return aExact
            }
            return a.genericName < b.genericName
        }
        
        searchResults = sortedResults
        
        if sortedResults.isEmpty {
            errorMessage = "No results found for \"\(query)\""
        }
        
        debugLog("🔍 Search '\(query)' returned \(sortedResults.count) results in \(String(format: "%.0f", elapsed * 1000))ms", component: "DrugLookup")
        
        isSearching = false
    }
}
