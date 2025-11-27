import Foundation
import Combine

class EncounterController: ObservableObject {
    @Published var state: EncounterState?
    @Published var helperSuggestions: HelperSuggestions = HelperSuggestions()
    @Published var soapNote: String = ""
    @Published var isTranscribing: Bool = false
    @Published var transcriptionError: String?
    @Published var llmError: String?
    
    private let audioManager: AudioManager
    private let configManager: ConfigManager
    private var sttClient: STTClient?
    private var llmClient: LLMClient?
    
    private var transcriptionTask: Task<Void, Never>?
    private var stateUpdateTask: Task<Void, Never>?
    private var soapUpdateTask: Task<Void, Never>?
    
    private var pendingChunks: [URL] = []
    private var lastTranscriptIndex: Int = 0
    
    init(audioManager: AudioManager, configManager: ConfigManager) {
        self.audioManager = audioManager
        self.configManager = configManager
        
        audioManager.delegate = self
        
        setupClients()
    }
    
    private func setupClients() {
        guard let config = configManager.config else { return }
        
        sttClient = DeepgramRESTClient(apiKey: config.deepgramApiKey)
        llmClient = LLMClient(apiKey: config.openrouterApiKey, model: config.model)
    }
    
    // MARK: - Encounter Lifecycle
    
    func startEncounter() {
        let encounterId = UUID()
        state = EncounterState(id: encounterId)
        helperSuggestions = HelperSuggestions()
        soapNote = ""
        lastTranscriptIndex = 0
        pendingChunks = []
        transcriptionError = nil
        llmError = nil
        
        do {
            try audioManager.startRecording(encounterId: encounterId)
            startUpdateTasks()
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
    
    func endEncounter() async {
        // Stop all tasks first
        stopUpdateTasks()
        audioManager.stopRecording()
        
        state?.endedAt = Date()
        
        // Process any remaining chunks
        await processRemainingChunks()
        
        // Generate final SOAP note
        await generateFinalSOAP()
    }
    
    func pauseEncounter() {
        audioManager.pauseRecording()
        stopUpdateTasks()
    }
    
    func resumeEncounter() {
        audioManager.resumeRecording()
        startUpdateTasks()
    }
    
    // MARK: - Update Tasks
    
    private func startUpdateTasks() {
        guard let config = configManager.config else { return }
        
        let transcriptionInterval = TimeInterval(config.timing.transcriptionIntervalSeconds)
        let helperInterval = TimeInterval(config.timing.helperUpdateIntervalSeconds)
        let soapInterval = TimeInterval(config.timing.soapUpdateIntervalSeconds)
        
        // Transcription task runs based on audio chunks (handled by delegate)
        
        // State/Helper update task
        stateUpdateTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(helperInterval))
                guard !Task.isCancelled else { break }
                await updateStateAndHelpers()
            }
        }
        
        // SOAP update task
        soapUpdateTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(soapInterval))
                guard !Task.isCancelled else { break }
                await updateSOAPNote()
            }
        }
    }
    
    private func stopUpdateTasks() {
        transcriptionTask?.cancel()
        stateUpdateTask?.cancel()
        soapUpdateTask?.cancel()
        
        transcriptionTask = nil
        stateUpdateTask = nil
        soapUpdateTask = nil
    }
    
    // MARK: - Transcription
    
    private func transcribeChunk(_ chunkURL: URL) async {
        guard let sttClient = sttClient else { return }
        
        do {
            let audioData = try Data(contentsOf: chunkURL)
            isTranscribing = true
            transcriptionError = nil
            
            let segments = try await sttClient.transcribe(audioData: audioData)
            
            await MainActor.run {
                for segment in segments {
                    let entry = TranscriptEntry(
                        timestamp: segment.timestamp,
                        speaker: segment.speaker,
                        text: segment.text
                    )
                    self.state?.transcript.append(entry)
                }
                self.isTranscribing = false
            }
        } catch {
            await MainActor.run {
                self.isTranscribing = false
                self.transcriptionError = error.localizedDescription
            }
            print("Transcription error: \(error)")
        }
    }
    
    private func processRemainingChunks() async {
        for chunk in pendingChunks {
            await transcribeChunk(chunk)
        }
        pendingChunks = []
    }
    
    // MARK: - LLM Updates
    
    private func updateStateAndHelpers() async {
        guard let llmClient = llmClient, let state = state else { return }
        
        // Get new transcript since last update
        let newTranscript = Array(state.transcript.dropFirst(lastTranscriptIndex))
        guard !newTranscript.isEmpty else { return }
        
        lastTranscriptIndex = state.transcript.count
        
        let transcriptText = newTranscript.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        
        // Update helper suggestions
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let stateJSON = try encoder.encode(state)
            let stateString = String(data: stateJSON, encoding: .utf8) ?? "{}"
            
            let userContent = """
            Current state:
            \(stateString)
            
            New transcript:
            \(transcriptText)
            """
            
            let response = try await llmClient.complete(
                systemPrompt: LLMPrompts.helperSuggestions,
                userContent: userContent
            )
            
            // Parse helper suggestions
            if let suggestions = safeParse(response, as: HelperSuggestions.self) {
                await MainActor.run {
                    self.helperSuggestions = suggestions
                    self.llmError = nil
                }
            }
        } catch {
            await MainActor.run {
                self.llmError = error.localizedDescription
            }
            print("Helper update error: \(error)")
        }
    }
    
    private func updateSOAPNote() async {
        guard let llmClient = llmClient, let state = state else { return }
        guard !state.transcript.isEmpty else { return }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let stateJSON = try encoder.encode(state)
            let stateString = String(data: stateJSON, encoding: .utf8) ?? "{}"
            
            let response = try await llmClient.complete(
                systemPrompt: LLMPrompts.soapRenderer,
                userContent: stateString
            )
            
            await MainActor.run {
                self.soapNote = response
                self.llmError = nil
            }
        } catch {
            await MainActor.run {
                self.llmError = error.localizedDescription
            }
            print("SOAP update error: \(error)")
        }
    }
    
    private func generateFinalSOAP() async {
        // Force a final SOAP generation
        await updateSOAPNote()
    }
    
    // MARK: - Helpers
    
    private func safeParse<T: Decodable>(_ jsonString: String, as type: T.Type) -> T? {
        // Try to extract JSON from markdown code blocks if present
        var cleanedJSON = jsonString
        if cleanedJSON.contains("```json") {
            cleanedJSON = cleanedJSON
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if cleanedJSON.contains("```") {
            cleanedJSON = cleanedJSON
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard let data = cleanedJSON.data(using: .utf8) else { return nil }
        
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            print("JSON parsing failed: \(error)")
            return nil
        }
    }
}

// MARK: - AudioManagerDelegate

extension EncounterController: AudioManagerDelegate {
    func audioManager(_ manager: AudioManager, didSaveChunk chunkURL: URL, chunkNumber: Int) {
        pendingChunks.append(chunkURL)
        
        // Transcribe immediately
        Task {
            await transcribeChunk(chunkURL)
            pendingChunks.removeAll { $0 == chunkURL }
        }
    }
    
    func audioManager(_ manager: AudioManager, didEncounterError error: Error) {
        print("Audio error: \(error)")
    }
}

