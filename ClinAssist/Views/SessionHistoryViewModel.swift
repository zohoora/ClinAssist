import Foundation
import SwiftUI

/// ViewModel for SessionHistoryView - manages session loading, SOAP regeneration, and billing code generation
@MainActor
class SessionHistoryViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var selectedDate: Date = Date()
    @Published var sessions: [HistoricalSession] = []
    @Published var selectedSession: HistoricalSession?
    @Published var isLoading: Bool = false
    @Published var isRegenerating: Bool = false
    @Published var isGeneratingCodes: Bool = false
    @Published var billingSuggestion: BillingSuggestion?
    @Published var billingError: String?
    
    // MARK: - Dependencies
    
    private let storage = EncounterStorage.shared
    private let configManager: ConfigManager
    private let llmOrchestrator: LLMOrchestrator
    private var billingGenerator: BillingCodeGenerator?
    
    // MARK: - Initialization
    
    init(configManager: ConfigManager) {
        self.configManager = configManager
        self.llmOrchestrator = LLMOrchestrator(configManager: configManager)
        self.billingGenerator = BillingCodeGenerator()
    }
    
    // MARK: - Session Loading
    
    func loadSessionsForSelectedDate() {
        isLoading = true
        sessions = []
        selectedSession = nil
        billingSuggestion = nil
        billingError = nil
        
        Task {
            let encounterURLs = storage.listEncountersForDate(selectedDate)
            
            var loadedSessions: [HistoricalSession] = []
            
            for url in encounterURLs {
                if let session = loadSession(from: url) {
                    loadedSessions.append(session)
                }
            }
            
            sessions = loadedSessions.sorted { $0.startTime < $1.startTime }
            isLoading = false
            
            // Auto-select first session if available
            if let first = sessions.first {
                selectSession(first)
            }
        }
    }
    
    private func loadSession(from url: URL) -> HistoricalSession? {
        // Load encounter state
        let state = storage.loadEncounter(from: url)
        
        // Load SOAP note
        guard let soapNote = storage.loadSOAPNote(from: url), !soapNote.isEmpty else {
            debugLog("⏭️ Skipping session \(url.lastPathComponent) - no SOAP note", component: "History")
            return nil
        }
        
        // Load transcript
        let transcript = storage.loadTranscript(from: url)
        
        // Parse start time from folder name
        let startTime = storage.parseEncounterTime(from: url) ?? state?.startedAt ?? Date()
        let endTime = state?.endedAt
        
        // Extract patient name
        let patientName = storage.extractPatientIdentifier(from: soapNote)
        
        debugLog("📁 Loaded session: \(patientName) - SOAP: \(soapNote.count) chars, state: \(state != nil ? "✓" : "✗")", component: "History")
        
        return HistoricalSession(
            id: state?.id ?? UUID(),
            folderURL: url,
            startTime: startTime,
            endTime: endTime,
            patientName: patientName,
            soapNote: soapNote,
            transcript: transcript,
            state: state
        )
    }
    
    // MARK: - Session Selection
    
    func selectSession(_ session: HistoricalSession) {
        debugLog("🔘 Selecting session: \(session.patientName), SOAP: \(session.soapNote.count) chars", component: "History")
        selectedSession = session
        billingError = nil
        
        // Load persisted billing codes for this session
        if let savedBillingCodes = storage.loadBillingCodes(from: session.folderURL) {
            billingSuggestion = savedBillingCodes
            debugLog("Loaded persisted billing codes for session", component: "History")
        } else {
            billingSuggestion = nil
        }
    }
    
    // MARK: - SOAP Regeneration
    
    func regenerateSOAP(
        for session: HistoricalSession,
        detailLevel: Int,
        format: SOAPFormat,
        customInstructions: String
    ) async {
        debugLog("🔄 Starting SOAP regeneration for session: \(session.patientName)", component: "History")
        
        guard let state = session.state else {
            debugLog("❌ Cannot regenerate SOAP - no encounter state available", component: "History")
            return
        }
        
        isRegenerating = true
        
        do {
            // Encode state to JSON (same format as SOAPGenerator)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let stateJSON = try encoder.encode(state)
            guard let stateString = String(data: stateJSON, encoding: .utf8) else {
                debugLog("❌ Failed to encode state to string", component: "History")
                isRegenerating = false
                return
            }
            
            debugLog("📝 State JSON: \(stateJSON.count) bytes, \(state.transcript.count) transcript entries", component: "History")
            
            // Get the system prompt with options
            let systemPrompt = LLMPrompts.soapRendererWithOptions(
                detailLevel: detailLevel,
                format: format,
                customInstructions: customInstructions
            )
            
            debugLog("📤 Calling LLMOrchestrator.generateFinalSOAP...", component: "History")
            
            // Use LLMOrchestrator with Final SOAP settings (scenario-based model selection)
            let newSOAPNote = try await llmOrchestrator.generateFinalSOAP(
                systemPrompt: systemPrompt,
                content: stateString,
                transcriptEntryCount: state.transcript.count,
                attachments: []  // Historical sessions don't have attachments for now
            )
            
            debugLog("📥 LLM returned: \(newSOAPNote.count) chars", component: "History")
            
            if newSOAPNote.isEmpty {
                debugLog("⚠️ LLM returned empty SOAP note!", component: "History")
            }
            
            // Update the session with new SOAP note
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                let updatedSession = HistoricalSession(
                    id: session.id,
                    folderURL: session.folderURL,
                    startTime: session.startTime,
                    endTime: session.endTime,
                    patientName: session.patientName,
                    soapNote: newSOAPNote,
                    transcript: session.transcript,
                    state: session.state
                )
                
                sessions[index] = updatedSession
                selectedSession = updatedSession
                debugLog("✅ Updated session and selectedSession with new SOAP note", component: "History")
                
                // Save the regenerated SOAP note to disk
                saveSOAPNote(newSOAPNote, to: session.folderURL)
            } else {
                debugLog("⚠️ Could not find session in sessions array!", component: "History")
            }
            
        } catch {
            debugLog("❌ SOAP regeneration failed: \(error)", component: "History")
        }
        
        isRegenerating = false
        debugLog("🔄 Regeneration complete, isRegenerating = false", component: "History")
    }
    
    private func saveSOAPNote(_ soapNote: String, to encounterPath: URL) {
        let soapPath = encounterPath.appendingPathComponent("soap_note.txt")
        try? soapNote.write(to: soapPath, atomically: true, encoding: .utf8)
        debugLog("Saved regenerated SOAP note to \(soapPath.lastPathComponent)", component: "History")
    }
    
    // MARK: - Billing Code Generation
    
    func generateBillingCodes(for session: HistoricalSession) async {
        guard let generator = billingGenerator else { return }
        
        isGeneratingCodes = true
        billingError = nil
        billingSuggestion = nil
        
        await generator.generateCodes(
            from: session.soapNote,
            encounterDuration: session.duration
        )
        
        if let suggestion = generator.suggestedCodes {
            billingSuggestion = suggestion
            
            // Persist billing codes to disk
            storage.saveBillingCodes(suggestion, to: session.folderURL)
        } else if let error = generator.error {
            billingError = error
        }
        
        isGeneratingCodes = false
    }
}

