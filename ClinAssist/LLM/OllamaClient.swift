import Foundation

/// Client for local Ollama LLM inference
class OllamaClient: LLMProvider {
    private let baseURL: String
    private let model: String
    
    init(baseURL: String = "http://localhost:11434", model: String = "qwen3:8b") {
        self.baseURL = baseURL
        self.model = model
    }
    
    /// Check if Ollama is available
    func isAvailable() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            debugLog("Not available: \(error.localizedDescription)", component: "Ollama")
            return false
        }
    }
    
    /// Complete a prompt using Ollama (LLMProvider conformance)
    func complete(systemPrompt: String, userContent: String, modelOverride: String? = nil) async throws -> String {
        let effectiveModel = modelOverride ?? model
        
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw LLMProviderError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60  // Increased timeout for slower networks
        
        let requestBody: [String: Any] = [
            "model": effectiveModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "stream": false,
            "think": false,
            "options": [
                "temperature": 0.3,
                "num_predict": 2048
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let startTime = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let elapsed = Date().timeIntervalSince(startTime)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMProviderError.requestFailed(provider: "Ollama", message: "HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
        
        let result = try LLMResponseParser.parseOllamaChatResponse(data)
        debugLog("✅ Response in \(String(format: "%.2f", elapsed))s (\(result.count) chars)", component: "Ollama")
        return result
    }
    
    /// Complete with thinking mode enabled (for Qwen3)
    /// Uses extended reasoning before generating the response
    func completeWithThinking(systemPrompt: String, userContent: String, modelOverride: String? = nil) async throws -> String {
        let effectiveModel = modelOverride ?? model
        
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw LLMProviderError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120  // Longer timeout for thinking mode
        
        let requestBody: [String: Any] = [
            "model": effectiveModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "stream": false,
            "think": true,  // Enable thinking mode for Qwen3
            "options": [
                "temperature": 0.3,
                "num_predict": 4096  // Higher limit for thinking + response
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        debugLog("🧠 Starting thinking mode completion...", component: "Ollama")
        let startTime = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let elapsed = Date().timeIntervalSince(startTime)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMProviderError.requestFailed(provider: "Ollama", message: "HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
        
        let result = try LLMResponseParser.parseOllamaChatResponse(data)
        debugLog("🧠 Thinking completed in \(String(format: "%.2f", elapsed))s (\(result.count) chars)", component: "Ollama")
        return result
    }
    
    /// Quick completion for simple yes/no or short responses
    func quickComplete(prompt: String, modelOverride: String? = nil) async throws -> String {
        let effectiveModel = modelOverride ?? model
        
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw LLMProviderError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60  // Increased timeout for slower networks
        
        let requestBody: [String: Any] = [
            "model": effectiveModel,
            "prompt": prompt,
            "stream": false,
            "think": false,
            "options": [
                "temperature": 0.1,
                "num_predict": 64
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMProviderError.invalidResponse
        }
        
        return try LLMResponseParser.parseOllamaGenerateResponse(data)
    }
}

// MARK: - Legacy Error Type (deprecated, use LLMProviderError)

@available(*, deprecated, message: "Use LLMProviderError instead")
typealias OllamaError = LLMProviderError

