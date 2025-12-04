import Foundation
@testable import ClinAssist

/// Mock LLM client for testing without API calls
@MainActor
class MockLLMClient: LLMClient {
    var completeResponse: String = "{}"
    var mockResponse: String = "{}"
    var shouldThrowError: Bool = false
    var shouldFail: Bool = false
    var errorToThrow: Error = LLMProviderError.invalidResponse
    var lastSystemPrompt: String?
    var lastUserContent: String?
    var callCount: Int = 0
    var completeCalled: Bool = false
    
    init() {
        super.init(apiKey: "test-api-key", model: "test-model")
    }
    
    override func complete(systemPrompt: String, userContent: String, modelOverride: String? = nil) async throws -> String {
        callCount += 1
        completeCalled = true
        lastSystemPrompt = systemPrompt
        lastUserContent = userContent
        
        if shouldThrowError || shouldFail {
            throw errorToThrow
        }
        return mockResponse.isEmpty ? completeResponse : mockResponse
    }
    
    func reset() {
        completeResponse = "{}"
        mockResponse = "{}"
        shouldThrowError = false
        shouldFail = false
        lastSystemPrompt = nil
        lastUserContent = nil
        callCount = 0
        completeCalled = false
    }
    
    /// Sets up a successful response
    func setupSuccess(response: String) {
        shouldFail = false
        shouldThrowError = false
        mockResponse = response
    }
}

// MARK: - Preconfigured Mocks

extension MockLLMClient {
    /// Returns a mock that provides valid helper suggestions
    static func withHelperSuggestions() -> MockLLMClient {
        let mock = MockLLMClient()
        mock.completeResponse = """
        {
            "differentialDiagnosis": ["Hypertension", "Anxiety"],
            "issues": [{"description": "Elevated BP", "addressed_in_plan": false}],
            "drugCards": [{"name": "Lisinopril", "dosage": "10mg", "frequency": "Daily"}]
        }
        """
        return mock
    }
    
    /// Returns a mock that provides a SOAP note
    static func withSOAPNote() -> MockLLMClient {
        let mock = MockLLMClient()
        mock.completeResponse = """
        PATIENT: John Smith
        
        S:
        - Chief complaint: Headache for 3 days
        - No fever or vomiting
        
        O:
        - BP 120/80
        - Alert and oriented
        
        A:
        - Tension headache
        
        P:
        - Ibuprofen 400mg TID PRN
        - Follow up if no improvement in 1 week
        """
        return mock
    }
    
    /// Returns a mock that simulates API failure
    static func failing(with error: LLMProviderError) -> MockLLMClient {
        let mock = MockLLMClient()
        mock.shouldThrowError = true
        mock.errorToThrow = error
        return mock
    }
    
    /// Returns a mock that provides empty JSON response
    static func empty() -> MockLLMClient {
        let mock = MockLLMClient()
        mock.completeResponse = """
        {
            "differentialDiagnosis": [],
            "issues": [],
            "drugCards": []
        }
        """
        return mock
    }
    
    /// Returns a mock that provides JSON wrapped in markdown
    static func withMarkdownWrappedJSON() -> MockLLMClient {
        let mock = MockLLMClient()
        mock.completeResponse = """
        ```json
        {
            "differentialDiagnosis": ["Test"],
            "issues": [],
            "drugCards": []
        }
        ```
        """
        return mock
    }
}

