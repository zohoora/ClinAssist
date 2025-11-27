import SwiftUI

struct MainWindowView: View {
    @ObservedObject var appDelegate: AppDelegate
    
    @State private var transcriptExpanded: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Check if configured
            if !appDelegate.configManager.isConfigured {
                SetupView(configManager: appDelegate.configManager) {
                    appDelegate.configManager.loadConfig()
                }
            } else {
                // Status Bar
                StatusBarView(
                    appState: appDelegate.appState,
                    duration: appDelegate.encounterDuration,
                    isTranscribing: appDelegate.encounterController.isTranscribing,
                    hasTranscriptionError: appDelegate.encounterController.transcriptionError != nil,
                    hasLLMError: appDelegate.encounterController.llmError != nil
                )
                
                Divider()
                
                // Main content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if appDelegate.appState == .idle && !appDelegate.showEndEncounterSheet {
                            IdleStateView()
                        } else {
                            ActiveEncounterView(
                                encounterController: appDelegate.encounterController,
                                transcriptExpanded: $transcriptExpanded
                            )
                        }
                    }
                    .padding()
                }
                
                Divider()
                
                // Bottom action button
                BottomActionView(appDelegate: appDelegate)
            }
        }
        .frame(minWidth: 380, maxWidth: 380)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $appDelegate.showEndEncounterSheet) {
            EndEncounterSheet(
                soapNote: appDelegate.encounterController.soapNote,
                onCopyToClipboard: {
                    // Already handled in the sheet
                },
                onDismiss: {
                    appDelegate.dismissEndEncounterSheet()
                }
            )
        }
    }
}

// MARK: - Status Bar

struct StatusBarView: View {
    let appState: AppState
    let duration: TimeInterval
    let isTranscribing: Bool
    let hasTranscriptionError: Bool
    let hasLLMError: Bool
    
    var body: some View {
        HStack {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .overlay {
                    if appState == .recording {
                        Circle()
                            .stroke(statusColor.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.5)
                            .opacity(0.7)
                            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: appState)
                    }
                }
            
            Text(appState.displayName)
                .font(.system(size: 13, weight: .medium))
            
            // Transcribing indicator
            if isTranscribing {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            }
            
            // Error indicators
            if hasTranscriptionError {
                Image(systemName: "waveform.badge.exclamationmark")
                    .font(.system(size: 12))
                    .foregroundColor(.yellow)
                    .help("Transcription issue")
            }
            
            if hasLLMError {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 12))
                    .foregroundColor(.yellow)
                    .help("Assistant issue")
            }
            
            Spacer()
            
            // Duration (only show during active encounter)
            if appState == .recording || appState == .paused {
                Text(formatDuration(duration))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(statusBackgroundColor)
    }
    
    private var statusColor: Color {
        switch appState {
        case .idle:
            return .gray
        case .recording:
            return .red
        case .paused:
            return .yellow
        case .processing:
            return .blue
        }
    }
    
    private var statusBackgroundColor: Color {
        switch appState {
        case .recording:
            return Color.red.opacity(0.1)
        case .paused:
            return Color.yellow.opacity(0.1)
        case .processing:
            return Color.blue.opacity(0.1)
        default:
            return Color.clear
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

// MARK: - Idle State View

struct IdleStateView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "stethoscope")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.5))
            
            VStack(spacing: 8) {
                Text("ClinAssist")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Ready to start a new encounter")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 4) {
                Text("Press **⌃⌥S** to start")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("or click the button below")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Active Encounter View

struct ActiveEncounterView: View {
    @ObservedObject var encounterController: EncounterController
    @Binding var transcriptExpanded: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Transcript Section
            TranscriptView(
                transcript: encounterController.state?.transcript ?? [],
                isExpanded: $transcriptExpanded
            )
            
            // SOAP Note Section
            SOAPView(
                soapNote: encounterController.soapNote,
                isUpdating: false
            )
            .frame(minHeight: 200)
            
            // Assistant Section
            HelperPanelView(
                suggestions: encounterController.helperSuggestions,
                issues: encounterController.state?.issuesMentioned ?? []
            )
        }
    }
}

// MARK: - Bottom Action View

struct BottomActionView: View {
    @ObservedObject var appDelegate: AppDelegate
    
    var body: some View {
        VStack(spacing: 0) {
            // Microphone permission warning if needed
            if !appDelegate.audioManager.permissionGranted {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("Microphone access required")
                        .font(.caption)
                    Spacer()
                    Button("Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.yellow.opacity(0.1))
            }
            
            Button(action: {
                appDelegate.toggleEncounter()
            }) {
                HStack {
                    if appDelegate.appState == .processing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: buttonIcon)
                    }
                    
                    Text(buttonTitle)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(buttonColor)
            .disabled(appDelegate.appState == .processing || (!appDelegate.audioManager.permissionGranted && appDelegate.appState == .idle))
            .padding(16)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var buttonTitle: String {
        switch appDelegate.appState {
        case .idle:
            return "Start Encounter"
        case .recording, .paused:
            return "End Encounter"
        case .processing:
            return "Processing..."
        }
    }
    
    private var buttonIcon: String {
        switch appDelegate.appState {
        case .idle:
            return "play.fill"
        case .recording, .paused:
            return "stop.fill"
        case .processing:
            return "hourglass"
        }
    }
    
    private var buttonColor: Color {
        switch appDelegate.appState {
        case .idle:
            return .blue
        case .recording, .paused:
            return .red
        case .processing:
            return .gray
        }
    }
}

#Preview {
    MainWindowView(appDelegate: AppDelegate())
        .frame(width: 380, height: 700)
}
