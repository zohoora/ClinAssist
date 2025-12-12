import XCTest
@testable import ClinAssist

@MainActor
final class LLMClientTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Intercept URLSession.shared requests for networked tests.
        URLProtocol.registerClass(MockURLProtocol.self)
        MockURLProtocol.reset()
    }
    
    override func tearDownWithError() throws {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.reset()
    }
    
    // MARK: - JSON Parsing Helper Tests
    
    func testCleanJSONParsingFromMarkdown() {
        let wrappedJSON = """
        ```json
        {
            "ddx": ["Test"],
            "red_flags": [],
            "suggested_questions": [],
            "issues": [],
            "drug_cards": []
        }
        ```
        """
        
        let cleaned = cleanJSONFromMarkdown(wrappedJSON)
        XCTAssertFalse(cleaned.contains("```"))
        
        // Should be parseable
        let data = cleaned.data(using: .utf8)!
        XCTAssertNoThrow(try JSONDecoder().decode(HelperSuggestions.self, from: data))
    }
    
    func testCleanJSONWithoutMarkdown() {
        let plainJSON = """
        {
            "ddx": ["Migraine"],
            "red_flags": [],
            "suggested_questions": [],
            "issues": [],
            "drug_cards": []
        }
        """
        
        let cleaned = cleanJSONFromMarkdown(plainJSON)
        XCTAssertEqual(cleaned.trimmingCharacters(in: .whitespacesAndNewlines), 
                       plainJSON.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    func testCleanJSONWithGenericCodeBlock() {
        let genericBlock = """
        ```
        {"key": "value"}
        ```
        """
        
        let cleaned = cleanJSONFromMarkdown(genericBlock)
        XCTAssertFalse(cleaned.contains("```"))
    }
    
    // MARK: - Response Parsing Tests
    
    func testParseValidHelperSuggestions() {
        let json = """
        {
            "ddx": ["Hypertension", "Anxiety"],
            "red_flags": ["Chest pain"],
            "suggested_questions": ["Any family history?"],
            "issues": [
                {"label": "Elevated BP", "addressed_in_plan": true}
            ],
            "drug_cards": [
                {"name": "Lisinopril", "class": "ACE Inhibitor", "typical_adult_dose": "10mg daily", "key_cautions": ["Cough", "Hyperkalemia"]}
            ]
        }
        """
        
        let result = safeParse(json, as: HelperSuggestions.self)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.ddx.count, 2)
        XCTAssertEqual(result?.issues.count, 1)
        XCTAssertEqual(result?.drugCards.count, 1)
    }
    
    func testParseInvalidJSONReturnsNil() {
        let invalidJSON = "{ not valid json }"
        
        let result = safeParse(invalidJSON, as: HelperSuggestions.self)
        
        XCTAssertNil(result)
    }
    
    func testParseJSONWithExtraWhitespace() {
        let jsonWithWhitespace = """
        
        
        {
            "ddx": ["Test"],
            "red_flags": [],
            "suggested_questions": [],
            "issues": [],
            "drug_cards": []
        }
        
        
        """
        
        let result = safeParse(jsonWithWhitespace, as: HelperSuggestions.self)
        
        XCTAssertNotNil(result)
    }
    
    // MARK: - Error Handling Tests
    
    func testLLMProviderErrorDescriptions() {
        XCTAssertEqual(LLMProviderError.invalidURL.errorDescription, "Invalid API URL")
        XCTAssertEqual(LLMProviderError.invalidAPIKey(provider: "OpenRouter").errorDescription, "Invalid OpenRouter API key. Please check your config.json.")
        XCTAssertEqual(LLMProviderError.invalidResponse.errorDescription, "Invalid response from LLM service")
        
        let requestError = LLMProviderError.requestFailed(provider: "OpenRouter", message: "Server error")
        XCTAssertEqual(requestError.errorDescription, "OpenRouter request failed: Server error")
    }
    
    // MARK: - Prompts Tests
    
    func testSOAPRendererPromptExists() {
        XCTAssertFalse(LLMPrompts.soapRenderer.isEmpty)
        XCTAssertTrue(LLMPrompts.soapRenderer.contains("SOAP"))
    }
    
    func testHelperSuggestionsPromptExists() {
        XCTAssertFalse(LLMPrompts.helperSuggestions.isEmpty)
        XCTAssertTrue(LLMPrompts.helperSuggestions.contains("ddx") || LLMPrompts.helperSuggestions.contains("differential"))
    }
    
    func testStateUpdaterPromptExists() {
        XCTAssertFalse(LLMPrompts.stateUpdater.isEmpty)
    }
    
    // MARK: - Network Request Tests (MockURLProtocol)
    
    func testQuickCompleteBuildsExpectedRequestBodyAndParsesResponse() async throws {
        let client = LLMClient(apiKey: "test-openrouter-key", model: "default-model")
        
        let responseJSON = """
        {
          "choices": [
            { "message": { "content": "START" } }
          ]
        }
        """
        
        func requestBodyData(_ request: URLRequest) throws -> Data {
            if let body = request.httpBody { return body }
            guard let stream = request.httpBodyStream else { return Data() }
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 16 * 1024
            var buffer = Array<UInt8>(repeating: 0, count: bufferSize)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: bufferSize)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }
            return data
        }
        
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("openrouter.ai/api/v1/chat/completions") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-openrouter-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            
            // Validate JSON body
            let bodyData = try requestBodyData(request)
            let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            XCTAssertEqual(json?["model"] as? String, "override-model")
            XCTAssertEqual(json?["max_tokens"] as? Int, 64)
            XCTAssertEqual(json?["temperature"] as? Double, 0.1)
            
            let messages = json?["messages"] as? [[String: Any]]
            XCTAssertEqual(messages?.count, 1)
            XCTAssertEqual(messages?.first?["role"] as? String, "user")
            XCTAssertNotNil(messages?.first?["content"] as? String)
            
            let data = responseJSON.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response)
        }
        
        let result = try await client.quickComplete(prompt: "Detect encounter start", modelOverride: "override-model")
        XCTAssertTrue(result.uppercased().contains("START"))
    }
    
    func testQuickComplete401ThrowsInvalidAPIKey() async {
        let client = LLMClient(apiKey: "bad-key", model: "default-model")
        
        MockURLProtocol.setupErrorResponse(statusCode: 401, message: "Invalid key")
        
        do {
            _ = try await client.quickComplete(prompt: "Test", modelOverride: nil)
            XCTFail("Expected error")
        } catch {
            guard case LLMProviderError.invalidAPIKey(provider: "OpenRouter") = error else {
                XCTFail("Expected invalidAPIKey(OpenRouter), got \(error)")
                return
            }
        }
    }
    
    func testQuickCompleteNon200ThrowsRequestFailed() async {
        let client = LLMClient(apiKey: "test-openrouter-key", model: "default-model")
        
        MockURLProtocol.setupErrorResponse(statusCode: 500, message: "Server error")
        
        do {
            _ = try await client.quickComplete(prompt: "Test", modelOverride: nil)
            XCTFail("Expected error")
        } catch {
            guard case LLMProviderError.requestFailed(provider: "OpenRouter", message: _) = error else {
                XCTFail("Expected requestFailed(OpenRouter), got \(error)")
                return
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func cleanJSONFromMarkdown(_ input: String) -> String {
        var cleaned = input
        if cleaned.contains("```json") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if cleaned.contains("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }
    
    private func safeParse<T: Decodable>(_ jsonString: String, as type: T.Type) -> T? {
        var cleanedJSON = jsonString
        if cleanedJSON.contains("```json") {
            cleanedJSON = cleanedJSON
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if cleanedJSON.contains("```") {
            cleanedJSON = cleanedJSON
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard let data = cleanedJSON.data(using: .utf8) else { return nil }
        
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }
}
