import SwiftUI

/// Main view for medication lookup feature
struct MedicationLookupView: View {
    @StateObject private var service = DrugLookupService()
    @State private var searchText = ""
    @State private var selectedDrug: DrugProduct?
    
    var body: some View {
        HSplitView {
            // Left panel - Search and results
            searchPanel
                .frame(minWidth: 300, idealWidth: 350, maxWidth: 450)
            
            // Right panel - Drug details
            detailPanel
                .frame(minWidth: 350)
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Search Panel
    
    private var searchPanel: some View {
        VStack(spacing: 0) {
            // Search header
            searchHeader
            
            Divider()
            
            // Results list
            if !service.isDatabaseReady {
                databaseNotReadyState
            } else if service.isSearching {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Searching...")
                        .font(.system(size: 13, weight: .medium))
                }
                .padding()
                Spacer()
            } else if service.searchResults.isEmpty {
                emptyState
            } else {
                resultsList
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
    
    private var searchHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "pills.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                
                Text("Medication Lookup")
                    .font(.system(size: 15, weight: .semibold))
                
                Spacer()
            }
            
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search by drug name or DIN...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onChange(of: searchText) { _, newValue in
                        service.search(query: newValue)
                    }
                    .onSubmit {
                        Task {
                            await service.searchImmediately(query: searchText)
                        }
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        service.search(query: "")
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
    }
    
    private var databaseNotReadyState: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 48))
                .foregroundColor(.orange.opacity(0.6))
            
            Text("Drug Database Not Built")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("The local drug database needs to be built before you can search.\n\nUse the menu option \"Update Drug Database...\" to build it.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            
            if let error = service.errorMessage {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary.opacity(0.5))
                
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else if searchText.isEmpty {
                Image(systemName: "pill")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary.opacity(0.5))
                
                Text("Enter a drug name or DIN to search")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Database info
                if let lastUpdate = service.lastDatabaseUpdate {
                    VStack(spacing: 4) {
                        Text("\(service.drugCount) drugs • \(service.variantCount) variants")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                        
                        Text("Updated \(lastUpdate, style: .relative) ago")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .padding(.top, 8)
                }
            } else if searchText.count < 2 {
                Text("Enter at least 2 characters to search")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(service.searchResults) { drug in
                    DrugResultRow(drug: drug, isSelected: selectedDrug?.id == drug.id)
                        .onTapGesture {
                            selectedDrug = drug
                        }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Detail Panel
    
    private var detailPanel: some View {
        Group {
            if let drug = selectedDrug {
                DrugDetailView(drug: drug)
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("Select a medication to view details")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Drug Result Row

struct DrugResultRow: View {
    let drug: DrugProduct
    let isSelected: Bool
    
    /// Get unique TRUE brand names (excludes generic manufacturer names like ACH-APIXABAN)
    private var uniqueBrandNames: [String] {
        var brandNames = Set<String>()
        let genericLower = drug.genericName.lowercased()
        
        // Add primary brand name if it's a true brand (doesn't contain generic name)
        if !drug.brandName.isEmpty {
            let baseBrand = extractBrandBase(drug.brandName)
            if isTrueBrandName(baseBrand, genericName: genericLower) {
                brandNames.insert(baseBrand)
            }
        }
        
        // Add brand names from variants that are true brands
        for variant in drug.variants {
            let baseBrand = extractBrandBase(variant.brandName)
            if isTrueBrandName(baseBrand, genericName: genericLower) {
                brandNames.insert(baseBrand)
            }
        }
        
        return Array(brandNames).sorted()
    }
    
    /// Check if a brand name is a true brand (not a generic manufacturer name)
    private func isTrueBrandName(_ brandName: String, genericName: String) -> Bool {
        let brandLower = brandName.lowercased()
        
        // If it's empty or same as generic, not a brand
        if brandLower.isEmpty || brandLower == genericName {
            return false
        }
        
        // If the brand name contains the generic name, it's likely a generic product
        // e.g., "ACH-APIXABAN" contains "APIXABAN"
        if brandLower.contains(genericName) {
            return false
        }
        
        // Common generic manufacturer prefixes in Canada
        let genericPrefixes = [
            "ACH-", "AG-", "APO-", "TEVA-", "PMS-", "JAMP-", "MINT-", "SANDOZ-",
            "MYLAN-", "RATIO-", "RAN-", "CO-", "DOM-", "NRA-", "MED-", "MAR-",
            "NU-", "PRO-", "RIVA-", "SANIS-", "SIVEM-", "VAN-", "ZYM-", "AUR-",
            "BIO-", "GD-", "M-", "NAT-", "NTP-", "PHL-", "PHARMA-", "AA-", "ACT-"
        ]
        
        for prefix in genericPrefixes {
            if brandLower.hasPrefix(prefix.lowercased()) {
                return false
            }
        }
        
        return true
    }
    
    /// Extract base brand name (removes strength/form suffixes like "2.5MG TAB")
    private func extractBrandBase(_ brandName: String) -> String {
        // Common patterns to strip: "2.5MG TAB", "5MG TAB", etc.
        let pattern = #"\s+\d+(\.\d+)?\s*(MG|MCG|G|ML|IU)\s*(TAB|CAP|SOL|INJ|SUSP|CR|XR|SR|ER|DR|EC)?.*$"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(brandName.startIndex..., in: brandName)
            return regex.stringByReplacingMatches(in: brandName, range: range, withTemplate: "").trimmingCharacters(in: .whitespaces)
        }
        return brandName
    }
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // Show generic name prominently
                Text(drug.genericName.uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                // Show all brand names in parentheses
                if !uniqueBrandNames.isEmpty {
                    Text("(\(uniqueBrandNames.joined(separator: ", ")))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // Show variant count
                if drug.variants.count > 0 {
                    Text("\(drug.variants.count) variants")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
            
            Spacer()
            
            // Coverage badges
            VStack(alignment: .trailing, spacing: 4) {
                if drug.hasODBCoverage {
                    CoverageBadge(
                        text: "ODB",
                        status: drug.odbCoverage?.statusColor ?? .covered,
                        isLimitedUse: drug.odbCoverage?.isLimitedUse ?? false
                    )
                }
                
                if drug.hasNIHBCoverage {
                    CoverageBadge(
                        text: "NIHB",
                        status: drug.nihbCoverage?.statusColor ?? .covered,
                        isLimitedUse: drug.nihbCoverage?.isLimitedUse ?? false
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Coverage Badge

struct CoverageBadge: View {
    let text: String
    let status: CoverageStatusColor
    let isLimitedUse: Bool
    
    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            
            Text(text)
                .font(.system(size: 9, weight: .semibold))
            
            if isLimitedUse {
                Text("LU")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.15))
        .cornerRadius(4)
    }
    
    private var statusColor: Color {
        switch status {
        case .covered:
            return .green
        case .limitedUse:
            return .orange
        case .notCovered:
            return .red
        case .notDetermined:
            return .gray
        }
    }
}

// MARK: - Drug Detail View

struct DrugDetailView: View {
    let drug: DrugProduct
    @State private var showAllVariants = false
    
    /// Get unique TRUE brand names (excludes generic manufacturer names like ACH-APIXABAN)
    private var uniqueBrandNames: [String] {
        var brandNames = Set<String>()
        let genericLower = drug.genericName.lowercased()
        
        // Add primary brand name if it's a true brand (doesn't contain generic name)
        if !drug.brandName.isEmpty {
            let baseBrand = extractBrandBase(drug.brandName)
            if isTrueBrandName(baseBrand, genericName: genericLower) {
                brandNames.insert(baseBrand)
            }
        }
        
        // Add brand names from variants that are true brands
        for variant in drug.variants {
            let baseBrand = extractBrandBase(variant.brandName)
            if isTrueBrandName(baseBrand, genericName: genericLower) {
                brandNames.insert(baseBrand)
            }
        }
        
        return Array(brandNames).sorted()
    }
    
    /// Check if a brand name is a true brand (not a generic manufacturer name)
    private func isTrueBrandName(_ brandName: String, genericName: String) -> Bool {
        let brandLower = brandName.lowercased()
        
        // If it's empty or same as generic, not a brand
        if brandLower.isEmpty || brandLower == genericName {
            return false
        }
        
        // If the brand name contains the generic name, it's likely a generic product
        // e.g., "ACH-APIXABAN" contains "APIXABAN"
        if brandLower.contains(genericName) {
            return false
        }
        
        // Common generic manufacturer prefixes in Canada
        let genericPrefixes = [
            "ACH-", "AG-", "APO-", "TEVA-", "PMS-", "JAMP-", "MINT-", "SANDOZ-",
            "MYLAN-", "RATIO-", "RAN-", "CO-", "DOM-", "NRA-", "MED-", "MAR-",
            "NU-", "PRO-", "RIVA-", "SANIS-", "SIVEM-", "VAN-", "ZYM-", "AUR-",
            "BIO-", "GD-", "M-", "NAT-", "NTP-", "PHL-", "PHARMA-", "AA-", "ACT-"
        ]
        
        for prefix in genericPrefixes {
            if brandLower.hasPrefix(prefix.lowercased()) {
                return false
            }
        }
        
        return true
    }
    
    /// Extract base brand name (removes strength/form suffixes like "2.5MG TAB")
    private func extractBrandBase(_ brandName: String) -> String {
        // Common patterns to strip: "2.5MG TAB", "5MG TAB", etc.
        let pattern = #"\s+\d+(\.\d+)?\s*(MG|MCG|G|ML|IU)\s*(TAB|CAP|SOL|INJ|SUSP|CR|XR|SR|ER|DR|EC)?.*$"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(brandName.startIndex..., in: brandName)
            return regex.stringByReplacingMatches(in: brandName, range: range, withTemplate: "").trimmingCharacters(in: .whitespaces)
        }
        return brandName
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                drugHeader
                
                Divider()
                
                // Coverage status
                coverageSection
                
                // Available strengths
                if !drug.availableStrengths.isEmpty {
                    strengthsSection
                }
                
                // Variants section (different DINs/manufacturers)
                if !drug.variants.isEmpty {
                    variantsSection
                }
                
                // Active ingredients (if available)
                if !drug.activeIngredients.isEmpty {
                    ingredientsSection
                }
                
                Spacer()
            }
            .padding(20)
        }
    }
    
    private var drugHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(drug.genericName.uppercased())
                .font(.system(size: 22, weight: .bold))
            
            // Show all brand names in parentheses
            if !uniqueBrandNames.isEmpty {
                Text("(\(uniqueBrandNames.joined(separator: ", ")))")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            
            if let therapeutic = drug.therapeuticClass {
                Text(therapeutic)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
    }
    
    private var coverageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coverage Status")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                // ODB Coverage
                CoverageCard(
                    title: "Ontario Drug Benefit",
                    subtitle: "Provincial",
                    coverage: drug.odbCoverage.map { odb in
                        CoverageInfo(
                            status: odb.statusDescription,
                            color: odb.statusColor,
                            details: nil
                        )
                    }
                )
                
                // NIHB Coverage
                CoverageCard(
                    title: "NIHB",
                    subtitle: "Federal (ON)",
                    coverage: drug.nihbCoverage.map { nihb in
                        CoverageInfo(
                            status: nihb.statusDescription,
                            color: nihb.statusColor,
                            details: nil
                        )
                    }
                )
            }
            
            // Limited Use Details (if applicable)
            if let odb = drug.odbCoverage, odb.isLimitedUse {
                limitedUseSection(coverage: odb)
            }
        }
    }
    
    private func limitedUseSection(coverage: ODBCoverage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))
                
                Text("Limited Use Requirements")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Show LU code badges
                HStack(spacing: 4) {
                    ForEach(coverage.limitedUseCodes, id: \.self) { code in
                        Text("Sec \(code)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
            }
            
            // Show actual criteria from database if available
            if !coverage.limitedUseCriteria.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(coverage.limitedUseCriteria.filter { !$0.isAuthPeriodNote && !$0.criteria.isEmpty }) { criterion in
                        VStack(alignment: .leading, spacing: 8) {
                            // Show LU Code if available
                            if let code = criterion.reasonForUseId, !code.isEmpty {
                                HStack(spacing: 6) {
                                    Text("LU Code:")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    Text(code)
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(.orange)
                                }
                            }
                            
                            // Show criteria text
                            Text(criterion.criteria)
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            // Show authorization period if available
                            if let authPeriod = findAuthorizationPeriod(for: criterion, in: coverage.limitedUseCriteria) {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 10))
                                    Text("Authorization Period: \(authPeriod)")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.secondary)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                    }
                }
            } else {
                // Fall back to generic descriptions if no criteria in database
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(coverage.limitedUseCodes, id: \.self) { code in
                        HStack(alignment: .top, spacing: 10) {
                            Text("Sec \(code)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(4)
                            
                            Text(limitedUseCodeDescription(code))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    /// Find the authorization period that follows a criterion (by sequence)
    private func findAuthorizationPeriod(for criterion: LimitedUseCriterion, in criteria: [LimitedUseCriterion]) -> String? {
        // Look for auth period note that follows this criterion
        if let nextCriterion = criteria.first(where: { $0.sequence == criterion.sequence + 1 && $0.isAuthPeriodNote }) {
            return nextCriterion.authorizationPeriod
        }
        return nil
    }
    
    /// Returns a fallback description for ODB Limited Use codes when detailed criteria not available
    private func limitedUseCodeDescription(_ code: String) -> String {
        switch code.lowercased() {
        case "3b":
            return "Requires a written request from the prescriber explaining the clinical rationale."
        case "3b-eap":
            return "Exceptional Access Program. Requires EAP approval with clinical documentation."
        case "3c":
            return "Requires completion of a Limited Use (LU) request form."
        case "6":
            return "Requires prior authorization. Prescriber must apply for coverage."
        case "9":
            return "Section 9 coverage criteria apply."
        case "12":
            return "Limited clinical criteria (LCC) - specific indications must be met."
        default:
            return "Specific clinical criteria apply. Check ODB Formulary for details."
        }
    }
    
    private var strengthsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available Strengths")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
            
            FlowLayout(spacing: 8) {
                ForEach(drug.availableStrengths, id: \.self) { strength in
                    Text(strength)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(6)
                }
            }
        }
    }
    
    private var variantsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Available Products (\(drug.variants.count))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if drug.variants.count > 5 {
                    Button(showAllVariants ? "Show Less" : "Show All") {
                        showAllVariants.toggle()
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }
            
            VStack(spacing: 1) {
                ForEach(showAllVariants ? drug.variants : Array(drug.variants.prefix(5))) { variant in
                    VariantRow(variant: variant)
                }
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
    }
    
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Ingredients")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(drug.activeIngredients) { ingredient in
                    HStack {
                        Text(ingredient.name)
                            .font(.system(size: 13))
                        
                        Spacer()
                        
                        Text("\(ingredient.strength) \(ingredient.strengthUnit)")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    if ingredient.id != drug.activeIngredients.last?.id {
                        Divider()
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
    }
}

// MARK: - Variant Row

struct VariantRow: View {
    let variant: DrugVariant
    @State private var isExpanded = false
    
    private var hasLUCriteria: Bool {
        guard let odb = variant.odbCoverage else { return false }
        return odb.isLimitedUse && !odb.limitedUseCriteria.isEmpty
    }
    
    private var luCodes: [String] {
        guard let odb = variant.odbCoverage else { return [] }
        let codes = odb.limitedUseCriteria
            .compactMap { $0.reasonForUseId }
            .filter { !$0.isEmpty }
        return Array(Set(codes)).sorted()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row (clickable if has LU criteria)
            Button(action: {
                if hasLUCriteria {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            }) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(variant.brandName)
                                .font(.system(size: 12, weight: .medium))
                            
                            // Show LU codes inline
                            if !luCodes.isEmpty {
                                HStack(spacing: 3) {
                                    ForEach(luCodes.prefix(3), id: \.self) { code in
                                        Text(code)
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundColor(.orange)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.orange.opacity(0.15))
                                            .cornerRadius(3)
                                    }
                                    if luCodes.count > 3 {
                                        Text("+\(luCodes.count - 3)")
                                            .font(.system(size: 9))
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                        }
                        
                        HStack(spacing: 8) {
                            Text("DIN: \(variant.din)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                            
                            if !variant.strength.isEmpty {
                                Text(variant.strength)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if !variant.manufacturer.isEmpty {
                            Text(variant.manufacturer)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                    }
                    
                    Spacer()
                    
                    // Coverage for this specific variant
                    VStack(alignment: .trailing, spacing: 3) {
                        if let odb = variant.odbCoverage {
                            MiniCoverageBadge(text: "ODB", color: odb.statusColor)
                        }
                        if let nihb = variant.nihbCoverage {
                            MiniCoverageBadge(text: "NIHB", color: nihb.statusColor)
                        }
                    }
                    
                    // Expand indicator
                    if hasLUCriteria {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Expanded LU criteria section
            if isExpanded, let odb = variant.odbCoverage {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(odb.limitedUseCriteria.filter { !$0.isAuthPeriodNote && !$0.criteria.isEmpty }) { criterion in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                if let code = criterion.reasonForUseId, !code.isEmpty {
                                    Text("LU \(code)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15))
                                        .cornerRadius(4)
                                }
                                
                                // Find associated auth period
                                if let authPeriod = findAuthPeriod(for: criterion, in: odb.limitedUseCriteria) {
                                    HStack(spacing: 2) {
                                        Image(systemName: "clock")
                                            .font(.system(size: 8))
                                        Text(authPeriod)
                                            .font(.system(size: 9))
                                    }
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                                }
                            }
                            
                            Text(criterion.criteria)
                                .font(.system(size: 11))
                                .foregroundColor(.primary.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.05))
                        .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }
    
    private func findAuthPeriod(for criterion: LimitedUseCriterion, in criteria: [LimitedUseCriterion]) -> String? {
        // First check if the criterion itself has an auth period
        if let period = criterion.authorizationPeriod, !period.isEmpty {
            return period
        }
        
        // Look for the next "R" type note after this criterion
        if let currentIndex = criteria.firstIndex(where: { $0.id == criterion.id }) {
            for i in (currentIndex + 1)..<criteria.count {
                let nextCriterion = criteria[i]
                if nextCriterion.isAuthPeriodNote {
                    // Extract the period from the text
                    let text = nextCriterion.criteria
                    if text.contains("Indefinite") {
                        return "Indefinite"
                    } else if let range = text.range(of: #"\d+\s*(year|month|day|week)s?"#, options: .regularExpression) {
                        return String(text[range])
                    }
                    return nil
                }
                // If we hit another non-R criterion, stop looking
                if !nextCriterion.isAuthPeriodNote && nextCriterion.reasonForUseId != nil {
                    break
                }
            }
        }
        return nil
    }
}

struct MiniCoverageBadge: View {
    let text: String
    let color: CoverageStatusColor
    
    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(statusColor)
    }
    
    private var statusColor: Color {
        switch color {
        case .covered: return .green
        case .limitedUse: return .orange
        case .notCovered: return .red
        case .notDetermined: return .gray
        }
    }
}

// MARK: - Flow Layout for Tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                
                self.size.width = max(self.size.width, x)
            }
            
            self.size.height = y + rowHeight
        }
    }
}

// MARK: - Helper Views

struct InfoItem: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            Text(value.isEmpty || value == "N/A" ? "—" : value)
                .font(.system(size: 13))
                .foregroundColor(.primary)
        }
    }
}

struct CoverageInfo {
    let status: String
    let color: CoverageStatusColor
    let details: String?
}

struct CoverageCard: View {
    let title: String
    let subtitle: String
    let coverage: CoverageInfo?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            if let coverage = coverage {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(coverage.color))
                        .frame(width: 10, height: 10)
                    
                    Text(coverage.status)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(statusColor(coverage.color))
                }
                
                if let details = coverage.details {
                    Text(details)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("No data available")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    private func statusColor(_ status: CoverageStatusColor) -> Color {
        switch status {
        case .covered:
            return .green
        case .limitedUse:
            return .orange
        case .notCovered:
            return .red
        case .notDetermined:
            return .gray
        }
    }
}

// MARK: - Preview

#Preview {
    MedicationLookupView()
        .frame(width: 900, height: 600)
}

