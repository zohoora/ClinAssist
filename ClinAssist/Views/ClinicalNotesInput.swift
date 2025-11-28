import SwiftUI

struct ClinicalNotesInputView: View {
    @ObservedObject var encounterController: EncounterController
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var isExpanded: Bool = true
    
    var clinicalNotes: [ClinicalNote] {
        encounterController.state?.clinicalNotes ?? []
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("CLINICAL NOTES")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text("(\(clinicalNotes.count))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Spacer()
                
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
                VStack(spacing: 8) {
                    // Input field
                    HStack(spacing: 8) {
                        TextField("Add note (exam finding, procedure, etc.)", text: $inputText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                            .focused($isInputFocused)
                            .onSubmit {
                                submitNote()
                            }
                        
                        Button(action: submitNote) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    
                    // List of entered notes
                    if !clinicalNotes.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(clinicalNotes) { note in
                                    ClinicalNoteRow(note: note)
                                }
                            }
                        }
                        .frame(maxHeight: 120)
                    }
                    
                    // Helper text
                    Text("Press Enter or + to add. Notes are integrated into SOAP.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            }
        }
    }
    
    private func submitNote() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        encounterController.addClinicalNote(trimmed)
        inputText = ""
        isInputFocused = true
    }
}

struct ClinicalNoteRow: View {
    let note: ClinicalNote
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 10))
                .foregroundColor(.blue)
                .frame(width: 14)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(note.text)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(formatTime(note.timestamp))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

#Preview {
    ClinicalNotesInputView(encounterController: EncounterController(
        audioManager: AudioManager(),
        configManager: ConfigManager.shared
    ))
    .padding()
    .frame(width: 380)
}

