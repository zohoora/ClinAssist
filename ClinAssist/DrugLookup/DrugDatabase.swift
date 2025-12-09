import Foundation
import SQLite3

/// SQLite database wrapper for local drug storage
/// Provides fast, offline medication lookups
class DrugDatabase {
    
    static let shared = DrugDatabase()
    
    private var db: OpaquePointer?
    private let dbPath: URL
    
    // MARK: - Initialization
    
    init() {
        // Store database in Dropbox folder alongside other app data
        dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Dropbox")
            .appendingPathComponent("livecode_records")
            .appendingPathComponent("drug_database.sqlite")
        
        openDatabase()
    }
    
    deinit {
        closeDatabase()
    }
    
    // MARK: - Database Connection
    
    private func openDatabase() {
        // Ensure directory exists
        try? FileManager.default.createDirectory(
            at: dbPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        if sqlite3_open(dbPath.path, &db) != SQLITE_OK {
            debugLog("❌ Failed to open drug database: \(String(cString: sqlite3_errmsg(db)))", component: "DrugDB")
            db = nil
        } else {
            debugLog("✅ Drug database opened: \(dbPath.path)", component: "DrugDB")
        }
    }
    
    private func closeDatabase() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }
    
    /// Check if database exists and has data
    var isDatabaseReady: Bool {
        guard FileManager.default.fileExists(atPath: dbPath.path) else {
            return false
        }
        
        // Check if drugs table has data
        let count = getDrugCount()
        return count > 0
    }
    
    /// Get the last update date
    var lastUpdateDate: Date? {
        guard let dateString = getMetadata(key: "last_update") else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }
    
    // MARK: - Schema Creation
    
    /// Create all database tables (call during database build)
    func createSchema() {
        guard db != nil else { return }
        
        let schemas = [
            // Main drugs table (consolidated by generic name)
            """
            CREATE TABLE IF NOT EXISTS drugs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                generic_name TEXT NOT NULL UNIQUE,
                therapeutic_class TEXT,
                atc_code TEXT,
                created_at TEXT,
                updated_at TEXT
            )
            """,
            
            // Variants table (individual DINs/brands)
            """
            CREATE TABLE IF NOT EXISTS variants (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                drug_id INTEGER REFERENCES drugs(id),
                din TEXT UNIQUE NOT NULL,
                brand_name TEXT,
                strength TEXT,
                strength_value REAL,
                strength_unit TEXT,
                dosage_form TEXT,
                route TEXT,
                manufacturer TEXT,
                odb_covered INTEGER DEFAULT 0,
                odb_limited_use INTEGER DEFAULT 0,
                odb_lu_codes TEXT,
                odb_price REAL,
                nihb_covered INTEGER DEFAULT 0,
                nihb_limited_use INTEGER DEFAULT 0,
                nihb_status TEXT
            )
            """,
            
            // Active ingredients (for combination drugs)
            """
            CREATE TABLE IF NOT EXISTS ingredients (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                drug_id INTEGER REFERENCES drugs(id),
                ingredient_name TEXT NOT NULL,
                strength TEXT,
                strength_unit TEXT
            )
            """,
            
            // Indications (future)
            """
            CREATE TABLE IF NOT EXISTS indications (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                drug_id INTEGER REFERENCES drugs(id),
                indication TEXT NOT NULL,
                source TEXT
            )
            """,
            
            // Dosing information (future)
            """
            CREATE TABLE IF NOT EXISTS dosing (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                drug_id INTEGER REFERENCES drugs(id),
                population TEXT,
                indication TEXT,
                dose TEXT,
                frequency TEXT,
                max_dose TEXT,
                notes TEXT,
                source TEXT
            )
            """,
            
            // Drug interactions (future)
            """
            CREATE TABLE IF NOT EXISTS interactions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                drug_id_1 INTEGER REFERENCES drugs(id),
                drug_id_2 INTEGER REFERENCES drugs(id),
                severity TEXT,
                description TEXT,
                source TEXT
            )
            """,
            
            // Metadata table
            """
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY,
                value TEXT
            )
            """,
            
            // Indexes
            "CREATE INDEX IF NOT EXISTS idx_generic_name ON drugs(generic_name)",
            "CREATE INDEX IF NOT EXISTS idx_brand_name ON variants(brand_name)",
            "CREATE INDEX IF NOT EXISTS idx_din ON variants(din)",
            "CREATE INDEX IF NOT EXISTS idx_drug_id ON variants(drug_id)",
            "CREATE INDEX IF NOT EXISTS idx_ingredient ON ingredients(ingredient_name)",
            "CREATE INDEX IF NOT EXISTS idx_atc ON drugs(atc_code)"
        ]
        
        for schema in schemas {
            executeSQL(schema)
        }
        
        debugLog("✅ Database schema created", component: "DrugDB")
    }
    
    /// Drop all tables (for rebuilding)
    func dropAllTables() {
        guard db != nil else { return }
        
        let tables = ["variants", "ingredients", "indications", "dosing", "interactions", "drugs", "metadata"]
        for table in tables {
            executeSQL("DROP TABLE IF EXISTS \(table)")
        }
        
        debugLog("🗑️ All tables dropped", component: "DrugDB")
    }
    
    // MARK: - Drug Operations
    
    /// Insert or update a drug record
    /// Returns the drug ID
    @discardableResult
    func insertDrug(genericName: String, therapeuticClass: String?, atcCode: String?) -> Int64? {
        guard db != nil else { return nil }
        
        let now = ISO8601DateFormatter().string(from: Date())
        
        let sql = """
            INSERT INTO drugs (generic_name, therapeutic_class, atc_code, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(generic_name) DO UPDATE SET
                therapeutic_class = COALESCE(excluded.therapeutic_class, therapeutic_class),
                atc_code = COALESCE(excluded.atc_code, atc_code),
                updated_at = excluded.updated_at
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            debugLog("❌ Failed to prepare insert drug: \(String(cString: sqlite3_errmsg(db)))", component: "DrugDB")
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, genericName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        bindTextOrNull(stmt, index: 2, value: therapeuticClass)
        bindTextOrNull(stmt, index: 3, value: atcCode)
        sqlite3_bind_text(stmt, 4, now, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 5, now, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            debugLog("❌ Failed to insert drug: \(String(cString: sqlite3_errmsg(db)))", component: "DrugDB")
            return nil
        }
        
        // Get the drug ID (either new or existing)
        return getDrugId(genericName: genericName)
    }
    
    /// Get drug ID by generic name
    func getDrugId(genericName: String) -> Int64? {
        guard db != nil else { return nil }
        
        let sql = "SELECT id FROM drugs WHERE generic_name = ?"
        var stmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, genericName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int64(stmt, 0)
        }
        return nil
    }
    
    // MARK: - Variant Operations
    
    /// Insert a drug variant (specific DIN/brand)
    func insertVariant(
        drugId: Int64,
        din: String,
        brandName: String,
        strength: String?,
        strengthValue: Double?,
        strengthUnit: String?,
        dosageForm: String?,
        route: String?,
        manufacturer: String?,
        odbCovered: Bool,
        odbLimitedUse: Bool,
        odbLuCodes: String?,
        odbPrice: Double?,
        nihbCovered: Bool,
        nihbLimitedUse: Bool,
        nihbStatus: String?
    ) {
        guard db != nil else { return }
        
        let sql = """
            INSERT INTO variants (
                drug_id, din, brand_name, strength, strength_value, strength_unit,
                dosage_form, route, manufacturer,
                odb_covered, odb_limited_use, odb_lu_codes, odb_price,
                nihb_covered, nihb_limited_use, nihb_status
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(din) DO UPDATE SET
                brand_name = excluded.brand_name,
                strength = COALESCE(excluded.strength, strength),
                strength_value = COALESCE(excluded.strength_value, strength_value),
                strength_unit = COALESCE(excluded.strength_unit, strength_unit),
                dosage_form = COALESCE(excluded.dosage_form, dosage_form),
                route = COALESCE(excluded.route, route),
                manufacturer = COALESCE(excluded.manufacturer, manufacturer),
                odb_covered = excluded.odb_covered,
                odb_limited_use = excluded.odb_limited_use,
                odb_lu_codes = excluded.odb_lu_codes,
                odb_price = COALESCE(excluded.odb_price, odb_price),
                nihb_covered = excluded.nihb_covered,
                nihb_limited_use = excluded.nihb_limited_use,
                nihb_status = excluded.nihb_status
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            debugLog("❌ Failed to prepare insert variant: \(String(cString: sqlite3_errmsg(db)))", component: "DrugDB")
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int64(stmt, 1, drugId)
        sqlite3_bind_text(stmt, 2, din, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 3, brandName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        bindTextOrNull(stmt, index: 4, value: strength)
        bindDoubleOrNull(stmt, index: 5, value: strengthValue)
        bindTextOrNull(stmt, index: 6, value: strengthUnit)
        bindTextOrNull(stmt, index: 7, value: dosageForm)
        bindTextOrNull(stmt, index: 8, value: route)
        bindTextOrNull(stmt, index: 9, value: manufacturer)
        sqlite3_bind_int(stmt, 10, odbCovered ? 1 : 0)
        sqlite3_bind_int(stmt, 11, odbLimitedUse ? 1 : 0)
        bindTextOrNull(stmt, index: 12, value: odbLuCodes)
        bindDoubleOrNull(stmt, index: 13, value: odbPrice)
        sqlite3_bind_int(stmt, 14, nihbCovered ? 1 : 0)
        sqlite3_bind_int(stmt, 15, nihbLimitedUse ? 1 : 0)
        bindTextOrNull(stmt, index: 16, value: nihbStatus)
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            debugLog("❌ Failed to insert variant: \(String(cString: sqlite3_errmsg(db)))", component: "DrugDB")
        }
    }
    
    // MARK: - Ingredient Operations
    
    func insertIngredient(drugId: Int64, ingredientName: String, strength: String?, strengthUnit: String?) {
        guard db != nil else { return }
        
        let sql = "INSERT INTO ingredients (drug_id, ingredient_name, strength, strength_unit) VALUES (?, ?, ?, ?)"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int64(stmt, 1, drugId)
        sqlite3_bind_text(stmt, 2, ingredientName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        bindTextOrNull(stmt, index: 3, value: strength)
        bindTextOrNull(stmt, index: 4, value: strengthUnit)
        
        sqlite3_step(stmt)
    }
    
    // MARK: - Search Operations
    
    /// Search drugs by name (generic or brand)
    func searchDrugs(query: String, limit: Int = 50) -> [DrugProduct] {
        guard db != nil else { return [] }
        
        let searchTerm = "%\(query)%"
        
        // First, get matching drug IDs from both drugs and variants tables
        let sql = """
            SELECT DISTINCT d.id, d.generic_name, d.therapeutic_class, d.atc_code
            FROM drugs d
            LEFT JOIN variants v ON v.drug_id = d.id
            WHERE d.generic_name LIKE ? OR v.brand_name LIKE ? OR v.din LIKE ?
            ORDER BY 
                CASE WHEN d.generic_name LIKE ? THEN 0 ELSE 1 END,
                d.generic_name
            LIMIT ?
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            debugLog("❌ Failed to prepare search: \(String(cString: sqlite3_errmsg(db)))", component: "DrugDB")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        
        let exactMatch = "\(query)%"
        sqlite3_bind_text(stmt, 1, searchTerm, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 2, searchTerm, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 3, searchTerm, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 4, exactMatch, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int(stmt, 5, Int32(limit))
        
        var results: [DrugProduct] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let drugId = sqlite3_column_int64(stmt, 0)
            let genericName = String(cString: sqlite3_column_text(stmt, 1))
            let therapeuticClass = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            
            // Get variants for this drug
            let variants = getVariants(drugId: drugId)
            
            // Determine best coverage
            let bestODB = variants.compactMap { $0.odbCoverage }.first { $0.isCovered }
                ?? variants.compactMap { $0.odbCoverage }.first
            let bestNIHB = variants.compactMap { $0.nihbCoverage }.first { $0.isCovered }
                ?? variants.compactMap { $0.nihbCoverage }.first
            
            // Get available strengths
            let strengths = Set(variants.compactMap { $0.strength }.filter { !$0.isEmpty })
            let strengthStr = strengths.sorted().joined(separator: ", ")
            
            let product = DrugProduct(
                id: genericName.lowercased().replacingOccurrences(of: " ", with: "-"),
                brandName: variants.first?.brandName ?? genericName,
                genericName: genericName,
                strength: strengthStr,
                dosageForm: variants.first?.dosageForm ?? "",
                manufacturer: "",
                therapeuticClass: therapeuticClass,
                activeIngredients: [],
                odbCoverage: bestODB,
                nihbCoverage: bestNIHB,
                variants: variants
            )
            
            results.append(product)
        }
        
        return results
    }
    
    /// Get all variants for a drug
    private func getVariants(drugId: Int64) -> [DrugVariant] {
        guard db != nil else { return [] }
        
        let sql = """
            SELECT din, brand_name, strength, dosage_form, manufacturer,
                   odb_covered, odb_limited_use, odb_lu_codes,
                   nihb_covered, nihb_limited_use, nihb_status
            FROM variants
            WHERE drug_id = ?
            ORDER BY brand_name
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int64(stmt, 1, drugId)
        
        var variants: [DrugVariant] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let din = String(cString: sqlite3_column_text(stmt, 0))
            let brandName = String(cString: sqlite3_column_text(stmt, 1))
            let strength = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let dosageForm = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
            let manufacturer = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
            
            let odbCovered = sqlite3_column_int(stmt, 5) == 1
            let odbLimitedUse = sqlite3_column_int(stmt, 6) == 1
            let odbLuCodes = sqlite3_column_text(stmt, 7).map { String(cString: $0) }
            
            let nihbCovered = sqlite3_column_int(stmt, 8) == 1
            let nihbLimitedUse = sqlite3_column_int(stmt, 9) == 1
            let nihbStatus = sqlite3_column_text(stmt, 10).map { String(cString: $0) }
            
            var variant = DrugVariant(
                din: din,
                brandName: brandName,
                strength: strength,
                dosageForm: dosageForm,
                manufacturer: manufacturer
            )
            
            // Add ODB coverage - get from ODB manager to include LU criteria
            if odbCovered || odbLimitedUse {
                // Try to get full coverage from ODB manager (includes LU criteria)
                if let fullCoverage = ODBFormularyManager.shared.getCoverage(din: din) {
                    variant.odbCoverage = fullCoverage
                } else {
                    // Fall back to basic coverage from database
                    variant.odbCoverage = ODBCoverage(
                        din: din,
                        isCovered: odbCovered,
                        isLimitedUse: odbLimitedUse,
                        limitedUseCodes: odbLuCodes?.components(separatedBy: ",") ?? [],
                        limitedUseCriteria: [],
                        price: nil,
                        listingDate: nil
                    )
                }
            }
            
            // Add NIHB coverage
            if nihbCovered || nihbLimitedUse || nihbStatus != nil {
                variant.nihbCoverage = NIHBCoverage(
                    din: din,
                    chemicalName: "",
                    itemName: brandName,
                    ahfsCode: "",
                    ahfsDescription: "",
                    ontarioStatus: nihbStatus ?? (nihbCovered ? "Open Benefit" : "Not Determined"),
                    manufacturer: manufacturer
                )
            }
            
            variants.append(variant)
        }
        
        return variants
    }
    
    // MARK: - Metadata Operations
    
    func setMetadata(key: String, value: String) {
        guard db != nil else { return }
        
        let sql = "INSERT INTO metadata (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 2, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        
        sqlite3_step(stmt)
    }
    
    func getMetadata(key: String) -> String? {
        guard db != nil else { return nil }
        
        let sql = "SELECT value FROM metadata WHERE key = ?"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return String(cString: sqlite3_column_text(stmt, 0))
        }
        return nil
    }
    
    // MARK: - Statistics
    
    func getDrugCount() -> Int {
        guard db != nil else { return 0 }
        
        let sql = "SELECT COUNT(*) FROM drugs"
        var stmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }
    
    func getVariantCount() -> Int {
        guard db != nil else { return 0 }
        
        let sql = "SELECT COUNT(*) FROM variants"
        var stmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }
    
    // MARK: - Transaction Support
    
    func beginTransaction() {
        executeSQL("BEGIN TRANSACTION")
    }
    
    func commitTransaction() {
        executeSQL("COMMIT")
    }
    
    func rollbackTransaction() {
        executeSQL("ROLLBACK")
    }
    
    // MARK: - Helpers
    
    private func executeSQL(_ sql: String) {
        guard db != nil else { return }
        
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                debugLog("❌ SQL error: \(String(cString: errMsg))", component: "DrugDB")
                sqlite3_free(errMsg)
            }
        }
    }
    
    private func bindTextOrNull(_ stmt: OpaquePointer?, index: Int32, value: String?) {
        if let value = value, !value.isEmpty {
            sqlite3_bind_text(stmt, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
    
    private func bindDoubleOrNull(_ stmt: OpaquePointer?, index: Int32, value: Double?) {
        if let value = value {
            sqlite3_bind_double(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
}

