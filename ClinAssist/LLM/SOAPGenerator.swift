import Foundation

/// Handles SOAP note generation with configurable detail levels and formats
/// Extracted from EncounterController to improve separation of concerns
@MainActor
class SOAPGenerator: ObservableObject {
    
    // MARK: - Published State
    
    @Published var soapNote: String = ""
    @Published var isGenerating: Bool = false
    @Published var error: String?
    
    /// Current detail level (1-10, default 5) - persisted to UserDefaults
    @Published var currentDetailLevel: Int {
        didSet {
            UserDefaults.standard.set(currentDetailLevel, forKey: Self.detailLevelKey)
        }
    }
    
    /// Current SOAP format - persisted to UserDefaults
    @Published var currentSOAPFormat: SOAPFormat {
        didSet {
            UserDefaults.standard.set(currentSOAPFormat.rawValue, forKey: Self.formatKey)
        }
    }
    
    // MARK: - Private Properties
    
    private let configManager: ConfigManager
    private var llmOrchestrator: LLMOrchestrator?
    private var regenerationTask: Task<Void, Never>?
    private let errorHandler = ErrorHandler.shared
    
    // MARK: - Constants
    
    private static let detailLevelKey = "soap_detail_level"
    private static let formatKey = "soap_format"
    
    /// Threshold for "large" transcripts that need extended context window
    private let largeTranscriptThreshold = 500
    
    // MARK: - Initialization
    
    init(configManager: ConfigManager) {
        self.configManager = configManager
        self.currentDetailLevel = Self.loadPersistedDetailLevel()
        self.currentSOAPFormat = Self.loadPersistedFormat()
    }
    
    /// Set the LLM orchestrator (called after it's initialized in EncounterController)
    func setOrchestrator(_ orchestrator: LLMOrchestrator?) {
        self.llmOrchestrator = orchestrator
    }
    
    // MARK: - Persistence
    
    private static func loadPersistedDetailLevel() -> Int {
        let saved = UserDefaults.standard.integer(forKey: detailLevelKey)
        return saved > 0 ? max(1, min(10, saved)) : 5  // Default to 5 if not set
    }
    
    private static func loadPersistedFormat() -> SOAPFormat {
        if let savedRaw = UserDefaults.standard.string(forKey: formatKey),
           let format = SOAPFormat(rawValue: savedRaw) {
            return format
        }
        return .problemBased  // Default
    }
    
    // MARK: - Public Methods
    
    /// Generate the final SOAP note for an encounter
    func generateFinalSOAP(
        from state: EncounterState,
        attachments: [EncounterAttachment] = []
    ) async {
        await generateSOAPNote(
            from: state,
            isFinal: true,
            detailLevel: currentDetailLevel,
            format: currentSOAPFormat,
            attachments: attachments
        )
    }
    
    /// Regenerate SOAP with specific settings
    func regenerate(
        from state: EncounterState?,
        detailLevel: Int,
        format: SOAPFormat,
        customInstructions: String = "",
        attachments: [EncounterAttachment] = []
    ) {
        guard !isGenerating else {
            debugLog("SOAP regeneration already in progress, ignoring request", component: "SOAPGenerator")
            return
        }
        
        guard let state = state else {
            debugLog("Cannot regenerate SOAP - no state available", component: "SOAPGenerator")
            return
        }
        
        // Cancel any existing regeneration task
        regenerationTask?.cancel()
        
        currentDetailLevel = detailLevel
        currentSOAPFormat = format
        
        regenerationTask = Task {
            await generateSOAPNote(
                from: state,
                isFinal: true,
                detailLevel: detailLevel,
                format: format,
                customInstructions: customInstructions,
                attachments: attachments
            )
        }
    }
    
    /// Cancel any in-progress generation
    func cancelGeneration() {
        regenerationTask?.cancel()
        regenerationTask = nil
        isGenerating = false
    }
    
    /// Reset state for a new encounter
    func reset() {
        soapNote = ""
        error = nil
        isGenerating = false
        regenerationTask?.cancel()
        regenerationTask = nil
    }
    
    // MARK: - Private Methods
    
    private func generateSOAPNote(
        from state: EncounterState,
        isFinal: Bool,
        detailLevel: Int,
        format: SOAPFormat,
        customInstructions: String = "",
        attachments: [EncounterAttachment] = []
    ) async {
        guard !state.transcript.isEmpty else {
            debugLog("SOAP generation skipped - transcript is EMPTY", component: "SOAPGenerator")
            return
        }
        
        let transcriptCount = state.transcript.count
        let clinicalNotesCount = state.clinicalNotes.count
        let detailInfo = " [level \(detailLevel)/10, \(format.rawValue)]"
        let logPrefix = isFinal ? "Generating FINAL SOAP\(detailInfo)" : "Generating live SOAP"
        debugLog("\(logPrefix) - \(transcriptCount) transcript entries, \(clinicalNotesCount) clinical notes", component: "SOAPGenerator")
        
        // Set generating flag for UI feedback
        isGenerating = true
        error = nil
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            
            let stateJSON: Data
            do {
                stateJSON = try encoder.encode(state)
            } catch {
                debugLog("Failed to encode state to JSON: \(error)", component: "SOAPGenerator")
                self.error = "Failed to encode encounter data: \(error.localizedDescription)"
                self.isGenerating = false
                return
            }
            
            guard let stateString = String(data: stateJSON, encoding: .utf8), !stateString.isEmpty else {
                debugLog("State JSON is empty or failed UTF-8 conversion", component: "SOAPGenerator")
                self.error = "Encounter data is empty"
                self.isGenerating = false
                return
            }
            
            debugLog("State JSON size: \(stateJSON.count) bytes", component: "SOAPGenerator")
            
            // Use LLMOrchestrator for intelligent provider selection
            guard let orchestrator = llmOrchestrator else {
                debugLog("No LLM orchestrator available!", component: "SOAPGenerator")
                self.error = "LLM service not configured"
                self.isGenerating = false
                return
            }
            
            // Get the appropriate prompt based on settings
            let hasAttachments = !attachments.isEmpty
            let prompt = LLMPrompts.soapRendererWithOptions(
                detailLevel: detailLevel,
                format: format,
                customInstructions: customInstructions,
                hasAttachments: hasAttachments
            )
            
            debugLog("Calling generateFinalSOAP with \(stateString.count) chars, \(attachments.count) attachments", component: "SOAPGenerator")
            let response = try await orchestrator.generateFinalSOAP(
                systemPrompt: prompt,
                content: stateString,
                transcriptEntryCount: transcriptCount,
                attachments: attachments
            )
            debugLog("Got response from LLM (\(response.count) chars)", component: "SOAPGenerator")
            
            // Validate response
            if response.isEmpty {
                debugLog("LLM returned EMPTY response - treating as error", component: "SOAPGenerator")
                self.error = "LLM returned an empty response. Please try regenerating the SOAP note."
                self.isGenerating = false
                return
            }
            
            if response.count < 50 {
                debugLog("LLM returned very short response (\(response.count) chars): \(response)", component: "SOAPGenerator")
            }
            
            self.soapNote = response
            self.error = nil
            self.isGenerating = false
            debugLog("SOAP note set (\(response.count) chars)\(detailInfo)", component: "SOAPGenerator")
            
        } catch let error as LLMProviderError {
            let errorMessage = error.localizedDescription
            self.error = errorMessage
            self.isGenerating = false
            self.errorHandler.report(llm: error, showAlert: isFinal)
            debugLog("SOAP generation error: \(error)", component: "SOAPGenerator")
        } catch {
            let errorMessage = error.localizedDescription
            self.error = errorMessage
            self.isGenerating = false
            self.errorHandler.report(encounter: .soapGenerationFailed(errorMessage), showAlert: isFinal)
            debugLog("SOAP generation error: \(error)", component: "SOAPGenerator")
        }
    }
}

// MARK: - SOAP Configuration Extension

extension SOAPGenerator {
    
    /// Available detail level presets
    enum DetailPreset: Int, CaseIterable {
        case ultraBrief = 1
        case minimal = 2
        case brief = 3
        case short = 4
        case standard = 5
        case expanded = 6
        case detailed = 7
        case thorough = 8
        case comprehensive = 9
        case maximum = 10
        
        var displayName: String {
            switch self {
            case .ultraBrief: return "Ultra-Brief (1)"
            case .minimal: return "Minimal (2)"
            case .brief: return "Brief (3)"
            case .short: return "Short (4)"
            case .standard: return "Standard (5)"
            case .expanded: return "Expanded (6)"
            case .detailed: return "Detailed (7)"
            case .thorough: return "Thorough (8)"
            case .comprehensive: return "Comprehensive (9)"
            case .maximum: return "Maximum (10)"
            }
        }
    }
}
