import XCTest
@testable import ClinAssist

@MainActor
final class GroqClientTests: XCTestCase {
    
    override func setUpWithError() throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        MockURLProtocol.reset()
    }
    
    override func tearDownWithError() throws {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.reset()
    }
    
    func testQuickCompleteBuildsExpectedRequestBodyAndParsesResponse() async throws {
        let client = GroqClient(apiKey: "test-groq-key", model: "openai/gpt-oss-20b")
        
        let responseJSON = """
        {
          "choices": [
            { "message": { "content": "CONTINUE" } }
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
            XCTAssertTrue(request.url?.absoluteString.contains("api.groq.com/openai/v1/chat/completions") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-groq-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            
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
        
        let result = try await client.quickComplete(prompt: "Detect encounter end", modelOverride: "override-model")
        XCTAssertTrue(result.uppercased().contains("CONTINUE"))
    }
    
    func testQuickComplete401ThrowsInvalidAPIKey() async {
        let client = GroqClient(apiKey: "bad-key", model: "openai/gpt-oss-20b")
        MockURLProtocol.setupErrorResponse(statusCode: 401, message: "Invalid key")
        
        do {
            _ = try await client.quickComplete(prompt: "Test", modelOverride: nil)
            XCTFail("Expected error")
        } catch {
            guard case LLMProviderError.invalidAPIKey(provider: "Groq") = error else {
                XCTFail("Expected invalidAPIKey(Groq), got \(error)")
                return
            }
        }
    }
    
    func testQuickComplete429ThrowsRateLimited() async {
        let client = GroqClient(apiKey: "test-groq-key", model: "openai/gpt-oss-20b")
        MockURLProtocol.setupErrorResponse(statusCode: 429, message: "Rate limit exceeded")
        
        do {
            _ = try await client.quickComplete(prompt: "Test", modelOverride: nil)
            XCTFail("Expected error")
        } catch {
            guard case LLMProviderError.rateLimited(provider: "Groq", message: _) = error else {
                XCTFail("Expected rateLimited(Groq), got \(error)")
                return
            }
        }
    }
    
    func testQuickCompleteNon200ThrowsRequestFailed() async {
        let client = GroqClient(apiKey: "test-groq-key", model: "openai/gpt-oss-20b")
        MockURLProtocol.setupErrorResponse(statusCode: 500, message: "Server error")
        
        do {
            _ = try await client.quickComplete(prompt: "Test", modelOverride: nil)
            XCTFail("Expected error")
        } catch {
            guard case LLMProviderError.requestFailed(provider: "Groq", message: _) = error else {
                XCTFail("Expected requestFailed(Groq), got \(error)")
                return
            }
        }
    }
}

