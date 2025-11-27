import SwiftUI

struct SOAPView: View {
    let soapNote: String
    let isUpdating: Bool
    
    @State private var scrollPosition: CGFloat = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("SOAP NOTE")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if isUpdating {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                }
            }
            
            // Content
            ScrollView {
                if soapNote.isEmpty {
                    Text("SOAP note will be generated as the encounter progresses...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    Text(soapNote)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
            }
            .frame(maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .animation(.easeInOut(duration: 0.3), value: soapNote)
        }
    }
}

#Preview {
    SOAPView(
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
        isUpdating: false
    )
    .padding()
    .frame(width: 380, height: 500)
}

