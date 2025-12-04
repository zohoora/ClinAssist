import SwiftUI

/// "Psst..." view that displays AI predictions about what information
/// will be useful to the physician shortly based on the current transcript
struct PsstView: View {
    let prediction: PsstPrediction
    let isUpdating: Bool
    
    @State private var isExpanded: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 12)
                        
                        Text("PSST...")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        // Whisper icon
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.purple.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                if isUpdating {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 10, height: 10)
                }
                
                // AI badge
                Text("groq")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(4)
            }
            
            if isExpanded {
                // Content
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: prediction.isEmpty ? "lightbulb" : "lightbulb.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.yellow.opacity(prediction.isEmpty ? 0.5 : 0.9))
                    
                    if prediction.isEmpty {
                        Text("Listening to the conversation...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        Text(prediction.hint ?? "")
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.purple.opacity(0.05),
                            Color.blue.opacity(0.03)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }
}

// MARK: - Prediction Model

struct PsstPrediction: Equatable {
    var hint: String?
    
    var isEmpty: Bool {
        hint?.isEmpty ?? true
    }
    
    init(hint: String? = nil) {
        self.hint = hint
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        PsstView(
            prediction: PsstPrediction(
                hint: "The patient mentioned chest pain - you may want to ask about duration, radiation, and any associated symptoms like shortness of breath or diaphoresis."
            ),
            isUpdating: false
        )
        
        PsstView(
            prediction: PsstPrediction(),
            isUpdating: true
        )
    }
    .padding()
    .frame(width: 380)
}
