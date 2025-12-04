import XCTest
@testable import ClinAssist

@MainActor
final class LLMClientTests: XCTestCase {
    
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
