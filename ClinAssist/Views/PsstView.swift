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
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 10, height: 10)
                        Text("thinking...")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                
                // Local AI badge
                Text("qwen3")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.15))
                    .cornerRadius(4)
            }
            
            if isExpanded {
                // Content
                VStack(alignment: .leading, spacing: 12) {
                    if prediction.isEmpty {
                        HStack {
                            Image(systemName: "lightbulb")
                                .font(.system(size: 14))
                                .foregroundColor(.yellow.opacity(0.7))
                            Text("Listening to the conversation...")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .italic()
                        }
                        .padding(12)
                    } else {
                        // What's likely coming next
                        if let nextTopic = prediction.likelyNextTopic, !nextTopic.isEmpty {
                            PsstSection(
                                icon: "arrow.forward.circle.fill",
                                iconColor: .blue,
                                title: "Coming up",
                                content: nextTopic
                            )
                        }
                        
                        // Questions the physician might want to ask
                        if !prediction.anticipatedQuestions.isEmpty {
                            PsstListSection(
                                icon: "questionmark.circle.fill",
                                iconColor: .orange,
                                title: "You might ask",
                                items: prediction.anticipatedQuestions
                            )
                        }
                        
                        // Info that would be useful to know
                        if !prediction.usefulInfo.isEmpty {
                            PsstListSection(
                                icon: "info.circle.fill",
                                iconColor: .green,
                                title: "Good to know",
                                items: prediction.usefulInfo
                            )
                        }
                        
                        // Potential concerns to watch for
                        if !prediction.watchFor.isEmpty {
                            PsstListSection(
                                icon: "exclamationmark.triangle.fill",
                                iconColor: .red,
                                title: "Watch for",
                                items: prediction.watchFor
                            )
                        }
                    }
                }
                .padding(12)
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

// MARK: - Psst Section Components

struct PsstSection: View {
    let icon: String
    let iconColor: Color
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            
            Text(content)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 17)
        }
    }
}

struct PsstListSection: View {
    let icon: String
    let iconColor: Color
    let title: String
    let items: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(iconColor.opacity(0.7))
                        Text(item)
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 17)
        }
    }
}

// MARK: - Prediction Model

struct PsstPrediction: Codable, Equatable {
    var likelyNextTopic: String?
    var anticipatedQuestions: [String]
    var usefulInfo: [String]
    var watchFor: [String]
    
    var isEmpty: Bool {
        (likelyNextTopic?.isEmpty ?? true) &&
        anticipatedQuestions.isEmpty &&
        usefulInfo.isEmpty &&
        watchFor.isEmpty
    }
    
    enum CodingKeys: String, CodingKey {
        case likelyNextTopic = "likely_next_topic"
        case anticipatedQuestions = "anticipated_questions"
        case usefulInfo = "useful_info"
        case watchFor = "watch_for"
    }
    
    init(
        likelyNextTopic: String? = nil,
        anticipatedQuestions: [String] = [],
        usefulInfo: [String] = [],
        watchFor: [String] = []
    ) {
        self.likelyNextTopic = likelyNextTopic
        self.anticipatedQuestions = anticipatedQuestions
        self.usefulInfo = usefulInfo
        self.watchFor = watchFor
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        PsstView(
            prediction: PsstPrediction(
                likelyNextTopic: "Discussion of treatment options and medication dosing",
                anticipatedQuestions: [
                    "Any allergies to antibiotics?",
                    "Previous reactions to NSAIDs?"
                ],
                usefulInfo: [
                    "Amoxicillin: 500mg TID x 10 days for strep",
                    "Consider rapid strep test if not done"
                ],
                watchFor: [
                    "Signs of peritonsillar abscess",
                    "Difficulty swallowing liquids"
                ]
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

