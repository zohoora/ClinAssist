import Foundation

/// Orchestrates LLM provider selection based on configuration and availability
/// Handles fallback logic: Groq -> Ollama -> OpenRouter
@MainActor
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
    
    /// For production use with pre-configured clients (from EncounterController)
    /// Also used for testing with injected clients
    init(configManager: ConfigManager, 
         openRouterClient: LLMClient? = nil,
         ollamaClient: OllamaClient? = nil,
         groqClient: GroqClient? = nil) {
        self.configManager = configManager
        self.openRouterClient = openRouterClient
        self.ollamaClient = ollamaClient
        self.groqClient = groqClient
        
        // Check Ollama availability if client was provided
        if ollamaClient != nil {
            Task {
                await checkOllamaAvailability()
            }
        }
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
    
    // Gemini 2.5 Flash model on OpenRouter (1M context window, fast, non-thinking)
    // Note: Avoid "preview" models as they may be thinking models that return empty content
    private let geminiModel = "google/gemini-2.5-flash"
    
    // Gemini 2.5 Flash for multimodal (images, PDFs) - fast and reliable
    private let geminiMultimodalModel = "google/gemini-2.5-flash"
    
    /// Generate final SOAP note
    /// Priority order:
    /// 1. Multimodal content (images/PDFs): Use Gemini 2.5 Flash (multimodal)
    /// 2. Large transcripts (>500 entries): Use Gemini 2.5 Flash (1M context)
    /// 3. Groq (if configured): Fast cloud inference for small/medium transcripts
    /// 4. Ollama (if configured): Local fallback if Groq fails
    /// 5. Fallback: Gemini 2.5 Flash via OpenRouter
    func generateFinalSOAP(systemPrompt: String, content: String, transcriptEntryCount: Int = 0, attachments: [EncounterAttachment] = []) async throws -> String {
        
        debugLog("📋 generateFinalSOAP called: content=\(content.count) chars, transcriptCount=\(transcriptEntryCount), attachments=\(attachments.count)", component: "LLMOrchestrator")
        
        // Log a snippet of the content for debugging
        let contentPreview = String(content.prefix(500))
        debugLog("📋 Content preview: \(contentPreview)...", component: "LLMOrchestrator")
        
        // Check for multimodal content - if present, MUST use Gemini multimodal
        let hasMultimodalContent = attachments.contains { $0.isMultimodal }
        
        if hasMultimodalContent {
            debugLog("🖼️ Multimodal content detected (\(attachments.filter { $0.isMultimodal }.count) items) - using Gemini 2.5 Flash", component: "LLMOrchestrator")
            return try await generateMultimodalSOAP(systemPrompt: systemPrompt, content: content, attachments: attachments)
        }
        
        // For large transcripts, use Gemini 2.5 Flash via OpenRouter (1M context window)
        if transcriptEntryCount > largeTranscriptThreshold {
            debugLog("📊 Large transcript (\(transcriptEntryCount) entries) - using Gemini 2.5 Flash (1M context)", component: "LLMOrchestrator")
            
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
            debugLog("✅ Gemini 2.5 Flash completed in \(String(format: "%.2f", elapsed))s", component: "LLMOrchestrator")
            return response
        }
        
        // Try Groq first (fast cloud inference for small/medium transcripts)
        if configManager.useGroqForFinalSoap, let groq = groqClient {
            debugLog("⚡ Using Groq for final SOAP (\(transcriptEntryCount) entries)", component: "LLMOrchestrator")
            let startTime = Date()
            do {
                let response = try await groq.complete(systemPrompt: systemPrompt, userContent: content)
                let elapsed = Date().timeIntervalSince(startTime)
                debugLog("✅ Groq completed in \(String(format: "%.2f", elapsed))s", component: "LLMOrchestrator")
                return response
            } catch {
                debugLog("⚠️ Groq failed: \(error.localizedDescription), trying Ollama...", component: "LLMOrchestrator")
                // Fall through to Ollama
            }
        }
        
        // Try Ollama as fallback (local, no rate limits)
        if ollamaAvailable && configManager.useOllamaForFinalSoap, let ollama = ollamaClient {
            debugLog("🦙 Using Ollama for final SOAP (\(transcriptEntryCount) entries)", component: "LLMOrchestrator")
            let startTime = Date()
            do {
                let response = try await ollama.complete(systemPrompt: systemPrompt, userContent: content)
                let elapsed = Date().timeIntervalSince(startTime)
                debugLog("✅ Ollama completed in \(String(format: "%.2f", elapsed))s", component: "LLMOrchestrator")
                return response
            } catch {
                debugLog("⚠️ Ollama failed: \(error.localizedDescription), trying Gemini...", component: "LLMOrchestrator")
                // Fall through to Gemini
            }
        }
        
        // Fallback to Gemini 2.5 Flash for any size
        guard let openRouter = openRouterClient else {
            throw LLMProviderError.notAvailable(provider: "Any LLM")
        }
        
        debugLog("☁️ Using Gemini 2.5 Flash as fallback", component: "LLMOrchestrator")
        return try await openRouter.complete(
            systemPrompt: systemPrompt,
            userContent: content,
            modelOverride: geminiModel
        )
    }
    
    // MARK: - Multimodal SOAP Generation
    
    /// Generate SOAP note with multimodal content (images, PDFs)
    /// Uses Gemini 2.5 Flash via OpenRouter with multimodal message format
    private func generateMultimodalSOAP(systemPrompt: String, content: String, attachments: [EncounterAttachment]) async throws -> String {
        guard let config = configManager.config else {
            throw LLMProviderError.notAvailable(provider: "OpenRouter")
        }
        
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
            throw LLMProviderError.invalidURL
        }
        
        let startTime = Date()
        debugLog("🖼️ Building multimodal request with \(attachments.count) attachments", component: "LLMOrchestrator")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.openrouterApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://clinassist.local", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("ClinAssist", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 120  // Longer timeout for multimodal
        
        // Build multimodal content array
        var contentParts: [[String: Any]] = []
        
        // Add text content first
        contentParts.append(["type": "text", "text": content])
        
        // Add attachments
        for attachment in attachments {
            if attachment.isMultimodal, let base64 = attachment.base64Data, let mimeType = attachment.mimeType {
                debugLog("📎 Adding \(attachment.type.rawValue): \(attachment.name) (\(mimeType))", component: "LLMOrchestrator")
                
                // Both images and PDFs use the same format for Gemini
                contentParts.append([
                    "type": "image_url",
                    "image_url": [
                        "url": "data:\(mimeType);base64,\(base64)"
                    ]
                ])
            } else if let textContent = attachment.textContent {
                // Text-only attachments - append to text content
                contentParts.append([
                    "type": "text",
                    "text": "\n\n--- Attached Document: \(attachment.name) ---\n\(textContent)"
                ])
            }
        }
        
        let requestBody: [String: Any] = [
            "model": geminiMultimodalModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": contentParts]
            ],
            "temperature": 0.3,
            "max_tokens": 8192
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog("❌ Invalid response type", component: "LLMOrchestrator")
            throw LLMProviderError.invalidResponse
        }
        
        debugLog("📡 Multimodal response status: \(httpResponse.statusCode) in \(String(format: "%.2f", elapsed))s", component: "LLMOrchestrator")
        
        if httpResponse.statusCode == 401 {
            debugLog("❌ Invalid API key", component: "LLMOrchestrator")
            throw LLMProviderError.invalidAPIKey(provider: "OpenRouter")
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            debugLog("❌ Multimodal error: \(errorMessage)", component: "LLMOrchestrator")
            throw LLMProviderError.requestFailed(provider: "OpenRouter", message: "HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
        
        let result = try LLMResponseParser.parseOpenAIChatResponse(data)
        debugLog("✅ Multimodal SOAP completed in \(String(format: "%.2f", elapsed))s (\(result.count) chars)", component: "LLMOrchestrator")
        return result
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


