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
                    hasLLMError: appDelegate.encounterController.llmError != nil,
                    autoDetectionEnabled: appDelegate.autoDetectionEnabled,
                    silenceDuration: appDelegate.silenceDuration,
                    audioLevel: appDelegate.audioManager.currentAudioLevel
                )
                
                Divider()
                
                // Main content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if (appDelegate.appState == .idle || appDelegate.appState == .monitoring || appDelegate.appState == .buffering) && !appDelegate.showEndEncounterSheet {
                            IdleStateView(
                                appState: appDelegate.appState,
                                autoDetectionEnabled: appDelegate.autoDetectionEnabled,
                                silenceDuration: appDelegate.silenceDuration,
                                audioLevel: appDelegate.audioManager.currentAudioLevel
                            )
                        } else if appDelegate.appState.isActive || appDelegate.appState == .processing {
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
        .frame(minWidth: 320, maxWidth: 600)
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
        .overlay {
            // Auto-end confirmation overlay
            if appDelegate.showAutoEndConfirmation {
                AutoEndConfirmationView(
                    onConfirm: { appDelegate.confirmAutoEnd() },
                    onCancel: { appDelegate.cancelAutoEnd() }
                )
            }
        }
    }
}

// MARK: - Auto-End Confirmation View

struct AutoEndConfirmationView: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            // Confirmation card
            VStack(spacing: 20) {
                // Icon
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                // Title
                Text("End Encounter?")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                // Message
                Text("Silence detected. Would you like to end this encounter?\n\nRecording continues until you confirm.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Indicator that recording continues
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                        .overlay {
                            Circle()
                                .stroke(Color.blue.opacity(0.5), lineWidth: 2)
                                .scaleEffect(1.5)
                                .opacity(0.7)
                        }
                    Text("Still recording...")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.vertical, 8)
                
                // Buttons
                HStack(spacing: 16) {
                    Button(action: onCancel) {
                        Text("Continue")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape)
                    
                    Button(action: onConfirm) {
                        Text("End Encounter")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .keyboardShortcut(.return)
                }
                .padding(.horizontal)
            }
            .padding(24)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            .frame(maxWidth: 320)
            .opacity(opacity)
            .scaleEffect(opacity == 0 ? 0.9 : 1.0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.2)) {
                    opacity = 1
                }
            }
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
    let autoDetectionEnabled: Bool
    let silenceDuration: TimeInterval
    let audioLevel: Float
    
    var body: some View {
        HStack {
            // Status indicator
            Circle()
                .fill(appState.statusColor)
                .frame(width: 10, height: 10)
                .overlay {
                    if appState == .recording || appState == .monitoring {
                        Circle()
                            .stroke(appState.statusColor.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.5)
                            .opacity(0.7)
                            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: appState)
                    }
                }
            
            Text(appState.displayName)
                .font(.system(size: 13, weight: .medium))
            
            // Auto-detection badge
            if autoDetectionEnabled && (appState == .monitoring || appState == .buffering) {
                Text("AUTO")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(4)
            }
            
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
            
            // Silence timer (show during monitoring/active with potential end)
            if appState == .monitoring && silenceDuration > 5 {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 10))
                    Text("\(Int(silenceDuration))s")
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(statusBackgroundColor)
    }
    
    private var statusBackgroundColor: Color {
        switch appState {
        case .recording:
            return Color.blue.opacity(0.1)
        case .paused:
            return Color.yellow.opacity(0.1)
        case .processing:
            return Color.blue.opacity(0.1)
        case .monitoring:
            return Color.green.opacity(0.05)
        case .buffering:
            return Color.orange.opacity(0.1)
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
    let appState: AppState
    let autoDetectionEnabled: Bool
    let silenceDuration: TimeInterval
    let audioLevel: Float
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Icon changes based on monitoring state
            if appState == .monitoring || appState == .buffering {
                MonitoringAnimationView(appState: appState, audioLevel: audioLevel)
            } else {
                Image(systemName: "stethoscope")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            
            VStack(spacing: 8) {
                Text("ClinAssist")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if appState == .monitoring {
                    VStack(spacing: 4) {
                        Text("🎙️ Listening for patient encounter...")
                            .font(.subheadline)
                            .foregroundColor(.green)
                        
                        Text("Will auto-start when clinical conversation detected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if appState == .buffering {
                    VStack(spacing: 4) {
                        Text("🔍 Analyzing speech...")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                        
                        Text("Checking if this is a clinical encounter")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Ready to start a new encounter")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Audio level indicator when monitoring
            if appState == .monitoring || appState == .buffering {
                AudioLevelIndicator(level: audioLevel)
                    .frame(height: 30)
                    .padding(.horizontal, 40)
            }
            
            VStack(spacing: 4) {
                Text("Press **⌃⌥S** to start manually")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if !autoDetectionEnabled {
                    Text("or click the button below")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Monitoring Animation View

struct MonitoringAnimationView: View {
    let appState: AppState
    let audioLevel: Float
    
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Outer pulse rings
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(ringColor.opacity(0.3 - Double(index) * 0.1), lineWidth: 2)
                    .frame(width: 70 + CGFloat(index) * 20, height: 70 + CGFloat(index) * 20)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .opacity(isAnimating ? 0.3 : 0.6)
                    .animation(
                        .easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
            
            // Center icon
            Image(systemName: appState == .monitoring ? "ear.badge.waveform" : "waveform.circle")
                .font(.system(size: 48))
                .foregroundColor(ringColor)
                .scaleEffect(1.0 + CGFloat(audioLevel) * 2)
                .animation(.easeInOut(duration: 0.1), value: audioLevel)
        }
        .onAppear {
            isAnimating = true
        }
    }
    
    private var ringColor: Color {
        appState == .buffering ? .orange : .green
    }
}

// MARK: - Audio Level Indicator

struct AudioLevelIndicator: View {
    let level: Float
    
    private let barCount = 20
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(for: index))
                    .frame(width: 8)
                    .scaleEffect(y: barHeight(for: index), anchor: .bottom)
                    .animation(.easeOut(duration: 0.05), value: level)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let normalizedLevel = CGFloat(min(level * 10, 1.0))  // Amplify for visibility
        let threshold = CGFloat(index) / CGFloat(barCount)
        
        if normalizedLevel > threshold {
            return 0.3 + (normalizedLevel - threshold) * 2
        } else {
            return 0.1
        }
    }
    
    private func barColor(for index: Int) -> Color {
        let normalizedLevel = CGFloat(min(level * 10, 1.0))
        let threshold = CGFloat(index) / CGFloat(barCount)
        
        if normalizedLevel > threshold {
            if index < barCount / 3 {
                return .green
            } else if index < barCount * 2 / 3 {
                return .yellow
            } else {
                return .orange
            }
        } else {
            return Color.gray.opacity(0.2)
        }
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
                isExpanded: $transcriptExpanded,
                interimText: encounterController.interimTranscript,
                interimSpeaker: encounterController.interimSpeaker,
                isStreamingConnected: encounterController.isStreamingConnected
            )
            
            // Clinical Notes Input (for manual observations/procedures)
            ClinicalNotesInputView(encounterController: encounterController)
            
            // SOAP Note Section
            SOAPView(
                soapNote: encounterController.soapNote,
                isUpdating: false
            )
            
            // Assistant Section
            HelperPanelView(
                suggestions: encounterController.helperSuggestions
            )
            
            // Chat Section (Gemini 3 Pro)
            ChatView(encounterController: encounterController)
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
            
            // Auto-detection toggle (when available)
            if appDelegate.configManager.config?.autoDetection != nil && !appDelegate.appState.isActive {
                HStack {
                    Toggle(isOn: Binding(
                        get: { appDelegate.autoDetectionEnabled },
                        set: { newValue in
                            if newValue {
                                appDelegate.startAutoDetection()
                            } else {
                                appDelegate.stopAutoDetection()
                            }
                        }
                    )) {
                        HStack(spacing: 4) {
                            Image(systemName: "ear.badge.waveform")
                                .font(.system(size: 12))
                            Text("Auto-detect encounters")
                                .font(.caption)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
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
        case .monitoring:
            return "Start Encounter Manually"
        case .buffering:
            return "Start Encounter Now"
        case .recording, .paused:
            return "End Encounter"
        case .processing:
            return "Processing..."
        }
    }
    
    private var buttonIcon: String {
        switch appDelegate.appState {
        case .idle, .monitoring, .buffering:
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
        case .monitoring, .buffering:
            return .green
        case .recording, .paused:
            return .orange
        case .processing:
            return .gray
        }
    }
}

#Preview {
    MainWindowView(appDelegate: AppDelegate())
        .frame(width: 380, height: 700)
}
