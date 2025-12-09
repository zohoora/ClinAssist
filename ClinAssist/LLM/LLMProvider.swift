import Foundation

/// Protocol for LLM completion providers
/// Implemented by LLMClient (OpenRouter), OllamaClient, and GroqClient
protocol LLMProvider {
    /// Complete a prompt with system and user content
    /// - Parameters:
    ///   - systemPrompt: The system prompt defining the assistant's behavior
    ///   - userContent: The user's input content
    ///   - modelOverride: Optional model to use instead of the default
    /// - Returns: The completion response string
    func complete(systemPrompt: String, userContent: String, modelOverride: String?) async throws -> String
}

extension LLMProvider {
    /// Convenience method without model override
    func complete(systemPrompt: String, userContent: String) async throws -> String {
        try await complete(systemPrompt: systemPrompt, userContent: userContent, modelOverride: nil)
    }
}

// MARK: - Unified Error Type

/// Unified error type for all LLM providers
enum LLMProviderError: LocalizedError {
    case invalidURL
    case invalidAPIKey(provider: String)
    case invalidResponse
    case emptyResponse
    case requestFailed(provider: String, message: String)
    case rateLimited(provider: String, message: String)
    case notAvailable(provider: String)
    case timeout(provider: String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidAPIKey(let provider):
            return "Invalid \(provider) API key. Please check your config.json."
        case .invalidResponse:
            return "Invalid response from LLM service"
        case .emptyResponse:
            return "LLM returned an empty response. Please try again."
        case .requestFailed(let provider, let message):
            return "\(provider) request failed: \(message)"
        case .rateLimited(let provider, let message):
            return "\(provider) rate limited: \(message)"
        case .notAvailable(let provider):
            return "\(provider) is not available"
        case .timeout(let provider):
            return "\(provider) request timed out"
        }
    }
}

// MARK: - Response Parsing Utilities

/// Shared utilities for parsing LLM API responses
enum LLMResponseParser {
    /// Parse OpenAI-compatible chat completion response format
    /// Used by OpenRouter, Groq, and other OpenAI-compatible APIs
    /// Also handles "thinking/reasoning" models that return content in `reasoning` field
    static func parseOpenAIChatResponse(_ data: Data) throws -> String {
        // Debug: log raw response if parsing fails
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let rawString = String(data: data, encoding: .utf8) ?? "Unable to decode as UTF-8"
            debugLog("❌ Failed to parse JSON. Raw response (first 500 chars): \(String(rawString.prefix(500)))", component: "LLMParser")
            throw LLMProviderError.invalidResponse
        }
        
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            // Log what we did get to help debug
            let keys = json.keys.joined(separator: ", ")
            debugLog("❌ Failed to parse response structure. Keys: \(keys)", component: "LLMParser")
            if let error = json["error"] as? [String: Any] {
                debugLog("❌ API Error: \(error)", component: "LLMParser")
            }
            throw LLMProviderError.invalidResponse
        }
        
        // Check content field first (standard OpenAI format)
        if let content = message["content"] as? String, !content.isEmpty {
            return content
        }
        
        // Fall back to reasoning field for "thinking" models (Gemini 3 Pro, etc.)
        // These models return their actual response in the reasoning field
        if let reasoning = message["reasoning"] as? String, !reasoning.isEmpty {
            debugLog("📝 Using reasoning field (thinking model detected)", component: "LLMParser")
            return reasoning
        }
        
        // Check if content exists but is empty (should be treated as error)
        if message["content"] != nil {
            debugLog("⚠️ Response has empty content field and no reasoning", component: "LLMParser")
            throw LLMProviderError.emptyResponse
        }
        
        debugLog("❌ No content or reasoning in response", component: "LLMParser")
        throw LLMProviderError.invalidResponse
    }
    
    /// Parse Ollama chat response format
    static func parseOllamaChatResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMProviderError.invalidResponse
        }
        return content
    }
    
    /// Parse Ollama generate response format
    static func parseOllamaGenerateResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? String else {
            throw LLMProviderError.invalidResponse
        }
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

