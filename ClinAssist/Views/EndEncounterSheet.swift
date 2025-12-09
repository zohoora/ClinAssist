import SwiftUI

struct EndEncounterSheet: View {
    let soapNote: String
    let isRegenerating: Bool
    let currentDetailLevel: Int
    let currentFormat: SOAPFormat
    let llmError: String?
    let onCopyToClipboard: () -> Void
    let onDismiss: () -> Void
    let onRegenerate: (Int, SOAPFormat, String) -> Void
    
    @State private var isCopied: Bool = false
    @State private var selectedDetailLevel: Double
    @State private var selectedFormat: SOAPFormat
    @State private var customInstructions: String = ""
    @State private var showInstructionsField: Bool = false
    
    init(
        soapNote: String,
        isRegenerating: Bool,
        currentDetailLevel: Int,
        currentFormat: SOAPFormat,
        llmError: String? = nil,
        onCopyToClipboard: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onRegenerate: @escaping (Int, SOAPFormat, String) -> Void
    ) {
        self.soapNote = soapNote
        self.isRegenerating = isRegenerating
        self.currentDetailLevel = currentDetailLevel
        self.currentFormat = currentFormat
        self.llmError = llmError
        self.onCopyToClipboard = onCopyToClipboard
        self.onDismiss = onDismiss
        self.onRegenerate = onRegenerate
        self._selectedDetailLevel = State(initialValue: Double(currentDetailLevel))
        self._selectedFormat = State(initialValue: currentFormat)
    }
    
    // Extract patient names from PATIENT: header lines
    private var patientNames: [String] {
        soapNote.components(separatedBy: .newlines)
            .filter { $0.uppercased().hasPrefix("PATIENT:") }
            .map { line in
                line.replacingOccurrences(of: "PATIENT:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }
    
    // SOAP note with PATIENT: header lines removed (for copying)
    private var soapNoteForCopy: String {
        soapNote.components(separatedBy: .newlines)
            .filter { !$0.uppercased().hasPrefix("PATIENT:") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var detailLevelDescription: String {
        let level = Int(selectedDetailLevel)
        switch level {
        case 1: return "Ultra-Brief"
        case 2: return "Minimal"
        case 3: return "Brief"
        case 4: return "Short"
        case 5: return "Standard"
        case 6: return "Expanded"
        case 7: return "Detailed"
        case 8: return "Thorough"
        case 9: return "Comprehensive"
        case 10: return "Maximum"
        default: return "Standard"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Encounter Complete")
                    .font(.headline)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            // Patient names (not included in copy)
            if !patientNames.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Patient\(patientNames.count > 1 ? "s" : ""):")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(patientNames, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                Text("(Patient names shown above are not included when copying)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            
            Divider()
            
            // Error display if SOAP generation failed
            if let error = llmError, soapNoteForCopy.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SOAP Note Generation Failed")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.red)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            // SOAP Note Content (without patient headers)
            ZStack {
                ScrollView {
                    Text(soapNoteForCopy.isEmpty ? (llmError != nil ? "Click 'Regenerate' to try again." : "No SOAP note generated.") : soapNoteForCopy)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(soapNoteForCopy.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                        .opacity(isRegenerating ? 0.3 : 1)
                }
                .background(Color(NSColor.textBackgroundColor))
                
                // Regenerating overlay
                if isRegenerating {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Regenerating SOAP note...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.7))
                }
            }
            
            Divider()
            
            // Customization Controls
            VStack(spacing: 12) {
                // Format Toggle
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Note Format")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            FormatToggleButton(
                                format: .problemBased,
                                isSelected: selectedFormat == .problemBased,
                                action: { selectedFormat = .problemBased }
                            )
                            
                            FormatToggleButton(
                                format: .comprehensive,
                                isSelected: selectedFormat == .comprehensive,
                                action: { selectedFormat = .comprehensive }
                            )
                        }
                    }
                    
                    Spacer()
                    
                    // Detail Level
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Detail Level")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            Text("Brief")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            
                            DetailSlider(value: $selectedDetailLevel)
                                .frame(width: 140)
                            
                            Text("\(Int(selectedDetailLevel))")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.accentColor)
                                .frame(width: 20)
                        }
                    }
                }
                
                // Custom Instructions
                VStack(alignment: .leading, spacing: 6) {
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showInstructionsField.toggle() } }) {
                        HStack(spacing: 4) {
                            Image(systemName: showInstructionsField ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Custom Instructions")
                                .font(.system(size: 11, weight: .semibold))
                            
                            if !customInstructions.isEmpty {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                            }
                            
                            Spacer()
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    if showInstructionsField {
                        TextEditor(text: $customInstructions)
                            .font(.system(size: 11))
                            .frame(height: 60)
                            .padding(6)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                            .overlay(
                                Group {
                                    if customInstructions.isEmpty {
                                        Text("e.g., \"Add more detail about medications\" or \"Include patient education points\"")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary.opacity(0.6))
                                            .padding(10)
                                            .allowsHitTesting(false)
                                    }
                                },
                                alignment: .topLeading
                            )
                    }
                }
                
                // Regenerate Button
                Button(action: regenerate) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Regenerate Note")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(isRegenerating || soapNoteForCopy.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Actions
            HStack(spacing: 12) {
                Button(action: {
                    copyToClipboard()
                }) {
                    HStack {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copied!" : "Copy to Clipboard")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(soapNoteForCopy.isEmpty || isRegenerating)
                
                Button(action: onDismiss) {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .frame(width: 540, height: 720)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func regenerate() {
        onRegenerate(Int(selectedDetailLevel), selectedFormat, customInstructions.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        // Copy the SOAP note WITHOUT patient header lines
        NSPasteboard.general.setString(soapNoteForCopy, forType: .string)
        
        isCopied = true
        onCopyToClipboard()
        
        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }
}

// MARK: - Format Toggle Button

struct FormatToggleButton: View {
    let format: SOAPFormat
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: format.icon)
                    .font(.system(size: 12))
                Text(format.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .foregroundColor(isSelected ? .accentColor : .primary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Custom Detail Slider

struct DetailSlider: View {
    @Binding var value: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 6)
                
                // Filled portion
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.6), Color.blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: CGFloat((value - 1) / 9) * geometry.size.width, height: 6)
                
                // Tick marks
                HStack(spacing: 0) {
                    ForEach(1...10, id: \.self) { tick in
                        Circle()
                            .fill(Double(tick) <= value ? Color.white : Color.secondary.opacity(0.4))
                            .frame(width: 4, height: 4)
                        if tick < 10 {
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 2)
                
                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .overlay(
                        Text("\(Int(value))")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.accentColor)
                    )
                    .offset(x: CGFloat((value - 1) / 9) * (geometry.size.width - 18))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                let newValue = 1 + (gesture.location.x / geometry.size.width) * 9
                                value = max(1, min(10, round(newValue)))
                            }
                    )
            }
        }
        .frame(height: 18)
    }
}

#Preview {
    EndEncounterSheet(
        soapNote: """
        PATIENT: John Smith
        
        PROBLEM: Migraine Headache
        S: 
        - 3-day history of throbbing headache
        - Right-sided, intensity 7/10
        - Associated with nausea, no vomiting
        - Photophobia present
        - No aura
        
        O:
        - VS: BP 124/78, HR 72, afebrile
        - Neuro exam unremarkable
        - No focal deficits
        
        A:
        - Migraine without aura, acute episode
        - No red flags for secondary headache
        
        P:
        - Sumatriptan 50mg PO PRN for acute episodes
        - Ibuprofen 400mg PO q6h PRN
        - Dark, quiet room rest
        - Follow up if symptoms persist >72h or worsen
        """,
        isRegenerating: false,
        currentDetailLevel: 5,
        currentFormat: .problemBased,
        onCopyToClipboard: { print("Copied") },
        onDismiss: { print("Dismissed") },
        onRegenerate: { level, format, instructions in print("Regenerate: level \(level), format \(format), instructions: \(instructions)") }
    )
}
