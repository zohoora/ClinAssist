import Foundation

/// Orchestrates LLM provider selection based on configuration and availability
/// Handles fallback logic: Groq -> Ollama -> OpenRouter
class LLMOrchestrator {
    
    // MARK: - Providers
    
    private var openRouterClient: LLMClient?
    private var ollamaClient: OllamaClient?
    private var groqClient: GroqClient?
    
    // MARK: - Configuration
    
    private let configManager: ConfigManager
    
    // MARK: - Availability State
    
    @Published private(set) var ollamaAvailable: Bool = false
    
    // MARK: - Initialization
    
    init(configManager: ConfigManager) {
        self.configManager = configManager
        setupClients()
    }
    
    /// For testing with injected clients
    init(configManager: ConfigManager, 
         openRouterClient: LLMClient? = nil,
         ollamaClient: OllamaClient? = nil,
         groqClient: GroqClient? = nil) {
        self.configManager = configManager
        self.openRouterClient = openRouterClient
        self.ollamaClient = ollamaClient
        self.groqClient = groqClient
    }
    
    // MARK: - Setup
    
    private func setupClients() {
        guard let config = configManager.config else { return }
        
        // Setup OpenRouter (always available as fallback)
        openRouterClient = LLMClient(apiKey: config.openrouterApiKey, model: config.model)
        debugLog("☁️ OpenRouter client configured with model: \(config.model)", component: "LLMOrchestrator")
        
        // Setup Groq if configured
        if configManager.isGroqEnabled {
            groqClient = GroqClient(apiKey: configManager.groqApiKey, model: configManager.groqModel)
            debugLog("⚡ Groq client configured with model: \(configManager.groqModel)", component: "LLMOrchestrator")
        }
        
        // Setup Ollama if configured
        if configManager.isOllamaEnabled {
            ollamaClient = OllamaClient(baseURL: configManager.ollamaBaseUrl, model: configManager.ollamaModel)
            debugLog("🦙 Ollama client configured: \(configManager.ollamaBaseUrl)", component: "LLMOrchestrator")
            
            // Check availability asynchronously
            Task {
                await checkOllamaAvailability()
            }
        }
    }
    
    /// Check if Ollama is available
    func checkOllamaAvailability() async {
        guard let client = ollamaClient else {
            ollamaAvailable = false
            return
        }
        
        let available = await client.isAvailable()
        await MainActor.run {
            self.ollamaAvailable = available
            if available {
                debugLog("✅ Ollama is available", component: "LLMOrchestrator")
            } else {
                debugLog("⚠️ Ollama is not available", component: "LLMOrchestrator")
            }
        }
    }
    
    // MARK: - Completion Methods
    
    // Threshold for "large" transcripts that need Gemini's 1M context window
    private let largeTranscriptThreshold = 500
    
    // Gemini 3 Pro model on OpenRouter (1M context window)
    private let geminiModel = "google/gemini-3-pro"
    
    /// Generate final SOAP note
    /// For large transcripts (>500 entries): Use Gemini 2.5 Pro (1M context)
    /// For smaller transcripts: Use Groq (fastest)
    func generateFinalSOAP(systemPrompt: String, content: String, transcriptEntryCount: Int = 0) async throws -> String {
        
        // For large transcripts, use Gemini 3 Pro via OpenRouter (1M context window)
        if transcriptEntryCount > largeTranscriptThreshold {
            debugLog("📊 Large transcript (\(transcriptEntryCount) entries) - using Gemini 3 Pro (1M context)", component: "LLMOrchestrator")
            
            guard let openRouter = openRouterClient else {
                throw LLMProviderError.notAvailable(provider: "OpenRouter")
            }
            
            let startTime = Date()
            let response = try await openRouter.complete(
                systemPrompt: systemPrompt,
                userContent: content,
                modelOverride: geminiModel
            )
            let elapsed = Date().timeIntervalSince(startTime)
            debugLog("✅ Gemini 3 Pro completed in \(String(format: "%.2f", elapsed))s", component: "LLMOrchestrator")
            return response
        }
        
        // For smaller transcripts, try Groq first (fastest)
        if configManager.useGroqForFinalSoap, let groq = groqClient {
            debugLog("⚡ Using Groq for final SOAP (\(transcriptEntryCount) entries)", component: "LLMOrchestrator")
            let startTime = Date()
            do {
                let response = try await groq.complete(systemPrompt: systemPrompt, userContent: content)
                let elapsed = Date().timeIntervalSince(startTime)
                debugLog("✅ Groq completed in \(String(format: "%.2f", elapsed))s", component: "LLMOrchestrator")
                return response
            } catch {
                debugLog("⚠️ Groq failed: \(error.localizedDescription), trying Gemini...", component: "LLMOrchestrator")
                // Fall through to Gemini
            }
        }
        
        // Fallback to Gemini 3 Pro for any size
        guard let openRouter = openRouterClient else {
            throw LLMProviderError.notAvailable(provider: "Any LLM")
        }
        
        debugLog("☁️ Using Gemini 3 Pro as fallback", component: "LLMOrchestrator")
        return try await openRouter.complete(
            systemPrompt: systemPrompt,
            userContent: content,
            modelOverride: geminiModel
        )
    }
    
    /// Generate live SOAP note (uses local if available: Ollama > OpenRouter)
    func generateLiveSOAP(systemPrompt: String, content: String) async throws -> String {
        // Try Ollama first (local, no rate limits)
        if ollamaAvailable && configManager.useOllamaForLiveSoap, let ollama = ollamaClient {
            debugLog("🦙 Using Ollama for live SOAP", component: "LLMOrchestrator")
            return try await ollama.complete(systemPrompt: systemPrompt, userContent: content)
        }
        
        // Fallback to OpenRouter
        guard let openRouter = openRouterClient else {
            throw LLMProviderError.notAvailable(provider: "Any LLM")
        }
        
        debugLog("☁️ Using OpenRouter for live SOAP", component: "LLMOrchestrator")
        return try await openRouter.complete(systemPrompt: systemPrompt, userContent: content)
    }
    
    /// Generate helper suggestions (uses local if available: Ollama > OpenRouter)
    func generateHelperSuggestions(systemPrompt: String, content: String) async throws -> String {
        // Try Ollama first
        if ollamaAvailable && configManager.useOllamaForHelpers, let ollama = ollamaClient {
            debugLog("🦙 Using Ollama for helpers", component: "LLMOrchestrator")
            return try await ollama.complete(systemPrompt: systemPrompt, userContent: content)
        }
        
        // Fallback to OpenRouter
        guard let openRouter = openRouterClient else {
            throw LLMProviderError.notAvailable(provider: "Any LLM")
        }
        
        debugLog("☁️ Using OpenRouter for helpers", component: "LLMOrchestrator")
        return try await openRouter.complete(systemPrompt: systemPrompt, userContent: content)
    }
    
    /// Get the Ollama client for session detection (if available and configured)
    func getOllamaClientForSessionDetection() -> OllamaClient? {
        guard ollamaAvailable && configManager.useOllamaForSessionDetection else {
            return nil
        }
        return ollamaClient
    }
    
    // MARK: - Accessors
    
    /// Check if any LLM provider is available
    var isAvailable: Bool {
        openRouterClient != nil || ollamaAvailable || groqClient != nil
    }
    
    /// Get the underlying Ollama client
    var ollama: OllamaClient? { ollamaClient }
}

