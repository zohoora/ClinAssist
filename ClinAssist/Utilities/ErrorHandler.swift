import Foundation
import SwiftUI

// MARK: - App Error Types

/// Unified error type that wraps all domain-specific errors in the application
enum AppError: LocalizedError, Identifiable {
    case audio(AudioError)
    case transcription(STTError)
    case streaming(StreamingSTTError)
    case llm(LLMProviderError)
    case encounter(EncounterError)
    case configuration(ConfigurationError)
    case general(String)
    
    var id: String {
        switch self {
        case .audio(let error): return "audio_\(error.localizedDescription)"
        case .transcription(let error): return "transcription_\(error.localizedDescription)"
        case .streaming(let error): return "streaming_\(error.localizedDescription)"
        case .llm(let error): return "llm_\(error.localizedDescription)"
        case .encounter(let error): return "encounter_\(error.localizedDescription)"
        case .configuration(let error): return "config_\(error.localizedDescription)"
        case .general(let message): return "general_\(message)"
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .audio(let error):
            return error.localizedDescription
        case .transcription(let error):
            return error.localizedDescription
        case .streaming(let error):
            return error.localizedDescription
        case .llm(let error):
            return error.localizedDescription
        case .encounter(let error):
            return error.localizedDescription
        case .configuration(let error):
            return error.localizedDescription
        case .general(let message):
            return message
        }
    }
    
    var category: ErrorCategory {
        switch self {
        case .audio:
            return .audio
        case .transcription, .streaming:
            return .transcription
        case .llm:
            return .llm
        case .encounter:
            return .encounter
        case .configuration:
            return .configuration
        case .general:
            return .general
        }
    }
    
    var severity: ErrorSeverity {
        switch self {
        case .audio(.permissionDenied):
            return .critical
        case .configuration:
            return .critical
        case .llm(.invalidAPIKey):
            return .critical
        case .transcription(.invalidAPIKey):
            return .critical
        case .streaming(.connectionFailed):
            return .warning
        case .llm(.requestFailed):
            return .warning
        default:
            return .info
        }
    }
    
    var suggestedAction: String? {
        switch self {
        case .audio(.permissionDenied):
            return "Go to System Settings > Privacy & Security > Microphone to grant access."
        case .configuration(.missingFile):
            return "Create a config.json file in ~/Dropbox/livecode_records/"
        case .configuration(.invalidFormat):
            return "Check your config.json file for syntax errors."
        case .llm(.invalidAPIKey):
            return "Verify your API key in the config file."
        case .transcription(.invalidAPIKey):
            return "Verify your Deepgram API key in the config file."
        case .streaming(.connectionFailed):
            return "Check your internet connection and try again."
        default:
            return nil
        }
    }
}

// MARK: - Error Categories

enum ErrorCategory: String {
    case audio = "Audio"
    case transcription = "Transcription"
    case llm = "AI Processing"
    case encounter = "Encounter"
    case configuration = "Configuration"
    case general = "General"
    
    var icon: String {
        switch self {
        case .audio: return "mic.slash"
        case .transcription: return "waveform.badge.exclamationmark"
        case .llm: return "brain.head.profile"
        case .encounter: return "stethoscope"
        case .configuration: return "gearshape.2"
        case .general: return "exclamationmark.triangle"
        }
    }
    
    var color: Color {
        switch self {
        case .audio: return .red
        case .transcription: return .orange
        case .llm: return .purple
        case .encounter: return .blue
        case .configuration: return .yellow
        case .general: return .gray
        }
    }
}

// MARK: - Error Severity

enum ErrorSeverity {
    case info       // Informational, non-blocking
    case warning    // Something went wrong but app can continue
    case critical   // Requires user action to proceed
    
    var icon: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .critical: return "exclamationmark.octagon"
        }
    }
    
    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Encounter-Specific Errors

enum EncounterError: LocalizedError {
    case notStarted
    case alreadyInProgress
    case noTranscript
    case saveFailed(String)
    case audioSetupFailed(String)
    case transcriptionFailed(String)
    case soapGenerationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notStarted:
            return "No encounter is currently active."
        case .alreadyInProgress:
            return "An encounter is already in progress."
        case .noTranscript:
            return "No transcript available to generate SOAP note."
        case .saveFailed(let reason):
            return "Failed to save encounter: \(reason)"
        case .audioSetupFailed(let reason):
            return "Failed to start audio recording: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription error: \(reason)"
        case .soapGenerationFailed(let reason):
            return "Failed to generate SOAP note: \(reason)"
        }
    }
}

// MARK: - Configuration Errors

enum ConfigurationError: LocalizedError {
    case missingFile
    case invalidFormat(String)
    case missingRequiredField(String)
    
    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "Configuration file not found."
        case .invalidFormat(let details):
            return "Invalid configuration format: \(details)"
        case .missingRequiredField(let field):
            return "Missing required configuration field: \(field)"
        }
    }
}

// MARK: - Error Handler

/// Centralized error handler for the application
/// Publishes errors for display in the UI and logs them for debugging
@MainActor
class ErrorHandler: ObservableObject {
    static let shared = ErrorHandler()
    
    /// Current error to display (nil when no active error)
    @Published var currentError: AppError?
    
    /// Whether to show the error alert
    @Published var showingAlert: Bool = false
    
    /// History of recent errors (for debugging)
    @Published private(set) var errorHistory: [ErrorHistoryEntry] = []
    
    /// Maximum number of errors to keep in history
    private let maxHistorySize = 50
    
    private init() {}
    
    // MARK: - Error Reporting
    
    /// Report an error to be displayed to the user
    func report(_ error: AppError, showAlert: Bool = true) {
        currentError = error
        
        // Add to history
        let entry = ErrorHistoryEntry(error: error, timestamp: Date())
        errorHistory.insert(entry, at: 0)
        if errorHistory.count > maxHistorySize {
            errorHistory.removeLast()
        }
        
        // Log the error
        debugLog("ERROR [\(error.category.rawValue)]: \(error.localizedDescription ?? "Unknown error")", component: "ErrorHandler", type: .error)
        
        // Show alert for non-info severity
        if showAlert && error.severity != .info {
            showingAlert = true
        }
    }
    
    /// Report an error from a specific domain error type
    func report(audio error: AudioError, showAlert: Bool = true) {
        report(.audio(error), showAlert: showAlert)
    }
    
    func report(transcription error: STTError, showAlert: Bool = true) {
        report(.transcription(error), showAlert: showAlert)
    }
    
    func report(streaming error: StreamingSTTError, showAlert: Bool = true) {
        report(.streaming(error), showAlert: showAlert)
    }
    
    func report(llm error: LLMProviderError, showAlert: Bool = true) {
        report(.llm(error), showAlert: showAlert)
    }
    
    func report(encounter error: EncounterError, showAlert: Bool = true) {
        report(.encounter(error), showAlert: showAlert)
    }
    
    func report(configuration error: ConfigurationError, showAlert: Bool = true) {
        report(.configuration(error), showAlert: showAlert)
    }
    
    func report(message: String, showAlert: Bool = true) {
        report(.general(message), showAlert: showAlert)
    }
    
    // MARK: - Error Clearing
    
    /// Clear the current error
    func clearError() {
        currentError = nil
        showingAlert = false
    }
    
    /// Clear error history
    func clearHistory() {
        errorHistory.removeAll()
    }
    
    // MARK: - Convenience Methods
    
    /// Check if there's an active critical error
    var hasCriticalError: Bool {
        currentError?.severity == .critical
    }
    
    /// Get the most recent error of a specific category
    func lastError(in category: ErrorCategory) -> AppError? {
        errorHistory.first { $0.error.category == category }?.error
    }
}

// MARK: - Error History Entry

struct ErrorHistoryEntry: Identifiable {
    let id = UUID()
    let error: AppError
    let timestamp: Date
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

// MARK: - SwiftUI Error Alert Modifier

struct ErrorAlertModifier: ViewModifier {
    @ObservedObject var errorHandler: ErrorHandler
    
    func body(content: Content) -> some View {
        content
            .alert(
                errorHandler.currentError?.category.rawValue ?? "Error",
                isPresented: $errorHandler.showingAlert,
                presenting: errorHandler.currentError
            ) { error in
                Button("OK") {
                    errorHandler.clearError()
                }
                
                if let action = error.suggestedAction, error.category == .audio {
                    Button("Open Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                        errorHandler.clearError()
                    }
                }
            } message: { error in
                VStack {
                    Text(error.localizedDescription ?? "An unknown error occurred.")
                    if let action = error.suggestedAction {
                        Text(action)
                            .font(.caption)
                    }
                }
            }
    }
}

extension View {
    /// Adds error alert handling to a view
    func withErrorHandling(_ errorHandler: ErrorHandler = .shared) -> some View {
        modifier(ErrorAlertModifier(errorHandler: errorHandler))
    }
}

// MARK: - Error Banner View

/// A non-intrusive error banner that can be displayed at the top of a view
struct ErrorBannerView: View {
    let error: AppError
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: error.severity.icon)
                .foregroundColor(error.severity.color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(error.category.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Text(error.localizedDescription ?? "Unknown error")
                    .font(.subheadline)
            }
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(error.severity.color.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(error.severity.color.opacity(0.3), lineWidth: 1)
        )
    }
}
