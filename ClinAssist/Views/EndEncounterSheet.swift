import SwiftUI

struct EndEncounterSheet: View {
    let soapNote: String
    let onCopyToClipboard: () -> Void
    let onDismiss: () -> Void
    
    @State private var isCopied: Bool = false
    
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
            
            // SOAP Note Content (without patient headers)
            ScrollView {
                Text(soapNoteForCopy.isEmpty ? "No SOAP note generated." : soapNoteForCopy)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .background(Color(NSColor.textBackgroundColor))
            
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
                .disabled(soapNoteForCopy.isEmpty)
                
                Button(action: onDismiss) {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
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

#Preview {
    EndEncounterSheet(
        soapNote: """
        PROBLEM 1: Migraine Headache
        S: 
        • 3-day history of throbbing headache
        • Right-sided, intensity 7/10
        • Associated with nausea, no vomiting
        • Photophobia present
        • No aura
        
        O:
        • VS: BP 124/78, HR 72, afebrile
        • Neuro exam unremarkable
        • No focal deficits
        
        A:
        • Migraine without aura, acute episode
        • No red flags for secondary headache
        
        P:
        • Sumatriptan 50mg PO PRN for acute episodes
        • Ibuprofen 400mg PO q6h PRN
        • Dark, quiet room rest
        • Follow up if symptoms persist >72h or worsen
        """,
        onCopyToClipboard: { print("Copied") },
        onDismiss: { print("Dismissed") }
    )
}

