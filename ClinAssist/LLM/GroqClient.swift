import Foundation

/// Client for Groq's fast LLM API
class GroqClient: LLMProvider {
    private let apiKey: String
    private let model: String
    private let baseURL = "https://api.groq.com/openai/v1/chat/completions"
    
    init(apiKey: String, model: String = "openai/gpt-oss-120b") {
        self.apiKey = apiKey
        self.model = model
    }
    
    func complete(systemPrompt: String, userContent: String, modelOverride: String? = nil) async throws -> String {
        guard let url = URL(string: baseURL) else {
            throw LLMProviderError.invalidURL
        }
        
        let effectiveModel = modelOverride ?? model
        let startTime = Date()
        debugLog("🚀 Calling model: \(effectiveModel)", component: "Groq")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
        let requestBody: [String: Any] = [
            "model": effectiveModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "temperature": 0.3,
            "max_tokens": 4096
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog("❌ Invalid response type", component: "Groq")
            throw LLMProviderError.invalidResponse
        }
        
        debugLog("📡 Response status: \(httpResponse.statusCode) in \(String(format: "%.2f", elapsed))s", component: "Groq")
        
        if httpResponse.statusCode == 401 {
            debugLog("❌ Invalid API key", component: "Groq")
            throw LLMProviderError.invalidAPIKey(provider: "Groq")
        }
        
        if httpResponse.statusCode == 429 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Rate limited"
            debugLog("⚠️ Rate limited: \(errorMessage)", component: "Groq")
            throw LLMProviderError.rateLimited(provider: "Groq", message: errorMessage)
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            debugLog("❌ Error: \(errorMessage)", component: "Groq")
            throw LLMProviderError.requestFailed(provider: "Groq", message: "HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
        
        let result = try LLMResponseParser.parseOpenAIChatResponse(data)
        debugLog("✅ Got response (\(result.count) chars) in \(String(format: "%.2f", elapsed))s", component: "Groq")
        return result
    }
}

extension GroqClient: SessionDetectorLLMClient {
    /// Fast short response completion used by SessionDetector (expects 1-word outputs like START/WAIT/END/CONTINUE).
    func quickComplete(prompt: String, modelOverride: String? = nil) async throws -> String {
        guard let url = URL(string: baseURL) else {
            throw LLMProviderError.invalidURL
        }
        
        let effectiveModel = modelOverride ?? model
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        let requestBody: [String: Any] = [
            "model": effectiveModel,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.1,
            "max_tokens": 64
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw LLMProviderError.invalidAPIKey(provider: "Groq")
        }
        
        if httpResponse.statusCode == 429 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Rate limited"
            throw LLMProviderError.rateLimited(provider: "Groq", message: errorMessage)
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMProviderError.requestFailed(provider: "Groq", message: "HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
        
        return try LLMResponseParser.parseOpenAIChatResponse(data)
    }
}

// MARK: - Legacy Error Type (deprecated, use LLMProviderError)

@available(*, deprecated, message: "Use LLMProviderError instead")
typealias GroqError = LLMProviderError

