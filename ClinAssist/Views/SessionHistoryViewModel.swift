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
    private let llmProvider: LLMProvider
    private let configManager: ConfigManager
    private var billingGenerator: BillingCodeGenerator?
    
    // MARK: - Initialization
    
    init(llmProvider: LLMProvider, configManager: ConfigManager) {
        self.llmProvider = llmProvider
        self.configManager = configManager
        self.billingGenerator = BillingCodeGenerator(llmProvider: llmProvider)
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
            // Build transcript text
            let transcriptText = state.transcript
                .map { "[\($0.speaker)] \($0.text)" }
                .joined(separator: "\n")
            
            debugLog("📝 Transcript: \(state.transcript.count) entries, \(transcriptText.count) chars", component: "History")
            
            // Build clinical notes text
            let clinicalNotesText = state.clinicalNotes
                .map { $0.text }
                .joined(separator: "\n")
            
            // Get the system prompt with options
            let systemPrompt = LLMPrompts.soapRendererWithOptions(
                detailLevel: detailLevel,
                format: format,
                customInstructions: customInstructions
            )
            
            // Build the user prompt
            var userPrompt = "Generate a SOAP note from the following clinical encounter transcript:\n\n"
            userPrompt += transcriptText
            
            if !clinicalNotesText.isEmpty {
                userPrompt += "\n\nClinician's Notes:\n\(clinicalNotesText)"
            }
            
            debugLog("📤 Calling LLM with \(userPrompt.count) char prompt...", component: "History")
            
            // Call LLM
            let newSOAPNote = try await llmProvider.complete(
                systemPrompt: systemPrompt,
                userContent: userPrompt
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

