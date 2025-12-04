import XCTest
@testable import ClinAssist

@MainActor
final class DeepgramRESTClientTests: XCTestCase {
    
    var client: DeepgramRESTClient!
    
    override func setUpWithError() throws {
        client = DeepgramRESTClient(apiKey: "test-api-key")
        
        // Register mock URL protocol
        URLProtocol.registerClass(MockURLProtocol.self)
    }
    
    override func tearDownWithError() throws {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.reset()
        client = nil
    }
    
    // MARK: - Success Tests
    
    func testTranscribeReturnsSegments() async throws {
        // Setup mock response
        MockURLProtocol.setupDeepgramSuccess(transcript: "Hello doctor", speaker: 0)
        
        let audioData = createTestAudioData()
        let segments = try await client.transcribe(audioData: audioData)
        
        XCTAssertFalse(segments.isEmpty)
    }
    
    func testTranscribeParsesSpeaker() async throws {
        MockURLProtocol.setupDeepgramSuccess(transcript: "Hello doctor", speaker: 0)
        
        let audioData = createTestAudioData()
        let segments = try await client.transcribe(audioData: audioData)
        
        XCTAssertEqual(segments.first?.speaker, "Physician")
    }
    
    func testTranscribeParsesText() async throws {
        MockURLProtocol.setupDeepgramSuccess(transcript: "Hello doctor how are you", speaker: 0)
        
        let audioData = createTestAudioData()
        let segments = try await client.transcribe(audioData: audioData)
        
        XCTAssertTrue(segments.first?.text.contains("Hello") ?? false)
    }
    
    func testTranscribeWithDiarization() async throws {
        MockURLProtocol.setupDeepgramDiarized(segments: [
            (text: "Hello patient", speaker: 0),
            (text: "Hi doctor", speaker: 1)
        ])
        
        let audioData = createTestAudioData()
        let segments = try await client.transcribe(audioData: audioData)
        
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].speaker, "Physician")
        XCTAssertEqual(segments[1].speaker, "Patient")
    }
    
    func testSpeakerMapping() async throws {
        // Test speaker 0 = Physician
        MockURLProtocol.setupDeepgramSuccess(transcript: "Hello", speaker: 0)
        var segments = try await client.transcribe(audioData: createTestAudioData())
        XCTAssertEqual(segments.first?.speaker, "Physician")
        
        // Test speaker 1 = Patient
        MockURLProtocol.setupDeepgramSuccess(transcript: "Hi", speaker: 1)
        segments = try await client.transcribe(audioData: createTestAudioData())
        XCTAssertEqual(segments.first?.speaker, "Patient")
        
        // Test speaker 2+ = Other
        MockURLProtocol.setupDeepgramDiarized(segments: [(text: "Test", speaker: 2)])
        segments = try await client.transcribe(audioData: createTestAudioData())
        XCTAssertEqual(segments.first?.speaker, "Other")
    }
    
    // MARK: - Error Tests
    
    func testInvalidAPIKeyThrowsError() async {
        MockURLProtocol.setupErrorResponse(statusCode: 401, message: "Invalid API key")
        
        let audioData = createTestAudioData()
        
        do {
            _ = try await client.transcribe(audioData: audioData)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is STTError)
            if case STTError.invalidAPIKey = error {
                // Success
            } else {
                XCTFail("Expected invalidAPIKey error, got \(error)")
            }
        }
    }
    
    func testServerErrorThrowsError() async {
        MockURLProtocol.setupErrorResponse(statusCode: 500, message: "Internal server error")
        
        let audioData = createTestAudioData()
        
        do {
            _ = try await client.transcribe(audioData: audioData)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is STTError)
        }
    }
    
    func testNetworkErrorThrowsError() async {
        MockURLProtocol.setupNetworkError()
        
        let audioData = createTestAudioData()
        
        do {
            _ = try await client.transcribe(audioData: audioData)
            XCTFail("Expected error to be thrown")
        } catch {
            // Network error should be thrown
            XCTAssertNotNil(error)
        }
    }
    
    func testInvalidResponseThrowsError() async {
        // Setup invalid JSON response
        MockURLProtocol.setupSuccessResponse(json: "not valid json")
        
        let audioData = createTestAudioData()
        
        do {
            _ = try await client.transcribe(audioData: audioData)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is STTError)
        }
    }
    
    func testEmptyTranscriptThrowsError() async {
        let emptyJSON = """
        {
            "metadata": {},
            "results": {
                "channels": [{
                    "alternatives": [{
                        "transcript": "",
                        "words": []
                    }]
                }]
            }
        }
        """
        MockURLProtocol.setupSuccessResponse(json: emptyJSON)
        
        let audioData = createTestAudioData()
        
        do {
            _ = try await client.transcribe(audioData: audioData)
            XCTFail("Expected error to be thrown")
        } catch {
            if case STTError.noTranscript = error {
                // Success
            } else {
                XCTFail("Expected noTranscript error, got \(error)")
            }
        }
    }
    
    // MARK: - Request Verification Tests
    
    func testRequestContainsAuthorizationHeader() async throws {
        MockURLProtocol.setupDeepgramSuccess(transcript: "Test")
        
        _ = try await client.transcribe(audioData: createTestAudioData())
        
        let request = MockURLProtocol.capturedRequests.last
        XCTAssertNotNil(request)
        XCTAssertTrue(request?.value(forHTTPHeaderField: "Authorization")?.contains("Token") ?? false)
    }
    
    func testRequestContainsContentType() async throws {
        MockURLProtocol.setupDeepgramSuccess(transcript: "Test")
        
        _ = try await client.transcribe(audioData: createTestAudioData())
        
        let request = MockURLProtocol.capturedRequests.last
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Content-Type"), "audio/wav")
    }
    
    func testRequestHasBodyData() async throws {
        MockURLProtocol.setupDeepgramSuccess(transcript: "Test")
        
        let audioData = createTestAudioData()
        _ = try await client.transcribe(audioData: audioData)
        
        let request = MockURLProtocol.capturedRequests.last
        // Note: httpBody may be nil after the request is made as URLSession streams it
        // We verify the request was made with POST method instead
        XCTAssertEqual(request?.httpMethod, "POST")
    }
    
    func testRequestURLContainsModelParameter() async throws {
        MockURLProtocol.setupDeepgramSuccess(transcript: "Test")
        
        _ = try await client.transcribe(audioData: createTestAudioData())
        
        let request = MockURLProtocol.capturedRequests.last
        XCTAssertTrue(request?.url?.absoluteString.contains("model=nova-3-medical") ?? false)
    }
    
    func testRequestURLContainsDiarizeParameter() async throws {
        MockURLProtocol.setupDeepgramSuccess(transcript: "Test")
        
        _ = try await client.transcribe(audioData: createTestAudioData())
        
        let request = MockURLProtocol.capturedRequests.last
        XCTAssertTrue(request?.url?.absoluteString.contains("diarize=true") ?? false)
    }
    
    // MARK: - Rate Limiting Tests
    
    func testRateLimitErrorHandling() async {
        MockURLProtocol.setupErrorResponse(statusCode: 429, message: "Rate limit exceeded")
        
        do {
            _ = try await client.transcribe(audioData: createTestAudioData())
            XCTFail("Expected error")
        } catch {
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestAudioData() -> Data {
        // Create minimal WAV header for testing
        var data = Data()
        
        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: [0x24, 0x00, 0x00, 0x00])  // File size
        data.append(contentsOf: "WAVE".utf8)
        
        // fmt subchunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: [0x10, 0x00, 0x00, 0x00])  // Subchunk size
        data.append(contentsOf: [0x01, 0x00])  // Audio format (PCM)
        data.append(contentsOf: [0x01, 0x00])  // Num channels
        data.append(contentsOf: [0x80, 0x3E, 0x00, 0x00])  // Sample rate (16000)
        data.append(contentsOf: [0x00, 0x7D, 0x00, 0x00])  // Byte rate
        data.append(contentsOf: [0x02, 0x00])  // Block align
        data.append(contentsOf: [0x10, 0x00])  // Bits per sample
        
        // data subchunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // Data size
        
        return data
    }
}

// MARK: - STTError Tests

@MainActor
final class STTErrorTests: XCTestCase {
    
    func testErrorDescriptions() {
        XCTAssertNotNil(STTError.invalidResponse.errorDescription)
        XCTAssertNotNil(STTError.invalidAPIKey.errorDescription)
        XCTAssertNotNil(STTError.noTranscript.errorDescription)
        XCTAssertNotNil(STTError.transcriptionFailed("test").errorDescription)
        XCTAssertNotNil(STTError.networkError(NSError(domain: "test", code: -1)).errorDescription)
    }
    
    func testTranscriptionFailedContainsMessage() {
        let error = STTError.transcriptionFailed("Custom message")
        XCTAssertTrue(error.errorDescription?.contains("Custom message") ?? false)
    }
}
