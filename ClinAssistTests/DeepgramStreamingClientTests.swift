import XCTest
@testable import ClinAssist

final class DeepgramStreamingClientTests: XCTestCase {
    
    var client: DeepgramStreamingClient!
    var mockWebSocket: MockWebSocketProvider!
    var mockDelegate: MockStreamingSTTClientDelegate!
    
    override func setUpWithError() throws {
        mockWebSocket = MockWebSocketProvider()
        mockDelegate = MockStreamingSTTClientDelegate()
        
        client = DeepgramStreamingClient(
            apiKey: "test-api-key",
            model: "nova-3-medical",
            language: "en",
            enableInterimResults: true,
            enableDiarization: true,
            webSocketProvider: mockWebSocket
        )
        client.delegate = mockDelegate
    }
    
    override func tearDownWithError() throws {
        client.disconnect()
        client = nil
        mockWebSocket = nil
        mockDelegate = nil
    }
    
    // MARK: - Connection Tests
    
    func testConnectCreatesWebSocketConnection() throws {
        try client.connect()
        
        XCTAssertTrue(mockWebSocket.connectCalled)
        XCTAssertNotNil(mockWebSocket.lastConnectURL)
        XCTAssertTrue(mockWebSocket.lastConnectURL!.absoluteString.contains("api.deepgram.com"))
        XCTAssertTrue(mockWebSocket.lastConnectURL!.absoluteString.contains("model=nova-3-medical"))
        XCTAssertTrue(mockWebSocket.lastConnectURL!.absoluteString.contains("diarize=true"))
        XCTAssertTrue(mockWebSocket.lastConnectURL!.absoluteString.contains("interim_results=true"))
    }
    
    func testConnectSetsAuthorizationHeader() throws {
        try client.connect()
        
        XCTAssertEqual(mockWebSocket.lastConnectHeaders?["Authorization"], "Token test-api-key")
    }
    
    func testConnectNotifiesDelegateOnSuccess() throws {
        try client.connect()
        
        // Wait for async callback
        let expectation = XCTestExpectation(description: "Connection state callback")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertTrue(mockDelegate.connectionStateChanges.contains(true))
        XCTAssertTrue(client.isConnected)
    }
    
    func testDisconnectClosesWebSocket() throws {
        try client.connect()
        client.disconnect()
        
        XCTAssertTrue(mockWebSocket.disconnectCalled)
        XCTAssertFalse(client.isConnected)
    }
    
    func testDisconnectSendsCloseStreamMessage() throws {
        try client.connect()
        client.disconnect()
        
        XCTAssertTrue(mockWebSocket.sentStrings.contains { $0.contains("CloseStream") })
    }
    
    // MARK: - Audio Streaming Tests
    
    func testSendAudioForwardsToWebSocket() throws {
        try client.connect()
        
        let samples: [Int16] = [100, 200, 300, -100, -200]
        client.sendAudio(samples)
        
        XCTAssertEqual(mockWebSocket.sentData.count, 1)
        XCTAssertEqual(mockWebSocket.sentData[0].count, samples.count * 2)  // 2 bytes per Int16
    }
    
    func testSendAudioDoesNotSendWhenDisconnected() throws {
        // Verify audio is NOT sent when disconnected
        let samples: [Int16] = [100, 200, 300]
        client.sendAudio(samples)
        
        // Should not be sent since we're not connected
        XCTAssertEqual(mockWebSocket.sentData.count, 0)
        XCTAssertFalse(client.isConnected)
    }
    
    // MARK: - Transcript Parsing Tests
    
    func testInterimResultNotifiesDelegate() throws {
        try client.connect()
        
        let interimJSON = MockWebSocketProvider.interimResultJSON(transcript: "Hello there", speaker: 0)
        mockWebSocket.simulateJSONMessage(interimJSON)
        
        // Wait for async processing
        let expectation = XCTestExpectation(description: "Interim result")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(mockDelegate.interimResults.count, 1)
        XCTAssertEqual(mockDelegate.interimResults[0].text, "Hello there")
        XCTAssertEqual(mockDelegate.interimResults[0].speaker, "Physician")
    }
    
    func testFinalResultNotifiesDelegate() throws {
        try client.connect()
        
        let finalJSON = MockWebSocketProvider.simpleFinalResultJSON(transcript: "How are you feeling today", speaker: 0)
        mockWebSocket.simulateJSONMessage(finalJSON)
        
        // Wait for async processing
        let expectation = XCTestExpectation(description: "Final result")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(mockDelegate.finalSegments.count, 1)
        XCTAssertEqual(mockDelegate.finalSegments[0].speaker, "Physician")
        XCTAssertTrue(mockDelegate.finalSegments[0].text.contains("How"))
    }
    
    func testDiarizationSeparatesSpeakers() throws {
        try client.connect()
        
        // Simulate a conversation with two speakers
        let words: [(String, Int)] = [
            ("Hello", 0),
            ("doctor", 0),
            ("Hi", 1),
            ("what", 1),
            ("brings", 1),
            ("you", 1),
            ("in", 1)
        ]
        let finalJSON = MockWebSocketProvider.finalResultJSON(words: words)
        mockWebSocket.simulateJSONMessage(finalJSON)
        
        // Wait for async processing
        let expectation = XCTestExpectation(description: "Diarized result")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Should produce two segments (speaker change)
        XCTAssertEqual(mockDelegate.finalSegments.count, 2)
        XCTAssertEqual(mockDelegate.finalSegments[0].speaker, "Physician")
        XCTAssertEqual(mockDelegate.finalSegments[0].text, "Hello doctor")
        XCTAssertEqual(mockDelegate.finalSegments[1].speaker, "Patient")
        XCTAssertTrue(mockDelegate.finalSegments[1].text.contains("Hi"))
    }
    
    func testSpeakerMapping() throws {
        try client.connect()
        
        // Test speaker 0 = Physician
        let json0 = MockWebSocketProvider.simpleFinalResultJSON(transcript: "Test", speaker: 0)
        mockWebSocket.simulateJSONMessage(json0)
        
        let expectation1 = XCTestExpectation(description: "Speaker 0")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expectation1.fulfill() }
        wait(for: [expectation1], timeout: 1.0)
        XCTAssertEqual(mockDelegate.finalSegments.last?.speaker, "Physician")
        
        // Test speaker 1 = Patient
        let json1 = MockWebSocketProvider.simpleFinalResultJSON(transcript: "Test", speaker: 1)
        mockWebSocket.simulateJSONMessage(json1)
        
        let expectation2 = XCTestExpectation(description: "Speaker 1")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expectation2.fulfill() }
        wait(for: [expectation2], timeout: 1.0)
        XCTAssertEqual(mockDelegate.finalSegments.last?.speaker, "Patient")
        
        // Test speaker 2+ = Other
        let json2 = MockWebSocketProvider.finalResultJSON(words: [("Test", 2)])
        mockWebSocket.simulateJSONMessage(json2)
        
        let expectation3 = XCTestExpectation(description: "Speaker 2")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expectation3.fulfill() }
        wait(for: [expectation3], timeout: 1.0)
        XCTAssertEqual(mockDelegate.finalSegments.last?.speaker, "Other")
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorMessageNotifiesDelegate() throws {
        try client.connect()
        
        let errorJSON = MockWebSocketProvider.errorJSON(message: "Rate limit exceeded")
        mockWebSocket.simulateJSONMessage(errorJSON)
        
        // Wait for async processing
        let expectation = XCTestExpectation(description: "Error handling")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(mockDelegate.errors.count, 1)
        XCTAssertTrue(mockDelegate.errors[0].localizedDescription.contains("Rate limit"))
    }
    
    func testWebSocketErrorNotifiesDelegate() throws {
        try client.connect()
        
        let error = NSError(domain: "Test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        mockWebSocket.simulateError(error)
        
        // Wait for async processing
        let expectation = XCTestExpectation(description: "WebSocket error")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(mockDelegate.errors.count, 1)
    }
    
    func testDisconnectNotifiesDelegate() throws {
        try client.connect()
        mockWebSocket.simulateDisconnect()
        
        // Wait for async processing
        let expectation = XCTestExpectation(description: "Disconnect")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertTrue(mockDelegate.connectionStateChanges.contains(false))
    }
    
    // MARK: - Metadata Handling Tests
    
    func testMetadataMessageIsIgnored() throws {
        try client.connect()
        
        let metadataJSON = MockWebSocketProvider.metadataJSON()
        mockWebSocket.simulateJSONMessage(metadataJSON)
        
        // Wait for async processing
        let expectation = XCTestExpectation(description: "Metadata")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Should not produce any transcript results
        XCTAssertEqual(mockDelegate.interimResults.count, 0)
        XCTAssertEqual(mockDelegate.finalSegments.count, 0)
    }
    
    // MARK: - Empty/Invalid Transcript Tests
    
    func testEmptyTranscriptIsIgnored() throws {
        try client.connect()
        
        let emptyJSON = """
        {
            "type": "Results",
            "is_final": true,
            "channel": {
                "alternatives": [{
                    "transcript": "",
                    "words": []
                }]
            }
        }
        """
        mockWebSocket.simulateJSONMessage(emptyJSON)
        
        // Wait for async processing
        let expectation = XCTestExpectation(description: "Empty transcript")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(mockDelegate.finalSegments.count, 0)
    }
    
    func testWhitespaceOnlyTranscriptIsIgnored() throws {
        try client.connect()
        
        let whitespaceJSON = """
        {
            "type": "Results",
            "is_final": true,
            "channel": {
                "alternatives": [{
                    "transcript": "   ",
                    "words": []
                }]
            }
        }
        """
        mockWebSocket.simulateJSONMessage(whitespaceJSON)
        
        // Wait for async processing
        let expectation = XCTestExpectation(description: "Whitespace transcript")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(mockDelegate.finalSegments.count, 0)
    }
}

// MARK: - Mock Delegate

class MockStreamingSTTClientDelegate: StreamingSTTClientDelegate {
    var interimResults: [(text: String, speaker: String)] = []
    var finalSegments: [TranscriptSegment] = []
    var connectionStateChanges: [Bool] = []
    var errors: [Error] = []
    
    func streamingClient(_ client: StreamingSTTClient, didReceiveInterim text: String, speaker: String) {
        interimResults.append((text: text, speaker: speaker))
    }
    
    func streamingClient(_ client: StreamingSTTClient, didReceiveFinal segment: TranscriptSegment) {
        finalSegments.append(segment)
    }
    
    func streamingClient(_ client: StreamingSTTClient, didChangeConnectionState connected: Bool) {
        connectionStateChanges.append(connected)
    }
    
    func streamingClient(_ client: StreamingSTTClient, didEncounterError error: Error) {
        errors.append(error)
    }
    
    func reset() {
        interimResults = []
        finalSegments = []
        connectionStateChanges = []
        errors = []
    }
}

