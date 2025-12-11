import Foundation
import Combine

/// Protocol for LLM client used by SessionDetector
protocol SessionDetectorLLMClient {
    func quickComplete(prompt: String, modelOverride: String?) async throws -> String
}

// OllamaClient conforms to this protocol
extension OllamaClient: SessionDetectorLLMClient {}

/// Detects the start and end of clinical encounters based on audio activity and transcript patterns
@MainActor
class SessionDetector: ObservableObject {
    
    // MARK: - Private logging helper (uses global DebugLogger)
    
    private func log(_ message: String) {
        debugLog(message, component: "SessionDetector")
    }
    
    // MARK: - Published State
    
    @Published var isMonitoring: Bool = false
    @Published var currentSilenceDuration: TimeInterval = 0
    @Published var detectionStatus: DetectionStatus = .idle
    @Published var lastDetectedPattern: String?
    
    // MARK: - Configuration
    
    struct Config {
        var enabled: Bool = true
        var detectEndOfEncounter: Bool = true  // When false, sessions can only be manually ended
        var silenceThresholdSeconds: TimeInterval = 45
        var minEncounterDurationSeconds: TimeInterval = 60
        var speechActivityThreshold: Float = 0.02  // Audio level threshold
        var bufferDurationSeconds: TimeInterval = 45  // Needs time for: audio record + transcribe + LLM (increased for slow networks)
    }
    
    var config: Config
    
    // MARK: - Detection State
    
    enum DetectionStatus: Equatable {
        case idle                    // Not monitoring
        case monitoring              // Listening for encounter start
        case buffering               // Speech detected, buffering to confirm
        case analyzing               // LLM is analyzing transcript
        case encounterActive         // In an active encounter
        case potentialEnd            // Detected end pattern, waiting for silence confirmation
    }
    
    // MARK: - Private Properties
    
    private var silenceTimer: Timer?
    private var bufferTimer: Timer?
    private var encounterStartTime: Date?
    private var lastSpeechTime: Date?
    private var recentTranscriptBuffer: [String] = []
    private let maxBufferSize = 20  // Keep last 20 transcript segments
    
    // LLM-based detection
    private var llmClient: SessionDetectorLLMClient?
    private var isAnalyzing: Bool = false
    private var lastAnalysisTime: Date?
    private let analysisDebounceSeconds: TimeInterval = 3  // Don't analyze more than every 3 seconds
    
    weak var delegate: SessionDetectorDelegate?
    
    // MARK: - LLM Prompts
    
    private let startDetectionPrompt = """
    You are analyzing a transcript excerpt to determine if a clinical patient encounter is beginning.

    Signs of encounter START:
    - Greeting between physician and patient
    - Patient entering the room
    - Discussion of why patient is visiting
    - Chief complaint being mentioned
    - Any medical discussion beginning

    Analyze the transcript and respond with ONLY one word:
    - "START" if this appears to be the beginning of a clinical encounter
    - "WAIT" if unclear or just casual conversation, keep monitoring

    Transcript:
    """
    
    private let endDetectionPrompt = """
    You are analyzing a transcript excerpt to determine if a clinical patient encounter is ending.

    Signs of encounter END:
    - Goodbye phrases or farewells
    - Discussion of follow-up appointments
    - Patient being dismissed
    - Wrapping up conversation
    - Instructions to see front desk

    Signs to CONTINUE (not ending):
    - New symptoms being discussed
    - Questions about medications
    - Physical examination happening
    - Any ongoing clinical discussion

    Analyze the transcript and respond with ONLY one word:
    - "END" if this appears to be the conclusion of the encounter
    - "CONTINUE" if the clinical discussion is ongoing

    Transcript:
    """
    
    // MARK: - Initialization
    
    init(config: Config = Config()) {
        self.config = config
    }
    
    func setLLMClient(_ client: SessionDetectorLLMClient?) {
        self.llmClient = client
        if client != nil {
            log("✅ LLM-based detection enabled")
        } else {
            log("⚠️ LLM-based detection disabled (no LLM client)")
        }
    }
    
    /// Convenience method for setting OllamaClient
    func setOllamaClient(_ client: OllamaClient?) {
        setLLMClient(client)
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        guard config.enabled else { return }
        
        // Auto-detection requires LLM - disable if not available
        guard llmClient != nil else {
            log("⚠️ Auto-detection disabled - no LLM available")
            return
        }
        
        isMonitoring = true
        detectionStatus = .monitoring
        currentSilenceDuration = 0
        recentTranscriptBuffer = []
        lastDetectedPattern = nil
        
        startSilenceTimer()
        
        log("Started monitoring for encounters (LLM enabled)")
    }
    
    func stopMonitoring() {
        isMonitoring = false
        detectionStatus = .idle
        stopSilenceTimer()
        stopBufferTimer()
        
        log("Stopped monitoring")
    }
    
    func encounterStartedManually() {
        log("encounterStartedManually called - setting to .encounterActive")
        detectionStatus = .encounterActive
        encounterStartTime = Date()
        currentSilenceDuration = 0
        recentTranscriptBuffer = []
    }
    
    func encounterEndedManually() {
        log("encounterEndedManually called - isMonitoring: \(isMonitoring)")
        if isMonitoring {
            detectionStatus = .monitoring
        } else {
            detectionStatus = .idle
        }
        
        // Reset all internal state to allow fresh detection
        encounterStartTime = nil
        recentTranscriptBuffer = []
        isAnalyzing = false
        lastAnalysisTime = nil
        lastSpeechTime = nil
        currentSilenceDuration = 0
        lastDetectedPattern = nil
        
        log("State reset complete - ready for next session")
    }
    
    /// Resets end detection state so it can detect end again
    /// Called when user cancels auto-end confirmation
    func resetEndDetection() {
        if detectionStatus == .potentialEnd {
            detectionStatus = .encounterActive
        }
        lastDetectedPattern = nil
        currentSilenceDuration = 0
        lastSpeechTime = Date() // Reset silence timer
        log("End detection reset - continuing encounter")
    }
    
    // MARK: - Audio Level Analysis (VAD)
    
    func processSpeechActivity(level: Float) {
        guard isMonitoring else { return }
        
        let isSpeaking = level > config.speechActivityThreshold
        
        // Debug logging every 50 calls
        if Int.random(in: 0..<50) == 0 {
            log("🎤 Audio level: \(String(format: "%.4f", level)), threshold: \(config.speechActivityThreshold), speaking: \(isSpeaking), status: \(detectionStatus)")
        }
        
        if isSpeaking {
            lastSpeechTime = Date()
            currentSilenceDuration = 0
            
            // If we're monitoring and speech is detected, start buffering for LLM analysis
            if detectionStatus == .monitoring {
                log("🎙️ Speech detected! Level: \(level)")
                log("📦 Starting buffering for LLM analysis...")
                startBuffering()
            }
        }
    }
    
    // MARK: - Transcript Analysis
    
    func processTranscript(_ text: String) {
        guard isMonitoring || detectionStatus == .encounterActive || detectionStatus == .buffering || detectionStatus == .analyzing else { return }
        
        // Add to buffer
        recentTranscriptBuffer.append(text)
        if recentTranscriptBuffer.count > maxBufferSize {
            recentTranscriptBuffer.removeFirst()
        }
        
        let combinedTranscript = recentTranscriptBuffer.joined(separator: "\n")
        
        switch detectionStatus {
        case .buffering, .analyzing:
            analyzeForEncounterStart(transcript: combinedTranscript)
            
        case .encounterActive:
            // Only analyze for end if end detection is enabled
            if config.detectEndOfEncounter {
                analyzeForEncounterEnd(transcript: combinedTranscript)
            }
            
        case .potentialEnd:
            // If we get new clinical content, cancel the end
            if detectClinicalContent(in: text) {
                cancelPotentialEnd()
            }
            
        default:
            break
        }
    }
    
    // MARK: - LLM-Based Detection
    
    private func analyzeForEncounterStart(transcript: String) {
        guard !isAnalyzing else { 
            log("🔄 Already analyzing, skipping")
            return 
        }
        guard shouldAnalyze() else { 
            log("⏳ Too soon to analyze again")
            return 
        }
        
        isAnalyzing = true
        detectionStatus = .analyzing
        lastAnalysisTime = Date()
        
        log("🤖 Sending transcript to LLM for start analysis...")
        log("📝 Transcript preview: \(String(transcript.prefix(200)))")
        
        Task {
            do {
                let prompt = startDetectionPrompt + "\n\n\"\"\"\n\(transcript)\n\"\"\""
                log("📤 Calling LLM quickComplete...")
                let response = try await llmClient?.quickComplete(prompt: prompt, modelOverride: nil) ?? "WAIT"
                
                let decision = response.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                log("🤖 LLM raw response: \(response.prefix(200))")
                log("🤖 LLM decision: \(decision)")
                
                await MainActor.run {
                    self.isAnalyzing = false
                    
                    if decision.contains("START") {
                        self.log("✅ LLM confirmed encounter start!")
                        self.lastDetectedPattern = "LLM detected encounter start"
                        self.confirmEncounterStart()
                    } else {
                        self.log("⏳ LLM says not an encounter yet, continuing to buffer")
                        // Keep buffering/monitoring
                        if self.detectionStatus == .analyzing {
                            self.detectionStatus = .buffering
                        }
                    }
                }
            } catch {
                self.log("❌ LLM analysis error: \(error.localizedDescription)")
                await MainActor.run {
                    self.isAnalyzing = false
                    self.detectionStatus = .buffering
                }
            }
        }
    }
    
    private func analyzeForEncounterEnd(transcript: String) {
        guard !isAnalyzing else { return }
        guard shouldAnalyze() else { return }
        
        // Don't end if encounter is too short
        if let startTime = encounterStartTime,
           Date().timeIntervalSince(startTime) < config.minEncounterDurationSeconds {
            return
        }
        
        isAnalyzing = true
        lastAnalysisTime = Date()
        
        Task {
            do {
                // Only analyze the last few transcript entries for end detection
                let recentText = recentTranscriptBuffer.suffix(5).joined(separator: "\n")
                let prompt = endDetectionPrompt + "\n\n\"\"\"\n\(recentText)\n\"\"\""
                let response = try await llmClient?.quickComplete(prompt: prompt, modelOverride: nil) ?? "CONTINUE"
                
                let decision = response.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                log("🤖 End analysis: \(decision)")
                
                await MainActor.run {
                    self.isAnalyzing = false
                    
                    if decision.contains("END") {
                        self.lastDetectedPattern = "LLM detected encounter end"
                        self.startPotentialEndTimer()
                    }
                    // If CONTINUE, just keep going - no action needed
                }
            } catch {
                log("❌ LLM end analysis error: \(error)")
                await MainActor.run {
                    self.isAnalyzing = false
                }
            }
        }
    }
    
    private func shouldAnalyze() -> Bool {
        guard let lastTime = lastAnalysisTime else { return true }
        return Date().timeIntervalSince(lastTime) >= analysisDebounceSeconds
    }
    
    // MARK: - Clinical Content Detection
    
    private func detectClinicalContent(in text: String) -> Bool {
        let lowercased = text.lowercased()
        let clinicalTerms = [
            "symptom", "pain", "medication", "prescription", "diagnosis",
            "exam", "test", "blood", "treatment", "dosage"
        ]
        
        for term in clinicalTerms {
            if lowercased.contains(term) {
                return true
            }
        }
        return false
    }
    
    // MARK: - State Transitions
    
    private func startBuffering() {
        detectionStatus = .buffering
        log("Started buffering (speech detected, waiting for transcript)")
        
        // Notify delegate to start provisional recording for transcript generation
        delegate?.sessionDetectorDidStartBuffering(self)
        
        // Set a timeout - if we don't confirm encounter start, go back to monitoring
        stopBufferTimer()
        bufferTimer = Timer.scheduledTimer(withTimeInterval: config.bufferDurationSeconds, repeats: false) { [weak self] _ in
            self?.bufferTimeout()
        }
    }
    
    private func bufferTimeout() {
        // If we're actively analyzing with LLM, extend the timeout
        if detectionStatus == .analyzing && isAnalyzing {
            log("Buffer timeout but LLM still analyzing - extending timeout")
            // Extend timer by another buffer duration
            stopBufferTimer()
            bufferTimer = Timer.scheduledTimer(withTimeInterval: config.bufferDurationSeconds, repeats: false) { [weak self] _ in
                self?.bufferTimeout()
            }
            return
        }
        
        if detectionStatus == .buffering || detectionStatus == .analyzing {
            log("Buffer timeout - returning to monitoring")
            detectionStatus = .monitoring
            recentTranscriptBuffer = []
            
            // Notify delegate to stop provisional recording
            delegate?.sessionDetectorDidCancelBuffering(self)
        }
    }
    
    private func confirmEncounterStart() {
        stopBufferTimer()
        detectionStatus = .encounterActive
        encounterStartTime = Date()
        
        log("✅ Encounter auto-started!")
        delegate?.sessionDetectorDidDetectEncounterStart(self)
    }
    
    private func startPotentialEndTimer() {
        detectionStatus = .potentialEnd
        log("Potential end detected - waiting for silence confirmation")
    }
    
    private func cancelPotentialEnd() {
        detectionStatus = .encounterActive
        lastDetectedPattern = nil
        log("End cancelled - clinical content detected")
    }
    
    private func confirmEncounterEnd() {
        log("✅ Encounter auto-ended!")
        
        if isMonitoring {
            detectionStatus = .monitoring
        } else {
            detectionStatus = .idle
        }
        
        encounterStartTime = nil
        recentTranscriptBuffer = []
        
        delegate?.sessionDetectorDidDetectEncounterEnd(self)
    }
    
    // MARK: - Silence Timer
    
    private func startSilenceTimer() {
        stopSilenceTimer()
        
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateSilenceDuration()
        }
    }
    
    private func stopSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
    
    private func stopBufferTimer() {
        bufferTimer?.invalidate()
        bufferTimer = nil
    }
    
    private func updateSilenceDuration() {
        guard let lastSpeech = lastSpeechTime else {
            currentSilenceDuration += 1
            checkSilenceThreshold()
            return
        }
        
        currentSilenceDuration = Date().timeIntervalSince(lastSpeech)
        checkSilenceThreshold()
    }
    
    private func checkSilenceThreshold() {
        // Skip all end detection if disabled
        guard config.detectEndOfEncounter else { return }
        
        // End encounter if in potentialEnd state and silence threshold exceeded
        if detectionStatus == .potentialEnd &&
           currentSilenceDuration >= config.silenceThresholdSeconds {
            confirmEncounterEnd()
        }
        
        // Also end if just in active encounter with very long silence (2x threshold)
        if detectionStatus == .encounterActive &&
           currentSilenceDuration >= (config.silenceThresholdSeconds * 2) {
            // Only if encounter has been going for a while
            if let startTime = encounterStartTime,
               Date().timeIntervalSince(startTime) >= config.minEncounterDurationSeconds {
                lastDetectedPattern = "Extended silence (\(Int(currentSilenceDuration))s)"
                confirmEncounterEnd()
            }
        }
    }
}

// MARK: - Delegate Protocol

@MainActor
protocol SessionDetectorDelegate: AnyObject {
    func sessionDetectorDidDetectEncounterStart(_ detector: SessionDetector)
    func sessionDetectorDidDetectEncounterEnd(_ detector: SessionDetector)
    func sessionDetectorDidStartBuffering(_ detector: SessionDetector)
    func sessionDetectorDidCancelBuffering(_ detector: SessionDetector)
}
