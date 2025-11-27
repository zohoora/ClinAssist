import SwiftUI

struct EndEncounterSheet: View {
    let soapNote: String
    let onCopyToClipboard: () -> Void
    let onDismiss: () -> Void
    
    @State private var isCopied: Bool = false
    
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
            
            Divider()
            
            // SOAP Note Content
            ScrollView {
                Text(soapNote.isEmpty ? "No SOAP note generated." : soapNote)
                    .font(.system(size: 13, design: .monospaced))
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
                .disabled(soapNote.isEmpty)
                
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
        NSPasteboard.general.setString(soapNote, forType: .string)
        
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

