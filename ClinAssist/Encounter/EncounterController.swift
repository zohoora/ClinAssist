import Foundation
import Combine

@MainActor
class EncounterController: ObservableObject {
    @Published var state: EncounterState?
    
    /// SOAP note - proxied from SOAPGenerator for backward compatibility
    var soapNote: String {
        get { soapGenerator.soapNote }
        set { soapGenerator.soapNote = newValue }
    }
    
    /// SOAP generator handles all SOAP note generation
    let soapGenerator: SOAPGenerator
    
    // Saved state for regeneration (preserved after encounter ends, even if new provisional recording starts)
    private var savedStateForRegeneration: EncounterState?
    @Published var isTranscribing: Bool = false
    @Published var transcriptionError: String?
    @Published var llmError: String?
    @Published var ollamaAvailable: Bool = false
    
    /// Error handler for unified error reporting
    private let errorHandler = ErrorHandler.shared
    
    // Psst... prediction state (local AI anticipatory suggestions)
    @Published var psstPrediction: PsstPrediction = PsstPrediction()
    @Published var isPsstUpdating: Bool = false
    
    // Streaming transcription state
    @Published var interimTranscript: String = ""  // Current interim result (may change)
    @Published var interimSpeaker: String = ""     // Speaker for interim result
    @Published var isStreamingConnected: Bool = false
    
    // Encounter attachments (from Chat section - images, PDFs, etc.)
    @Published var encounterAttachments: [EncounterAttachment] = []
    
    let audioManager: AudioManager
    private let configManager: ConfigManager
    private var sttClient: STTClient?              // REST client (fallback)
    private var streamingClient: StreamingSTTClient?  // WebSocket streaming client (protocol for testability)
    var llmClient: LLMClient?           // Cloud LLM (OpenRouter)
    var ollamaClient: OllamaClient?     // Local LLM (Ollama)
    var groqClient: GroqClient?         // Fast LLM (Groq) for final SOAP
    private var llmOrchestrator: LLMOrchestrator?  // Orchestrates LLM selection
    
    private var transcriptionTask: Task<Void, Never>?
    private var stateUpdateTask: Task<Void, Never>?
    private var psstUpdateTask: Task<Void, Never>?
    
    private var pendingChunks: [URL] = []
    private var lastTranscriptIndex: Int = 0
    private var audioLevelLogCount: Int = 0
    private var audioSampleLogCount: Int = 0
    
    // Track if we're using streaming mode
    private var useStreaming: Bool = true
    private var streamingWasUsedInSession: Bool = false  // Track if streaming worked during this session
    
    // Session detector for auto-detection
    let sessionDetector: SessionDetector
    
    // Provisional recording state (for LLM-based start detection)
    private var isProvisionalRecording = false
    private var provisionalEncounterId: UUID?
    
    // Delegate for state changes
    weak var delegate: EncounterControllerDelegate?
    
    // MARK: - Injected dependencies for testing
    private var injectedSTTClient: STTClient?
    private var injectedStreamingClient: StreamingSTTClient?
    
    /// Primary initializer for production use
    init(audioManager: AudioManager, configManager: ConfigManager) {
        self.audioManager = audioManager
        self.configManager = configManager
        self.injectedSTTClient = nil
        self.injectedStreamingClient = nil
        
        // Initialize SOAP generator
        self.soapGenerator = SOAPGenerator(configManager: configManager)
        
        // Build session detector config from config manager
        let detectorConfig = configManager.buildSessionDetectorConfig()
        self.sessionDetector = SessionDetector(config: detectorConfig)
        
        audioManager.delegate = self
        sessionDetector.delegate = self
        
        setupClients()
    }
    
    /// Testing initializer with dependency injection
    init(
        audioManager: AudioManager,
        configManager: ConfigManager,
        sttClient: STTClient? = nil,
        streamingClient: StreamingSTTClient? = nil,
        llmClient: LLMClient? = nil,
        ollamaClient: OllamaClient? = nil
    ) {
        self.audioManager = audioManager
        self.configManager = configManager
        self.injectedSTTClient = sttClient
        self.injectedStreamingClient = streamingClient
        self.llmClient = llmClient
        self.ollamaClient = ollamaClient
        
        // Initialize SOAP generator
        self.soapGenerator = SOAPGenerator(configManager: configManager)
        
        // Build session detector config from config manager
        let detectorConfig = configManager.buildSessionDetectorConfig()
        self.sessionDetector = SessionDetector(config: detectorConfig)
        
        audioManager.delegate = self
        sessionDetector.delegate = self
        
        setupClients()
    }
    
    private func setupClients() {
        guard let config = configManager.config else { return }
        
        // Determine streaming mode from config
        useStreaming = configManager.useDeepgramStreaming
        
        // Configure AudioManager for streaming mode
        audioManager.streamingEnabled = useStreaming
        audioManager.saveAudioBackup = configManager.saveAudioBackup
        
        // Setup REST STT client (use injected or create new)
        if let injected = injectedSTTClient {
            sttClient = injected
        } else {
        sttClient = DeepgramRESTClient(apiKey: config.deepgramApiKey)
        }
        
        // Setup streaming STT client if enabled
        debugLog("🔧 Deepgram config: useStreaming=\(useStreaming), saveAudioBackup=\(configManager.saveAudioBackup)", component: "Encounter")
        if useStreaming {
            if let injected = injectedStreamingClient {
                streamingClient = injected
                streamingClient?.delegate = self
            } else {
                let client = DeepgramStreamingClient(
                    apiKey: config.deepgramApiKey,
                    model: "nova-3-medical",
                    language: "en",
                    enableInterimResults: configManager.showInterimResults,
                    enableDiarization: true
                )
                client.delegate = self
                streamingClient = client
            }
            debugLog("🎤 Streaming mode ENABLED - client created", component: "Encounter")
        } else {
            debugLog("📦 Batch transcription mode (streaming disabled in config)", component: "Encounter")
        }
        
        // Setup cloud LLM client (use injected or create new, fallback for final SOAP)
        if llmClient == nil {
        llmClient = LLMClient(apiKey: config.openrouterApiKey, model: config.model)
        }
        
        // Setup Groq client for fast final SOAP generation
        if configManager.useGroqForFinalSoap {
            let groqModel = configManager.groqModel
            debugLog("🚀 Groq enabled for final SOAP: model=\(groqModel)", component: "Encounter")
            groqClient = GroqClient(apiKey: configManager.groqApiKey, model: groqModel)
        } else {
            debugLog("☁️ Using OpenRouter for final SOAP", component: "Encounter")
        }
        
        // Setup Ollama client if enabled
        debugLog("🔧 Checking Ollama config: enabled=\(configManager.isOllamaEnabled)", component: "Encounter")
        if configManager.isOllamaEnabled {
            let ollamaBaseUrl = configManager.ollamaBaseUrl
            let ollamaModel = configManager.ollamaModel
            debugLog("🔧 Creating Ollama client: \(ollamaBaseUrl), model: \(ollamaModel)", component: "Encounter")
            ollamaClient = OllamaClient(baseURL: ollamaBaseUrl, model: ollamaModel)
            
            // Check if Ollama is available
            Task {
                debugLog("🔍 Checking Ollama availability...", component: "Encounter")
                let available = await ollamaClient?.isAvailable() ?? false
                await MainActor.run {
                    self.ollamaAvailable = available
                    if available {
                        debugLog("✅ Ollama available (\(ollamaModel))", component: "Encounter")
                        // Pass Ollama client to session detector for LLM-based detection
                        debugLog("🔧 useOllamaForSessionDetection=\(self.configManager.useOllamaForSessionDetection)", component: "Encounter")
                        if self.configManager.useOllamaForSessionDetection {
                            debugLog("🔗 Passing Ollama client to SessionDetector...", component: "Encounter")
                            self.sessionDetector.setOllamaClient(self.ollamaClient)
                        }
                    } else {
                        debugLog("⚠️ Ollama not available, using cloud LLM", component: "Encounter")
                    }
                }
            }
        } else {
            debugLog("⚠️ Ollama not enabled in config", component: "Encounter")
        }
        
        // Setup LLM Orchestrator for intelligent LLM selection
        // If clients were injected (for testing), pass them to orchestrator
        if llmClient != nil || ollamaClient != nil || groqClient != nil {
            llmOrchestrator = LLMOrchestrator(
                configManager: configManager,
                openRouterClient: llmClient,
                ollamaClient: ollamaClient,
                groqClient: groqClient
            )
            debugLog("🎯 LLMOrchestrator initialized with injected clients", component: "Encounter")
        } else {
            llmOrchestrator = LLMOrchestrator(configManager: configManager)
            debugLog("🎯 LLMOrchestrator initialized", component: "Encounter")
        }
        
        // Set orchestrator on SOAP generator
        soapGenerator.setOrchestrator(llmOrchestrator)
    }
    
    // MARK: - Monitoring Mode (Auto-Detection)
    
    // Use global debugLog() function from DebugLogger.swift
    
    func startMonitoring() {
        debugLog("startMonitoring called", component: "Encounter")
        debugLog("isAutoDetectionEnabled: \(configManager.isAutoDetectionEnabled)", component: "Encounter")
        debugLog("audioManager.mode: \(audioManager.mode)", component: "Encounter")
        
        guard configManager.isAutoDetectionEnabled else {
            debugLog("Auto-detection not enabled - returning", component: "Encounter")
            return
        }
        
        do {
            // Only start audio monitoring if not already monitoring
            if audioManager.mode != .monitoring {
                debugLog("Starting audioManager monitoring...", component: "Encounter")
            try audioManager.startMonitoring()
                debugLog("audioManager started OK", component: "Encounter")
            } else {
                debugLog("audioManager already in monitoring mode - skipping", component: "Encounter")
            }
            
            // Always restart session detector to reset internal state
            debugLog("Starting sessionDetector monitoring...", component: "Encounter")
            sessionDetector.startMonitoring()
            debugLog("sessionDetector started OK", component: "Encounter")
            
            debugLog("Ollama client set: \(ollamaClient != nil)", component: "Encounter")
        } catch {
            debugLog("❌ ERROR starting monitoring: \(error)", component: "Encounter")
        }
    }
    
    func stopMonitoring() {
        audioManager.stopMonitoring()
        sessionDetector.stopMonitoring()
        debugLog("Stopped monitoring mode", component: "Encounter")
    }
    
    // MARK: - Encounter Lifecycle
    
    func startEncounter() {
        let encounterId = UUID()
        state = EncounterState(id: encounterId)
        psstPrediction = PsstPrediction()
        soapGenerator.reset()  // Reset SOAP generator state
        interimTranscript = ""
        interimSpeaker = ""
        lastTranscriptIndex = 0
        pendingChunks = []
        transcriptionError = nil
        encounterAttachments = []  // Reset attachments for new encounter
        llmError = nil
        streamingWasUsedInSession = false  // Reset for new session
        isEncounterEnded = false  // Reset encounter ended flag
        
        do {
            // Connect streaming client if using streaming mode
            if useStreaming {
                debugLog("🔌 Connecting streaming client...", component: "Encounter")
                try streamingClient?.connect()
                debugLog("✅ Streaming client connect() called", component: "Encounter")
            } else {
                debugLog("⏭️ Skipping streaming (useStreaming=\(useStreaming))", component: "Encounter")
            }
            
            // Use transition if already monitoring, otherwise start fresh
            if audioManager.mode == .monitoring {
                try audioManager.transitionToRecording(encounterId: encounterId)
            } else {
                try audioManager.startRecording(encounterId: encounterId)
            }
            sessionDetector.encounterStartedManually()
            startUpdateTasks()
            debugLog("🎙️ Encounter started, audio recording active", component: "Encounter")
        } catch let error as AudioError {
            debugLog("❌ Failed to start recording: \(error)", component: "Encounter")
            errorHandler.report(audio: error)
        } catch let error as StreamingSTTError {
            debugLog("❌ Failed to connect streaming: \(error)", component: "Encounter")
            errorHandler.report(streaming: error)
        } catch {
            debugLog("❌ Failed to start recording: \(error)", component: "Encounter")
            errorHandler.report(encounter: .audioSetupFailed(error.localizedDescription))
        }
    }
    
    /// Flag to prevent new transcript entries after encounter ends
    private var isEncounterEnded: Bool = false
    
    func endEncounter() async {
        // Mark encounter as ended to prevent new transcript entries
        isEncounterEnded = true
        
        let transcriptCount = state?.transcript.count ?? 0
        debugLog("🛑 Ending encounter - transcript has \(transcriptCount) entries", component: "Encounter")
        
        // Stop all tasks first
        stopUpdateTasks()
        
        // Cancel any pending transcription task
        transcriptionTask?.cancel()
        transcriptionTask = nil
        
        // Disconnect streaming client
        if useStreaming {
            debugLog("🔌 Disconnecting streaming client...", component: "Encounter")
            streamingClient?.disconnect()
        }
        
        // Clear interim state
        interimTranscript = ""
        interimSpeaker = ""
        
        // IMPORTANT: Stop audio FIRST to prevent race conditions with session detector
        // We'll restart monitoring AFTER SOAP generation completes
        audioManager.stopRecording()
        
        // Pause session detection while we generate SOAP
        sessionDetector.stopMonitoring()
        debugLog("⏸️ Session detection paused for SOAP generation", component: "Encounter")
        
        state?.endedAt = Date()
        
        // Save the state for regeneration (in case provisional recording starts and overwrites state)
        savedStateForRegeneration = state
        
        // Clear any pending chunks - we don't want to process them after encounter ends
        // This prevents the transcript from growing during SOAP generation
        pendingChunks = []
        debugLog("📦 Cleared pending chunks to prevent transcript growth", component: "Encounter")
        
        let finalTranscriptCount = state?.transcript.count ?? 0
        debugLog("📝 About to generate FINAL SOAP - transcript has \(finalTranscriptCount) entries", component: "Encounter")
        
        // Generate final SOAP note
        await generateFinalSOAP()
        
        debugLog("✅ SOAP generation complete", component: "Encounter")
        
        // NOW re-enable session detection after SOAP is done
        sessionDetector.encounterEndedManually()
        
        // Reset the ended flag for next encounter
        isEncounterEnded = false
        
        // Restart monitoring if auto-detection is enabled
        if configManager.isAutoDetectionEnabled {
            debugLog("▶️ Restarting session detection...", component: "Encounter")
            do {
                try audioManager.startMonitoring()
                sessionDetector.startMonitoring()
            } catch {
                debugLog("❌ Failed to restart monitoring: \(error)", component: "Encounter")
            }
        }
    }
    
    func pauseEncounter() {
        audioManager.pauseRecording()
        stopUpdateTasks()
    }
    
    func resumeEncounter() {
        audioManager.resumeRecording()
        startUpdateTasks()
    }
    
    // MARK: - Clinical Notes (Manual Input)
    
    func addClinicalNote(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let note = ClinicalNote(text: text.trimmingCharacters(in: .whitespacesAndNewlines))
        state?.clinicalNotes.append(note)
    }
    
    // MARK: - Encounter Attachments (from Chat)
    
    /// Add an attachment from the Chat section to be included in SOAP generation
    func addEncounterAttachment(_ attachment: EncounterAttachment) {
        encounterAttachments.append(attachment)
        debugLog("📎 Added encounter attachment: \(attachment.name) (\(attachment.type.rawValue))", component: "Encounter")
    }
    
    /// Check if any attachments require multimodal processing
    var hasMultimodalAttachments: Bool {
        encounterAttachments.contains { $0.isMultimodal }
    }
    
    // MARK: - Update Tasks
    
    private func startUpdateTasks() {
        guard let config = configManager.config else { return }
        
        let helperInterval = TimeInterval(config.timing.helperUpdateIntervalSeconds)
        let soapInterval = TimeInterval(config.timing.soapUpdateIntervalSeconds)
        
        // NOTE: Helper/Assistant updates disabled - UI section hidden
        // To re-enable, uncomment the following:
        // stateUpdateTask = Task {
        //     while !Task.isCancelled {
        //         try? await Task.sleep(for: .seconds(helperInterval))
        //         guard !Task.isCancelled else { break }
        //         await updateStateAndHelpers()
        //     }
        // }
        
        // Psst... prediction task (uses configured model for fast predictions)
        // Updates every 15 seconds with predictive insights
        psstUpdateTask = Task {
            // Initial delay to gather some transcript
            try? await Task.sleep(for: .seconds(10))
            while !Task.isCancelled {
                guard !Task.isCancelled else { break }
                await updatePsstPrediction()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        
    }
    
    private func stopUpdateTasks() {
        transcriptionTask?.cancel()
        stateUpdateTask?.cancel()
        psstUpdateTask?.cancel()
        
        transcriptionTask = nil
        stateUpdateTask = nil
        psstUpdateTask = nil
    }
    
    // MARK: - Transcription
    
    private func transcribeChunk(_ chunkURL: URL) async {
        // Don't process if encounter has ended
        guard !isEncounterEnded else {
            debugLog("⏭️ Skipping chunk transcription - encounter ended", component: "REST")
            return
        }
        
        guard let sttClient = sttClient else { 
            debugLog("❌ No STT client available", component: "REST")
            return 
        }
        
        do {
            let audioData = try Data(contentsOf: chunkURL)
            debugLog("🎤 Transcribing chunk: \(chunkURL.lastPathComponent) (\(audioData.count) bytes)", component: "REST")
            
            await MainActor.run {
                isTranscribing = true
                transcriptionError = nil
            }
            
            let segments = try await sttClient.transcribe(audioData: audioData)
            
            await MainActor.run {
                // Double-check encounter hasn't ended during transcription
                guard !self.isEncounterEnded else {
                    debugLog("⏭️ Discarding transcription results - encounter ended during processing", component: "REST")
                    self.isTranscribing = false
                    return
                }
                
                debugLog("📝 REST received \(segments.count) segments", component: "REST")
                for segment in segments {
                    // Skip duplicates
                    if self.isDuplicateTranscript(segment.text) {
                        debugLog("🔄 Skipped duplicate: \(segment.text.prefix(40))...", component: "REST")
                        continue
                    }
                    
                    let entry = TranscriptEntry(
                        timestamp: segment.timestamp,
                        speaker: segment.speaker,
                        text: segment.text
                    )
                    self.state?.transcript.append(entry)
                    debugLog("📝 Added: [\(segment.speaker)] \(segment.text.prefix(40))... (total: \(self.state?.transcript.count ?? 0))", component: "REST")
                    
                    // Feed transcript to session detector
                    self.sessionDetector.processTranscript(segment.text)
                }
                self.isTranscribing = false
            }
        } catch let error as STTError {
            await MainActor.run {
                self.isTranscribing = false
                self.transcriptionError = error.localizedDescription
                self.errorHandler.report(transcription: error, showAlert: false)
            }
            debugLog("❌ REST transcription error: \(error)", component: "REST")
        } catch {
            await MainActor.run {
                self.isTranscribing = false
                self.transcriptionError = error.localizedDescription
                self.errorHandler.report(encounter: .transcriptionFailed(error.localizedDescription), showAlert: false)
            }
            debugLog("❌ REST transcription error: \(error)", component: "REST")
        }
    }
    
    private func processRemainingChunks() async {
        for chunk in pendingChunks {
            await transcribeChunk(chunk)
        }
        pendingChunks = []
    }
    
    // MARK: - Psst... Prediction Updates
    
    private func updatePsstPrediction() async {
        guard let state = state, !state.transcript.isEmpty else { return }
        guard let orchestrator = llmOrchestrator else { return }
        
        // Use full transcript for context
        let transcriptText = state.transcript.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        
        // Skip if transcript is too short
        guard transcriptText.count > 100 else { return }
        
        await MainActor.run {
            self.isPsstUpdating = true
        }
        
        do {
            debugLog("🔮 Generating Psst... prediction", component: "Psst")
            
            let userContent = """
            TRANSCRIPT SO FAR:
            \(transcriptText)
            """
            
            // Use orchestrator for model selection
            let response = try await orchestrator.generatePsstPrediction(
                systemPrompt: LLMPrompts.psstPrediction,
                content: userContent
            )
            
            // Store plain text response
            let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedResponse.isEmpty {
                await MainActor.run {
                    self.psstPrediction = PsstPrediction(hint: trimmedResponse)
                    self.isPsstUpdating = false
                }
                debugLog("🔮 Psst... prediction updated: \(trimmedResponse.prefix(50))...", component: "Psst")
            } else {
                await MainActor.run {
                    self.isPsstUpdating = false
                }
            }
        } catch {
            await MainActor.run {
                self.isPsstUpdating = false
            }
            debugLog("❌ Psst... prediction error: \(error)", component: "Psst")
        }
    }
    
    private func generateFinalSOAP() async {
        // Use saved state for regeneration if current state is empty
        let effectiveState: EncounterState?
        if let saved = savedStateForRegeneration, !saved.transcript.isEmpty {
            if state == nil || state!.transcript.isEmpty || state!.transcript.count < saved.transcript.count {
                effectiveState = saved
            } else {
                effectiveState = state
            }
        } else {
            effectiveState = state
        }
        
        guard let stateToUse = effectiveState else {
            debugLog("Cannot generate SOAP - no state available", component: "SOAP")
            return
        }
        
        // Use SOAPGenerator for final SOAP generation
        await soapGenerator.generateFinalSOAP(from: stateToUse, attachments: encounterAttachments)
        
        // Sync error state
        if let error = soapGenerator.error {
            llmError = error
        }
    }
    
    /// Public method to regenerate SOAP with a specific detail level (legacy)
    /// Used by the EndEncounterSheet for "More Detail" / "Less Detail" buttons
    func regenerateSOAP(detailLevel: SOAPDetailLevel) {
        // Convert legacy detail level to numeric
        let numericLevel: Int
        switch detailLevel {
        case .less: numericLevel = 3
        case .normal: numericLevel = 5
        case .more: numericLevel = 7
        }
        regenerateSOAP(detailLevel: numericLevel, format: currentSOAPFormat)
    }
    
    /// Public method to regenerate SOAP with numeric detail level (1-10), format, and optional custom instructions
    func regenerateSOAP(detailLevel: Int, format: SOAPFormat, customInstructions: String = "") {
        // Use saved state for regeneration if current state is empty
        let effectiveState: EncounterState?
        if let saved = savedStateForRegeneration, !saved.transcript.isEmpty {
            if state == nil || state!.transcript.isEmpty || state!.transcript.count < saved.transcript.count {
                effectiveState = saved
            } else {
                effectiveState = state
            }
        } else {
            effectiveState = state
        }
        
        soapGenerator.regenerate(
            from: effectiveState,
            detailLevel: detailLevel,
            format: format,
            customInstructions: customInstructions,
            attachments: encounterAttachments
        )
    }
    
    /// Published property to track if SOAP is being regenerated - proxied from SOAPGenerator
    var isRegeneratingSOAP: Bool {
        soapGenerator.isGenerating
    }
    
    /// Current detail level (1-10, default 5) - proxied from SOAPGenerator
    var currentDetailLevel: Int {
        get { soapGenerator.currentDetailLevel }
        set { soapGenerator.currentDetailLevel = newValue }
    }
    
    /// Current SOAP format - proxied from SOAPGenerator
    var currentSOAPFormat: SOAPFormat {
        get { soapGenerator.currentSOAPFormat }
        set { soapGenerator.currentSOAPFormat = newValue }
    }
    
    // MARK: - Helpers
    
    /// Check if a transcript entry is a duplicate of recent entries
    /// Returns true if the text is very similar to any of the last N entries
    private func isDuplicateTranscript(_ text: String, checkLast n: Int = 10) -> Bool {
        guard let transcript = state?.transcript else { return false }
        
        let recentEntries = transcript.suffix(n)
        let normalizedNew = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        for entry in recentEntries {
            let normalizedExisting = entry.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check for exact match
            if normalizedNew == normalizedExisting {
                return true
            }
            
            // Check if one contains the other (for partial duplicates)
            if normalizedNew.count > 10 && normalizedExisting.count > 10 {
                // Check if >80% of the shorter string is contained in the longer
                let shorter = normalizedNew.count < normalizedExisting.count ? normalizedNew : normalizedExisting
                let longer = normalizedNew.count >= normalizedExisting.count ? normalizedNew : normalizedExisting
                
                if longer.contains(shorter) {
                    return true
                }
                
                // Check similarity using common prefix
                let commonPrefix = normalizedNew.commonPrefix(with: normalizedExisting)
                let similarity = Double(commonPrefix.count) / Double(min(normalizedNew.count, normalizedExisting.count))
                if similarity > 0.8 {
                    return true
                }
            }
        }
        
        return false
    }
    
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
            debugLog("⚠️ JSON parsing failed: \(error)", component: "Encounter")
            return nil
        }
    }
}

// MARK: - AudioManagerDelegate

extension EncounterController: AudioManagerDelegate {
    func audioManager(_ manager: AudioManager, didSaveChunk chunkURL: URL, chunkNumber: Int) {
        // Only use chunk-based transcription if not streaming
        guard !useStreaming || !isStreamingConnected else {
            debugLog("📦 Chunk \(chunkNumber) saved (streaming active, skipping REST)", component: "Audio")
            pendingChunks.append(chunkURL)  // Keep for backup/recovery
            return
        }
        
        debugLog("⚠️ Chunk \(chunkNumber) - using REST (useStreaming=\(useStreaming), connected=\(isStreamingConnected))", component: "Audio")
        pendingChunks.append(chunkURL)
        
        // Transcribe immediately using REST API
        Task {
            await transcribeChunk(chunkURL)
            pendingChunks.removeAll { $0 == chunkURL }
        }
    }
    
    func audioManager(_ manager: AudioManager, didCaptureAudioSamples samples: [Int16]) {
        // Forward audio samples to streaming client
        // Always send when streaming is enabled - the client handles buffering internally
        if useStreaming {
            streamingClient?.sendAudio(samples)
            
            // Log occasionally to verify streaming is working
            audioSampleLogCount += 1
            if audioSampleLogCount % 100 == 1 {
                debugLog("🎙️ Streaming audio: \(samples.count) samples, connected: \(isStreamingConnected), client exists: \(streamingClient != nil)", component: "Audio")
            }
        }
    }
    
    func audioManager(_ manager: AudioManager, didEncounterError error: Error) {
        debugLog("❌ Audio error: \(error)", component: "Audio")
    }
    
    func audioManager(_ manager: AudioManager, didUpdateAudioLevel level: Float) {
        // Log every 100th call to avoid flooding
        audioLevelLogCount += 1
        if audioLevelLogCount % 100 == 1 {
            debugLog("Audio level: \(String(format: "%.4f", level)), mode: \(audioManager.mode), detector: \(sessionDetector.detectionStatus)", component: "Audio")
        }
        
        // Pass audio level to session detector for VAD
        sessionDetector.processSpeechActivity(level: level)
    }
}

// MARK: - SessionDetectorDelegate

extension EncounterController: SessionDetectorDelegate {
    func sessionDetectorDidDetectEncounterStart(_ detector: SessionDetector) {
        debugLog("🎬 Auto-detected encounter start confirmed by LLM!", component: "Encounter")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // If we were in provisional recording, transition to full encounter
            if self.isProvisionalRecording {
                self.confirmProvisionalRecording()
            } else {
                // Start fresh encounter
                self.startEncounterFromAutoDetection()
            }
            
            // Notify the delegate to update UI
            self.delegate?.encounterControllerDidAutoStart(self)
        }
    }
    
    func sessionDetectorDidDetectEncounterEnd(_ detector: SessionDetector) {
        debugLog("🎬 Auto-detected encounter end!", component: "Encounter")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.encounterControllerDidAutoEnd(self)
        }
    }
    
    func sessionDetectorDidStartBuffering(_ detector: SessionDetector) {
        debugLog("📦 Buffering started - starting provisional recording", component: "Encounter")
        DispatchQueue.main.async { [weak self] in
            self?.startProvisionalRecording()
        }
    }
    
    func sessionDetectorDidCancelBuffering(_ detector: SessionDetector) {
        debugLog("📦 Buffering cancelled - stopping provisional recording", component: "Encounter")
        DispatchQueue.main.async { [weak self] in
            self?.cancelProvisionalRecording()
        }
    }
}

// MARK: - Auto-Detection Encounter Start

extension EncounterController {
    /// Starts provisional recording for LLM analysis (speech detected, waiting for LLM confirmation)
    func startProvisionalRecording() {
        guard !isProvisionalRecording else { return }
        
        let encounterId = UUID()
        provisionalEncounterId = encounterId
        isProvisionalRecording = true
        
        // Initialize state for transcription
        state = EncounterState(id: encounterId)
        psstPrediction = PsstPrediction()
        soapNote = ""
        interimTranscript = ""
        interimSpeaker = ""
        lastTranscriptIndex = 0
        pendingChunks = []
        transcriptionError = nil
        llmError = nil
        streamingWasUsedInSession = false  // Reset for new session
        
        do {
            // Connect streaming client if using streaming mode
            debugLog("🔧 useStreaming=\(useStreaming), streamingClient exists: \(streamingClient != nil)", component: "Encounter")
            if useStreaming {
                if let client = streamingClient {
                    debugLog("🔌 Connecting streaming client for provisional recording...", component: "Encounter")
                    try client.connect()
                    debugLog("✅ Streaming client connect() called", component: "Encounter")
                } else {
                    debugLog("⚠️ No streaming client available!", component: "Encounter")
                }
            }
            
            // Transition from monitoring to recording mode
            // Transcription happens automatically via AudioManager delegate callbacks
            try audioManager.transitionToRecording(encounterId: encounterId)
            debugLog("✅ Provisional recording started for LLM analysis", component: "Encounter")
        } catch {
            debugLog("❌ Failed to start provisional recording: \(error)", component: "Encounter")
            isProvisionalRecording = false
            provisionalEncounterId = nil
        }
    }
    
    /// Confirms provisional recording - officially starts the encounter
    func confirmProvisionalRecording() {
        guard isProvisionalRecording else { return }
        
        isProvisionalRecording = false
        sessionDetector.encounterStartedManually()
        startUpdateTasks()  // Start helper/SOAP updates
        debugLog("✅ Provisional recording confirmed - encounter officially started", component: "Encounter")
    }
    
    /// Cancels provisional recording - returns to monitoring
    func cancelProvisionalRecording() {
        guard isProvisionalRecording else { return }
        
        isProvisionalRecording = false
        provisionalEncounterId = nil
        
        // Disconnect streaming client
        if useStreaming {
            streamingClient?.disconnect()
        }
        
        // Clean up state
        state = nil
        pendingChunks = []
        interimTranscript = ""
        interimSpeaker = ""
        
        // Transition back to monitoring
        do {
            try audioManager.transitionToMonitoring()
            debugLog("✅ Provisional recording cancelled - back to monitoring", component: "Encounter")
        } catch {
            debugLog("❌ Failed to transition to monitoring: \(error)", component: "Encounter")
        }
    }
    
    /// Starts an encounter triggered by auto-detection (when not using provisional recording)
    func startEncounterFromAutoDetection() {
        let encounterId = UUID()
        state = EncounterState(id: encounterId)
        psstPrediction = PsstPrediction()
        soapNote = ""
        interimTranscript = ""
        interimSpeaker = ""
        lastTranscriptIndex = 0
        pendingChunks = []
        transcriptionError = nil
        encounterAttachments = []  // Reset attachments for new encounter
        llmError = nil
        streamingWasUsedInSession = false  // Reset for new session
        
        do {
            // Connect streaming client if using streaming mode
            if useStreaming {
                try streamingClient?.connect()
            }
            
            // Transition from monitoring to recording mode
            try audioManager.transitionToRecording(encounterId: encounterId)
            sessionDetector.encounterStartedManually()
            startUpdateTasks()
            debugLog("✅ Encounter started from auto-detection", component: "Encounter")
        } catch {
            debugLog("❌ Failed to start recording: \(error)", component: "Encounter")
        }
    }
}

// MARK: - StreamingSTTClientDelegate

extension EncounterController: StreamingSTTClientDelegate {
    func streamingClient(_ client: StreamingSTTClient, didReceiveInterim text: String, speaker: String) {
        interimTranscript = text
        interimSpeaker = speaker
        isTranscribing = true
        
        // Feed interim transcript to session detector for faster detection
        sessionDetector.processTranscript(text)
    }
    
    func streamingClient(_ client: StreamingSTTClient, didReceiveFinal segment: TranscriptSegment) {
        // Clear interim state
        interimTranscript = ""
        interimSpeaker = ""
        isTranscribing = false
        
        // Don't add new entries if encounter has ended
        guard !isEncounterEnded else {
            debugLog("⏭️ Discarding streaming result - encounter ended", component: "Streaming")
            return
        }
        
        // Skip duplicates
        if isDuplicateTranscript(segment.text) {
            debugLog("🔄 Skipped duplicate streaming: \(segment.text.prefix(40))...", component: "Streaming")
            return
        }
        
        // Mark that streaming was successfully used in this session
        streamingWasUsedInSession = true
        
        // Add to permanent transcript
        let entry = TranscriptEntry(
            timestamp: segment.timestamp,
            speaker: segment.speaker,
            text: segment.text
        )
        state?.transcript.append(entry)
        
        let transcriptCount = state?.transcript.count ?? 0
        debugLog("📝 FINAL transcript received: [\(segment.speaker)] \(segment.text.prefix(50))... (total: \(transcriptCount))", component: "Streaming")
        
        // Feed final transcript to session detector
        sessionDetector.processTranscript(segment.text)
    }
    
    func streamingClient(_ client: StreamingSTTClient, didChangeConnectionState connected: Bool) {
        isStreamingConnected = connected
        
        if connected {
            debugLog("✅ Streaming connected", component: "Encounter")
            transcriptionError = nil
        } else {
            debugLog("⚠️ Streaming disconnected", component: "Encounter")
            // If we disconnect during an active encounter, fall back to chunk-based transcription
            if audioManager.mode == .recording && !pendingChunks.isEmpty {
                debugLog("📦 Falling back to chunk transcription...", component: "Encounter")
                Task {
                    await processRemainingChunks()
                }
            }
        }
    }
    
    func streamingClient(_ client: StreamingSTTClient, didEncounterError error: Error) {
        debugLog("❌ Streaming error: \(error.localizedDescription)", component: "Encounter")
        transcriptionError = error.localizedDescription
        
        if let streamError = error as? StreamingSTTError {
            errorHandler.report(streaming: streamError, showAlert: false)
        } else {
            errorHandler.report(encounter: .transcriptionFailed(error.localizedDescription), showAlert: false)
        }
    }
}

// MARK: - Delegate Protocol

@MainActor
protocol EncounterControllerDelegate: AnyObject {
    func encounterControllerDidAutoStart(_ controller: EncounterController)
    func encounterControllerDidAutoEnd(_ controller: EncounterController)
}
