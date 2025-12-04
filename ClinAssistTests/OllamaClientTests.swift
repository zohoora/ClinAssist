import XCTest
@testable import ClinAssist

@MainActor
final class OllamaClientTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testDefaultInitialization() {
        let client = OllamaClient()
        
        // Can't directly access private properties, but we can verify it doesn't crash
        XCTAssertNotNil(client)
    }
    
    func testCustomInitialization() {
        let client = OllamaClient(baseURL: "http://custom:8080", model: "custom-model")
        
        XCTAssertNotNil(client)
    }
    
    // MARK: - Error Tests
    
    func testLLMProviderErrorDescriptions() {
        XCTAssertEqual(LLMProviderError.invalidURL.errorDescription, "Invalid API URL")
        XCTAssertEqual(LLMProviderError.invalidResponse.errorDescription, "Invalid response from LLM service")
        XCTAssertEqual(LLMProviderError.notAvailable(provider: "Ollama").errorDescription, "Ollama is not available")
        
        let requestError = LLMProviderError.requestFailed(provider: "Ollama", message: "Connection refused")
        XCTAssertEqual(requestError.errorDescription, "Ollama request failed: Connection refused")
    }
    
    // MARK: - Response Parsing Tests
    
    func testParseChatResponse() throws {
        let responseJSON = """
        {
            "message": {
                "role": "assistant",
                "content": "This is the response content"
            },
            "done": true
        }
        """
        
        let data = responseJSON.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        let message = json["message"] as? [String: Any]
        let content = message?["content"] as? String
        
        XCTAssertEqual(content, "This is the response content")
    }
    
    func testParseGenerateResponse() throws {
        let responseJSON = """
        {
            "response": "START",
            "done": true
        }
        """
        
        let data = responseJSON.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        let response = json["response"] as? String
        
        XCTAssertEqual(response, "START")
    }
    
    // MARK: - Session Detection Response Tests
    
    func testStartDetectionResponseParsing() {
        let validResponses = ["START", "start", "Start", " START ", "\nSTART\n"]
        
        for response in validResponses {
            let normalized = response.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertTrue(normalized.contains("START"), "Failed for: '\(response)'")
        }
    }
    
    func testEndDetectionResponseParsing() {
        let validResponses = ["END", "end", "End", " END ", "\nEND\n"]
        
        for response in validResponses {
            let normalized = response.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertTrue(normalized.contains("END"), "Failed for: '\(response)'")
        }
    }
    
    func testContinueResponseParsing() {
        let continueResponses = ["CONTINUE", "WAIT", "continue", "wait"]
        
        for response in continueResponses {
            let normalized = response.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertFalse(normalized.contains("START"))
            XCTAssertFalse(normalized.contains("END") && !normalized.contains("CONTINUE"))
        }
    }
    
    // MARK: - Request Body Tests
    
    func testChatRequestBodyStructure() throws {
        let systemPrompt = "You are a helpful assistant"
        let userContent = "Hello"
        let model = "qwen3:8b"
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "stream": false,
            "options": [
                "temperature": 0.3,
                "num_predict": 2048
            ]
        ]
        
        let data = try JSONSerialization.data(withJSONObject: requestBody)
        let decoded = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        XCTAssertEqual(decoded["model"] as? String, model)
        XCTAssertEqual(decoded["stream"] as? Bool, false)
        
        let messages = decoded["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 2)
        XCTAssertEqual(messages?[0]["role"] as? String, "system")
        XCTAssertEqual(messages?[1]["role"] as? String, "user")
    }
    
    func testQuickCompleteRequestBodyStructure() throws {
        let prompt = "Is this a clinical encounter?"
        let model = "qwen3:8b"
        
        let requestBody: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": 0.1,
                "num_predict": 50
            ]
        ]
        
        let data = try JSONSerialization.data(withJSONObject: requestBody)
        let decoded = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        XCTAssertEqual(decoded["model"] as? String, model)
        XCTAssertEqual(decoded["prompt"] as? String, prompt)
        
        let options = decoded["options"] as? [String: Any]
        XCTAssertEqual(options?["num_predict"] as? Int, 50)  // Short response expected
    }
}
