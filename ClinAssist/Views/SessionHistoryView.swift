import SwiftUI

/// A model representing a loaded historical session
struct HistoricalSession: Identifiable {
    let id: UUID
    let folderURL: URL
    let startTime: Date
    let endTime: Date?
    let patientName: String
    let soapNote: String
    let transcript: String?
    let state: EncounterState?
    
    var duration: TimeInterval {
        guard let end = endTime else { return 0 }
        return end.timeIntervalSince(startTime)
    }
    
    var durationFormatted: String {
        let minutes = Int(duration / 60)
        return "\(minutes) min"
    }
}

/// Main view for browsing session history
struct SessionHistoryView: View {
    @StateObject private var viewModel: SessionHistoryViewModel
    
    init(configManager: ConfigManager) {
        _viewModel = StateObject(wrappedValue: SessionHistoryViewModel(configManager: configManager))
    }
    
    var body: some View {
        HSplitView {
            // Left panel - Date picker and session list
            sessionListPanel
                .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)
            
            // Right panel - Session details
            sessionDetailPanel
                .frame(minWidth: 400)
        }
        .frame(minWidth: 800, minHeight: 550)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            viewModel.loadSessionsForSelectedDate()
        }
    }
    
    // MARK: - Left Panel
    
    private var sessionListPanel: some View {
        VStack(spacing: 0) {
            // Date picker header
            datePickerHeader
            
            Divider()
            
            // Sessions list
            if viewModel.isLoading {
                Spacer()
                ProgressView("Loading sessions...")
                    .padding()
                Spacer()
            } else if viewModel.sessions.isEmpty {
                Spacer()
                emptyStateView
                Spacer()
            } else {
                sessionsList
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private var datePickerHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.accentColor)
                
                Text("Session History")
                    .font(.system(size: 14, weight: .semibold))
                
                Spacer()
            }
            
            DatePicker(
                "",
                selection: $viewModel.selectedDate,
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .onChange(of: viewModel.selectedDate) { _, _ in
                viewModel.loadSessionsForSelectedDate()
            }
        }
        .padding()
    }
    
    private var sessionsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.sessions) { session in
                    SessionCardView(
                        session: session,
                        isSelected: viewModel.selectedSession?.id == session.id
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.selectSession(session)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No sessions")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            
            Text("No encounters recorded on this date")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    // MARK: - Right Panel
    
    private var sessionDetailPanel: some View {
        Group {
            if let session = viewModel.selectedSession {
                SessionDetailView(
                    session: session,
                    viewModel: viewModel
                )
            } else {
                noSelectionView
            }
        }
    }
    
    private var noSelectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))
            
            Text("Select a session")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            
            Text("Choose a session from the list to view details")
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}

// MARK: - Session Card View

struct SessionCardView: View {
    let session: HistoricalSession
    let isSelected: Bool
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Time range
            HStack {
                Circle()
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                
                Text("\(timeFormatter.string(from: session.startTime))")
                    .font(.system(size: 12, weight: .semibold))
                
                if let endTime = session.endTime {
                    Text("–")
                        .foregroundColor(.secondary)
                    Text(timeFormatter.string(from: endTime))
                        .font(.system(size: 12, weight: .semibold))
                }
                
                Spacer()
                
                Text(session.durationFormatted)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            // Patient name
            Text(session.patientName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .primary : .secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
    }
}

// MARK: - Session Detail View

struct SessionDetailView: View {
    let session: HistoricalSession
    @ObservedObject var viewModel: SessionHistoryViewModel
    
    @State private var isCopied = false
    @State private var selectedDetailLevel: Double = 5
    @State private var selectedFormat: SOAPFormat = .problemBased
    @State private var showCustomInstructions = false
    @State private var customInstructions = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            sessionHeader
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // SOAP Note section
                    soapNoteSection
                    
                    Divider()
                    
                    // Billing codes section
                    billingCodesSection
                }
                .padding()
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }
    
    // MARK: - Header
    
    private var sessionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.patientName)
                    .font(.system(size: 16, weight: .semibold))
                
                Text(formattedDateRange)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Duration badge
            Text(session.durationFormatted)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.15))
                .foregroundColor(.accentColor)
                .cornerRadius(12)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
    
    private var formattedDateRange: String {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "America/New_York")
        dateFormatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        return dateFormatter.string(from: session.startTime)
    }
    
    // MARK: - SOAP Note Section
    
    private var soapNoteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("SOAP NOTE")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if viewModel.isRegenerating {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            
            // SOAP content
            ZStack {
                Text(soapNoteForDisplay)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
                    .opacity(viewModel.isRegenerating ? 0.3 : 1)
                
                if viewModel.isRegenerating {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Regenerating...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // Controls
            soapControls
        }
    }
    
    private var soapNoteForDisplay: String {
        // Use viewModel.selectedSession to get live updates after regeneration
        // Fall back to session.soapNote if selectedSession doesn't match
        let soapNote = (viewModel.selectedSession?.id == session.id) 
            ? (viewModel.selectedSession?.soapNote ?? session.soapNote)
            : session.soapNote
        
        // Remove PATIENT: lines for display (same as EndEncounterSheet)
        return soapNote.components(separatedBy: .newlines)
            .filter { !$0.uppercased().hasPrefix("PATIENT:") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var soapControls: some View {
        VStack(spacing: 12) {
            HStack {
                // Format picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Format")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 6) {
                        FormatButton(
                            format: .problemBased,
                            isSelected: selectedFormat == .problemBased
                        ) {
                            selectedFormat = .problemBased
                        }
                        
                        FormatButton(
                            format: .comprehensive,
                            isSelected: selectedFormat == .comprehensive
                        ) {
                            selectedFormat = .comprehensive
                        }
                    }
                }
                
                Spacer()
                
                // Detail level
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Detail Level")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 6) {
                        Text("Brief")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        
                        Slider(value: $selectedDetailLevel, in: 1...10, step: 1)
                            .frame(width: 100)
                        
                        Text("\(Int(selectedDetailLevel))")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.accentColor)
                            .frame(width: 20)
                    }
                }
            }
            
            // Custom instructions toggle
            DisclosureGroup(
                isExpanded: $showCustomInstructions,
                content: {
                    TextEditor(text: $customInstructions)
                        .font(.system(size: 11))
                        .frame(height: 50)
                        .padding(4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                },
                label: {
                    HStack(spacing: 4) {
                        Text("Custom Instructions")
                            .font(.system(size: 10, weight: .medium))
                        
                        if !customInstructions.isEmpty {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 5, height: 5)
                        }
                    }
                    .foregroundColor(.secondary)
                }
            )
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: regenerateSOAP) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Regenerate")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isRegenerating)
                
                Spacer()
                
                Button(action: copyToClipboard) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copied!" : "Copy SOAP")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    private func regenerateSOAP() {
        Task {
            await viewModel.regenerateSOAP(
                for: session,
                detailLevel: Int(selectedDetailLevel),
                format: selectedFormat,
                customInstructions: customInstructions
            )
        }
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(soapNoteForDisplay, forType: .string)
        
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }
    
    // MARK: - Billing Codes Section
    
    private var billingCodesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("BILLING CODES")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if viewModel.isGeneratingCodes {
                    ProgressView()
                        .scaleEffect(0.6)
                }
                
                Button(action: generateCodes) {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                        Text("Suggest Codes")
                    }
                    .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isGeneratingCodes)
            }
            
            if let suggestion = viewModel.billingSuggestion {
                billingCodesContent(suggestion)
            } else if let error = viewModel.billingError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            } else {
                Text("Click 'Suggest Codes' to generate billing recommendations based on the SOAP note.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            }
        }
    }
    
    @ViewBuilder
    private func billingCodesContent(_ suggestion: BillingSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Diagnostic codes
            VStack(alignment: .leading, spacing: 8) {
                Text("Diagnostic Code")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                
                codeRow(
                    code: suggestion.primaryDiagnosis.code,
                    description: suggestion.primaryDiagnosis.description,
                    isPrimary: true
                )
                
                if !suggestion.secondaryDiagnoses.isEmpty {
                    Text("Secondary")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    
                    ForEach(suggestion.secondaryDiagnoses) { dx in
                        codeRow(code: dx.code, description: dx.description, isPrimary: false)
                    }
                }
            }
            
            Divider()
            
            // Billing codes
            VStack(alignment: .leading, spacing: 8) {
                Text("Billing Codes")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                
                ForEach(suggestion.billingCodes) { code in
                    HStack {
                        Text(code.code)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentColor)
                        
                        Text(code.description)
                            .font(.system(size: 11))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if let fee = code.fee {
                            Text(String(format: "$%.2f", fee))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Total
                HStack {
                    Text("Total Billable:")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text(String(format: "$%.2f", suggestion.totalBillable))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.green)
                }
                .padding(.top, 4)
            }
            
            // Alternative billing codes
            if !suggestion.alternativeBillingCodes.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("Alternative Options")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    
                    ForEach(suggestion.alternativeBillingCodes) { code in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(code.code)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.purple)
                                
                                Text(code.description)
                                    .font(.system(size: 10))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                if let fee = code.fee {
                                    Text(String(format: "$%.2f", fee))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let whenToUse = code.whenToUse, !whenToUse.isEmpty {
                                Text(whenToUse)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            
            // Rationale
            if !suggestion.rationale.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rationale")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Text(suggestion.rationale)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            // Compatibility note
            if let note = suggestion.compatibilityNote, !note.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                    
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            // Copy codes button
            HStack {
                Spacer()
                
                Button(action: { copyBillingCodes(suggestion) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy Codes")
                    }
                    .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func codeRow(code: String, description: String, isPrimary: Bool) -> some View {
        HStack {
            Text(code)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(isPrimary ? .orange : .secondary)
            
            Text(description)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .lineLimit(2)
            
            Spacer()
        }
    }
    
    private func generateCodes() {
        Task {
            await viewModel.generateBillingCodes(for: session)
        }
    }
    
    private func copyBillingCodes(_ suggestion: BillingSuggestion) {
        var text = "Diagnostic: \(suggestion.primaryDiagnosis.code) - \(suggestion.primaryDiagnosis.description)\n"
        
        for dx in suggestion.secondaryDiagnoses {
            text += "Secondary Dx: \(dx.code) - \(dx.description)\n"
        }
        
        text += "\nBilling:\n"
        for code in suggestion.billingCodes {
            text += "\(code.code) - \(code.description)"
            if let fee = code.fee {
                text += " ($\(String(format: "%.2f", fee)))"
            }
            text += "\n"
        }
        
        text += "\nTotal: $\(String(format: "%.2f", suggestion.totalBillable))"
        
        // Include alternative options
        if !suggestion.alternativeBillingCodes.isEmpty {
            text += "\n\nAlternative Options:\n"
            for code in suggestion.alternativeBillingCodes {
                text += "\(code.code) - \(code.description)"
                if let fee = code.fee {
                    text += " ($\(String(format: "%.2f", fee)))"
                }
                if let whenToUse = code.whenToUse {
                    text += "\n  → \(whenToUse)"
                }
                text += "\n"
            }
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Format Button

struct FormatButton: View {
    let format: SOAPFormat
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: format.icon)
                    .font(.system(size: 10))
                Text(format.displayName)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .foregroundColor(isSelected ? .accentColor : .primary)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    SessionHistoryView(
        configManager: ConfigManager.shared
    )
    .frame(width: 900, height: 650)
}

