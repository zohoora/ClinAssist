import Foundation
@testable import ClinAssist

/// Mock Ollama client for testing without network calls
class MockOllamaClient: SessionDetectorLLMClient {
    var isAvailableResult: Bool = true
    var completeResponse: String = ""
    var quickCompleteResponse: String = "START"
    var shouldThrowError: Bool = false
    var errorToThrow: Error = LLMProviderError.notAvailable(provider: "Ollama")
    
    private let model: String
    
    init(model: String = "test-model") {
        self.model = model
    }
    
    func isAvailable() async -> Bool {
        return isAvailableResult
    }
    
    func complete(systemPrompt: String, userContent: String, modelOverride: String? = nil) async throws -> String {
        if shouldThrowError {
            throw errorToThrow
        }
        return completeResponse
    }
    
    func quickComplete(prompt: String, modelOverride: String? = nil) async throws -> String {
        if shouldThrowError {
            throw errorToThrow
        }
        return quickCompleteResponse
    }
}

// MARK: - Preconfigured Mocks

extension MockOllamaClient {
    /// Returns a mock that always indicates encounter should start
    static func alwaysStart() -> MockOllamaClient {
        let mock = MockOllamaClient()
        mock.quickCompleteResponse = "START"
        return mock
    }
    
    /// Returns a mock that always indicates encounter should end
    static func alwaysEnd() -> MockOllamaClient {
        let mock = MockOllamaClient()
        mock.quickCompleteResponse = "END"
        return mock
    }
    
    /// Returns a mock that always continues monitoring
    static func alwaysContinue() -> MockOllamaClient {
        let mock = MockOllamaClient()
        mock.quickCompleteResponse = "CONTINUE"
        return mock
    }
    
    /// Returns a mock that simulates Ollama being unavailable
    static func unavailable() -> MockOllamaClient {
        let mock = MockOllamaClient()
        mock.isAvailableResult = false
        return mock
    }
    
    /// Returns a mock that throws errors
    static func failing(with error: Error) -> MockOllamaClient {
        let mock = MockOllamaClient()
        mock.shouldThrowError = true
        mock.errorToThrow = error
        return mock
    }
}

