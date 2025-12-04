import SwiftUI

struct TranscriptView: View {
    let transcript: [TranscriptEntry]
    @Binding var isExpanded: Bool
    
    // Interim (in-progress) transcript for real-time display
    var interimText: String = ""
    var interimSpeaker: String = ""
    var isStreamingConnected: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("TRANSCRIPT")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text("(\(transcript.count))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Streaming status indicator
                if isStreamingConnected {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                    }
                }
                
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
            
            if isExpanded {
                if transcript.isEmpty && interimText.isEmpty {
                    Text("Waiting for speech...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.vertical, 8)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(transcript) { entry in
                                    TranscriptEntryView(entry: entry)
                                        .id(entry.id)
                                }
                                
                                // Show interim (in-progress) transcript in real-time
                                if !interimText.isEmpty {
                                    InterimTranscriptView(text: interimText, speaker: interimSpeaker)
                                        .id("interim")
                                }
                            }
                            .padding(12)
                        }
                        .frame(maxHeight: 200)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .onChange(of: transcript.count) { _, _ in
                            if let lastEntry = transcript.last {
                                withAnimation {
                                    proxy.scrollTo(lastEntry.id, anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: interimText) { _, _ in
                            // Auto-scroll to show interim text
                            if !interimText.isEmpty {
                                withAnimation {
                                    proxy.scrollTo("interim", anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// View for displaying interim (in-progress) transcription
struct InterimTranscriptView: View {
    let text: String
    let speaker: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(speaker.isEmpty ? "..." : speaker)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(speakerColor.opacity(0.7))
                
                // Typing indicator
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.blue.opacity(0.5))
                            .frame(width: 4, height: 4)
                    }
                }
            }
            
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.primary.opacity(0.7))
                .italic()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(6)
    }
    
    private var speakerColor: Color {
        switch speaker {
        case "Physician":
            return .blue
        case "Patient":
            return .green
        default:
            return .secondary
        }
    }
}

struct TranscriptEntryView: View {
    let entry: TranscriptEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.speaker)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(speakerColor)
                
                Text(formatTime(entry.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Text(entry.text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private var speakerColor: Color {
        switch entry.speaker {
        case "Physician":
            return .blue
        case "Patient":
            return .green
        default:
            return .secondary
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

#Preview {
    TranscriptView(
        transcript: [
            TranscriptEntry(speaker: "Patient", text: "I've been having this headache for about three days now."),
            TranscriptEntry(speaker: "Physician", text: "Can you describe the headache? Where exactly does it hurt?"),
            TranscriptEntry(speaker: "Patient", text: "It's mostly on the right side, kind of throbbing.")
        ],
        isExpanded: .constant(true),
        interimText: "It gets worse when I'm in bright light...",
        interimSpeaker: "Patient",
        isStreamingConnected: true
    )
    .padding()
    .frame(width: 380)
}

