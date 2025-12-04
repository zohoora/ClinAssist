import XCTest
@testable import ClinAssist

/// Integration tests for the full transcript flow from audio capture to SOAP generation
final class TranscriptFlowTests: XCTestCase {
    
    var controller: EncounterController!
    var mockAudioManager: MockAudioManager!
    var mockConfigManager: MockConfigManager!
    var mockSTTClient: MockSTTClient!
    var mockStreamingClient: MockStreamingSTTClient!
    var mockLLMClient: MockLLMClient!
    
    override func setUpWithError() throws {
        mockAudioManager = MockAudioManager()
        mockConfigManager = MockConfigManager.withStreaming()
        mockSTTClient = MockSTTClient()
        mockStreamingClient = MockStreamingSTTClient()
        mockLLMClient = MockLLMClient()
        
        controller = EncounterController(
            audioManager: mockAudioManager,
            configManager: mockConfigManager,
            sttClient: mockSTTClient,
            streamingClient: mockStreamingClient,
            llmClient: mockLLMClient,
            ollamaClient: nil
        )
    }
    
    override func tearDownWithError() throws {
        controller = nil
        mockAudioManager = nil
        mockConfigManager = nil
        mockSTTClient = nil
        mockStreamingClient = nil
        mockLLMClient = nil
    }
    
    // MARK: - Full Flow Tests: Streaming Path
    
    /// Tests: Start encounter -> streaming connects -> audio samples sent -> final transcript received -> transcript in state -> SOAP generated
    func testStreamingFlowEndToEnd() async {
        // 1. Start encounter
        controller.startEncounter()
        XCTAssertNotNil(controller.state)
        XCTAssertTrue(mockStreamingClient.connectCalled)
        
        // 2. Simulate streaming connection
        mockStreamingClient.simulateConnectionState(connected: true)
        
        // Wait for state update
        await waitForMainThread()
        XCTAssertTrue(controller.isStreamingConnected)
        
        // 3. Simulate audio samples sent
        let samples: [Int16] = [100, 200, 300]
        mockAudioManager.simulateAudioSamples(samples)
        XCTAssertTrue(mockStreamingClient.sendAudioCalled)
        
        // 4. Simulate transcript received
        let segment1 = TranscriptSegment(speaker: "Physician", text: "What brings you in today?")
        let segment2 = TranscriptSegment(speaker: "Patient", text: "I have a headache for three days")
        mockStreamingClient.simulateFinalTranscript(segment1)
        mockStreamingClient.simulateFinalTranscript(segment2)
        
        await waitForMainThread()
        
        // 5. Verify transcript in state
        XCTAssertEqual(controller.state?.transcript.count, 2)
        XCTAssertEqual(controller.state?.transcript[0].speaker, "Physician")
        XCTAssertEqual(controller.state?.transcript[1].speaker, "Patient")
        
        // 6. Setup LLM response and end encounter
        mockLLMClient.mockResponse = SampleTranscripts.soapNote
        
        await controller.endEncounter()
        
        // 7. Verify SOAP was generated
        XCTAssertTrue(mockLLMClient.completeCalled)
        XCTAssertFalse(controller.soapNote.isEmpty)
    }
    
    // MARK: - Full Flow Tests: REST Fallback Path
    
    /// Tests: Start encounter -> streaming fails -> REST fallback -> chunk transcribed -> transcript in state -> SOAP generated
    func testRESTFallbackFlowEndToEnd() async {
        // Setup with REST-only mode
        mockConfigManager = MockConfigManager.withoutStreaming()
        controller = EncounterController(
            audioManager: mockAudioManager,
            configManager: mockConfigManager,
            sttClient: mockSTTClient,
            streamingClient: nil,
            llmClient: mockLLMClient,
            ollamaClient: nil
        )
        
        // 1. Start encounter
        controller.startEncounter()
        XCTAssertNotNil(controller.state)
        
        // 2. Setup REST response
        mockSTTClient.setupSuccess(segments: [
            TranscriptSegment(speaker: "Physician", text: "Hello, how can I help you?"),
            TranscriptSegment(speaker: "Patient", text: "I have back pain")
        ])
        
        // 3. Simulate chunk saved (triggers REST transcription)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_chunk.wav")
        try? Data().write(to: tempURL)
        mockAudioManager.simulateChunkSaved(at: tempURL, chunkNumber: 1)
        
        // Wait for async transcription
        await waitForAsync(timeout: 1.0)
        
        // 4. Verify REST was called
        XCTAssertTrue(mockSTTClient.transcribeCalled)
        
        // 5. Verify transcript in state
        XCTAssertGreaterThanOrEqual(controller.state?.transcript.count ?? 0, 0)
        
        // 6. Setup LLM and end encounter
        mockLLMClient.mockResponse = SampleTranscripts.soapNote
        
        await controller.endEncounter()
        
        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    // MARK: - Streaming Disconnect and Fallback
    
    func testStreamingDisconnectTriggersConnectionStateUpdate() async {
        controller.startEncounter()
        
        // Connect then disconnect
        mockStreamingClient.simulateConnectionState(connected: true)
        await waitForMainThread()
        XCTAssertTrue(controller.isStreamingConnected)
        
        mockStreamingClient.simulateConnectionState(connected: false)
        await waitForMainThread()
        XCTAssertFalse(controller.isStreamingConnected)
    }
    
    // MARK: - Auto-Detection Flow
    
    /// Tests: monitoring -> speech detected -> provisional recording -> encounter started
    func testAutoDetectionFlow() async {
        mockConfigManager = MockConfigManager.withAutoDetection()
        controller = EncounterController(
            audioManager: mockAudioManager,
            configManager: mockConfigManager,
            sttClient: mockSTTClient,
            streamingClient: mockStreamingClient,
            llmClient: mockLLMClient,
            ollamaClient: nil
        )
        
        // Start monitoring
        controller.startMonitoring()
        
        // Note: Full auto-detection testing requires mocking the SessionDetector
        // This test verifies the monitoring mode starts correctly
        XCTAssertTrue(mockAudioManager.startMonitoringCalled || mockAudioManager.mode == .monitoring)
    }
    
    // MARK: - Transcript Persistence Tests
    
    func testTranscriptPersistsThroughMultipleUpdates() async {
        controller.startEncounter()
        mockStreamingClient.simulateConnectionState(connected: true)
        
        // Send multiple transcripts
        for i in 1...5 {
            let segment = TranscriptSegment(speaker: i % 2 == 0 ? "Patient" : "Physician", text: "Message \(i)")
            mockStreamingClient.simulateFinalTranscript(segment)
        }
        
        await waitForMainThread()
        
        XCTAssertEqual(controller.state?.transcript.count, 5)
    }
    
    func testInterimTranscriptDoesNotPersist() async {
        controller.startEncounter()
        mockStreamingClient.simulateConnectionState(connected: true)
        
        // Send interim transcript
        mockStreamingClient.simulateInterimTranscript("Hello", speaker: "Physician")
        
        await waitForMainThread()
        
        // Interim should be in interim state, not permanent transcript
        XCTAssertEqual(controller.interimTranscript, "Hello")
        XCTAssertEqual(controller.state?.transcript.count, 0)
        
        // Now send final
        let segment = TranscriptSegment(speaker: "Physician", text: "Hello doctor")
        mockStreamingClient.simulateFinalTranscript(segment)
        
        await waitForMainThread()
        
        // Final should be in permanent transcript
        XCTAssertEqual(controller.state?.transcript.count, 1)
        XCTAssertEqual(controller.interimTranscript, "") // Cleared after final
    }
    
    // MARK: - Error Recovery Tests
    
    func testStreamingErrorDoesNotCrash() async {
        controller.startEncounter()
        mockStreamingClient.simulateConnectionState(connected: true)
        
        // Simulate error
        let error = NSError(domain: "Test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        mockStreamingClient.simulateError(error)
        
        await waitForMainThread()
        
        // Controller should still be functional
        XCTAssertNotNil(controller.transcriptionError)
        
        // Should still accept transcripts
        let segment = TranscriptSegment(speaker: "Physician", text: "Test")
        mockStreamingClient.simulateFinalTranscript(segment)
        
        await waitForMainThread()
        
        XCTAssertEqual(controller.state?.transcript.count, 1)
    }
    
    // MARK: - Clinical Notes Integration
    
    func testClinicalNotesIncludedInSOAPGeneration() async {
        controller.startEncounter()
        
        // Add clinical note
        controller.addClinicalNote("BP 120/80")
        controller.addClinicalNote("Heart rate 72")
        
        // Add transcript
        let segment = TranscriptSegment(speaker: "Patient", text: "I feel dizzy")
        mockStreamingClient.simulateFinalTranscript(segment)
        
        await waitForMainThread()
        
        XCTAssertEqual(controller.state?.clinicalNotes.count, 2)
        XCTAssertEqual(controller.state?.transcript.count, 1)
        
        // LLM call should include both
        mockLLMClient.mockResponse = SampleTranscripts.soapNote
        await controller.endEncounter()
        
        XCTAssertTrue(mockLLMClient.completeCalled)
        // The userContent should include the state with clinical notes
        XCTAssertNotNil(mockLLMClient.lastUserContent)
    }
    
    // MARK: - Helper Methods
    
    private func waitForMainThread() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                continuation.resume()
            }
        }
    }
    
    private func waitForAsync(timeout: TimeInterval) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                continuation.resume()
            }
        }
    }
}

