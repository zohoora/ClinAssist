import Foundation

/// Orchestrates LLM provider selection based on configuration and availability
/// Uses scenario-based config: standard, large, multimodal, backup
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
    
    /// Generate final SOAP note using scenario-based model selection
    /// Scenarios: multimodal -> large -> standard -> backup
    func generateFinalSOAP(systemPrompt: String, content: String, transcriptEntryCount: Int = 0, attachments: [EncounterAttachment] = []) async throws -> String {
        
        debugLog("📋 generateFinalSOAP called: content=\(content.count) chars, transcriptCount=\(transcriptEntryCount), attachments=\(attachments.count)", component: "LLMOrchestrator")
        
        // Log a snippet of the content for debugging
        let contentPreview = String(content.prefix(500))
        debugLog("📋 Content preview: \(contentPreview)...", component: "LLMOrchestrator")
        
        // Check for multimodal content
        let hasMultimodalContent = attachments.contains { $0.isMultimodal }
        
        // Determine scenario
        let scenario: LLMScenario
        if hasMultimodalContent {
            scenario = .multimodal
        } else if transcriptEntryCount > largeTranscriptThreshold {
            scenario = .large
        } else {
            scenario = .standard
        }
        
        let model = configManager.getModel(for: .finalSoap, scenario: scenario)
        debugLog("🎯 Final SOAP scenario: \(scenario.displayName), model: \(model.displayName)", component: "LLMOrchestrator")
        
        // Handle multimodal separately (requires special API format)
        if hasMultimodalContent {
            debugLog("🖼️ Multimodal content detected (\(attachments.filter { $0.isMultimodal }.count) items)", component: "LLMOrchestrator")
            let multimodalModel = configManager.getModel(for: .finalSoap, scenario: .multimodal)
            return try await generateMultimodalSOAP(systemPrompt: systemPrompt, content: content, attachments: attachments, model: multimodalModel)
        }
        
        // Try primary model
        do {
            return try await executeWithModel(model, function: .finalSoap, systemPrompt: systemPrompt, content: content)
        } catch {
            debugLog("⚠️ Primary model \(model.displayName) failed: \(error.localizedDescription)", component: "LLMOrchestrator")
            
            // Try backup model
            let backupModel = configManager.getModel(for: .finalSoap, scenario: .backup)
            if backupModel.id != model.id {
                debugLog("🔄 Trying backup model: \(backupModel.displayName)", component: "LLMOrchestrator")
                return try await executeWithModel(backupModel, function: .finalSoap, systemPrompt: systemPrompt, content: content)
            }
            
            throw error
        }
    }
    
    // MARK: - Multimodal SOAP Generation
    
    /// Generate SOAP note with multimodal content (images, PDFs)
    /// Uses the configured multimodal model via OpenRouter
    private func generateMultimodalSOAP(systemPrompt: String, content: String, attachments: [EncounterAttachment], model: LLMModelOption) async throws -> String {
        guard let config = configManager.config else {
            throw LLMProviderError.notAvailable(provider: "OpenRouter")
        }
        
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
            throw LLMProviderError.invalidURL
        }
        
        let startTime = Date()
        debugLog("🖼️ Building multimodal request with \(attachments.count) attachments using \(model.displayName)", component: "LLMOrchestrator")
        
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
            "model": model.modelId,
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
    
    // MARK: - Model Execution
    
    /// Execute a completion with the specified model
    private func executeWithModel(_ model: LLMModelOption, function: LLMFunction, systemPrompt: String, content: String) async throws -> String {
        let startTime = Date()
        
        switch model.provider {
        case .ollama:
            guard ollamaAvailable, let ollama = ollamaClient else {
                throw LLMProviderError.notAvailable(provider: "Ollama")
            }
            debugLog("🦙 Using \(model.displayName) for \(function.displayName)", component: "LLMOrchestrator")
            let response = try await ollama.complete(systemPrompt: systemPrompt, userContent: content, modelOverride: model.modelId)
            let elapsed = Date().timeIntervalSince(startTime)
            debugLog("✅ Ollama completed in \(String(format: "%.2f", elapsed))s", component: "LLMOrchestrator")
            return response
            
        case .groq:
            guard let groq = groqClient else {
                throw LLMProviderError.notAvailable(provider: "Groq")
            }
            debugLog("⚡ Using \(model.displayName) for \(function.displayName)", component: "LLMOrchestrator")
            let response = try await groq.complete(systemPrompt: systemPrompt, userContent: content, modelOverride: model.modelId)
            let elapsed = Date().timeIntervalSince(startTime)
            debugLog("✅ Groq completed in \(String(format: "%.2f", elapsed))s", component: "LLMOrchestrator")
            return response
            
        case .openRouter:
            guard let openRouter = openRouterClient else {
                throw LLMProviderError.notAvailable(provider: "OpenRouter")
            }
            debugLog("☁️ Using \(model.displayName) for \(function.displayName)", component: "LLMOrchestrator")
            let response = try await openRouter.complete(systemPrompt: systemPrompt, userContent: content, modelOverride: model.modelId)
            let elapsed = Date().timeIntervalSince(startTime)
            debugLog("✅ OpenRouter completed in \(String(format: "%.2f", elapsed))s", component: "LLMOrchestrator")
            return response
        }
    }
    
    /// Generate Psst... predictions using scenario-based model selection
    func generatePsstPrediction(systemPrompt: String, content: String) async throws -> String {
        let model = configManager.getModel(for: .psst, scenario: .standard)
        debugLog("🔮 Psst prediction model: \(model.displayName)", component: "LLMOrchestrator")
        
        do {
            return try await executeWithModel(model, function: .psst, systemPrompt: systemPrompt, content: content)
        } catch {
            debugLog("⚠️ Primary model \(model.displayName) failed: \(error.localizedDescription)", component: "LLMOrchestrator")
            
            // Try backup model
            let backupModel = configManager.getModel(for: .psst, scenario: .backup)
            if backupModel.id != model.id {
                debugLog("🔄 Trying backup model: \(backupModel.displayName)", component: "LLMOrchestrator")
                return try await executeWithModel(backupModel, function: .psst, systemPrompt: systemPrompt, content: content)
            }
            
            throw error
        }
    }
    
    /// Get the Ollama client for session detection (if available and configured)
    func getOllamaClientForSessionDetection() -> OllamaClient? {
        let model = configManager.getModel(for: .sessionDetection, scenario: .standard)
        guard model.provider == .ollama, ollamaAvailable else {
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


