import XCTest
@testable import ClinAssist

@MainActor
final class EncounterControllerTests: XCTestCase {
    
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
    
    // MARK: - Encounter Lifecycle Tests
    
    func testStartEncounterCreatesState() {
        XCTAssertNil(controller.state)
        
        controller.startEncounter()
        
        XCTAssertNotNil(controller.state)
        XCTAssertNotNil(controller.state?.startedAt)
        XCTAssertNil(controller.state?.endedAt)
        XCTAssertTrue(controller.state?.transcript.isEmpty ?? false)
    }
    
    func testStartEncounterStartsRecording() {
        controller.startEncounter()
        
        XCTAssertTrue(mockAudioManager.isRecording || mockAudioManager.transitionToRecordingCalled || mockAudioManager.startRecordingCalled)
    }
    
    func testStartEncounterConnectsStreamingClient() {
        controller.startEncounter()
        
        XCTAssertTrue(mockStreamingClient.connectCalled)
    }
    
    func testEndEncounterSetsEndedAt() async {
        controller.startEncounter()
        XCTAssertNil(controller.state?.endedAt)
        
        await controller.endEncounter()
        
        XCTAssertNotNil(controller.state?.endedAt)
    }
    
    func testEndEncounterDisconnectsStreamingClient() async {
        controller.startEncounter()
        
        await controller.endEncounter()
        
        XCTAssertTrue(mockStreamingClient.disconnectCalled)
    }
    
    func testEndEncounterStopsRecording() async {
        controller.startEncounter()
        
        await controller.endEncounter()
        
        XCTAssertTrue(mockAudioManager.stopRecordingCalled || mockAudioManager.transitionToMonitoringCalled)
    }
    
    func testPauseEncounterPausesRecording() {
        controller.startEncounter()
        
        controller.pauseEncounter()
        
        XCTAssertTrue(mockAudioManager.pauseRecordingCalled)
    }
    
    func testResumeEncounterResumesRecording() {
        controller.startEncounter()
        controller.pauseEncounter()
        
        controller.resumeEncounter()
        
        XCTAssertTrue(mockAudioManager.resumeRecordingCalled)
    }
    
    // MARK: - Transcript Accumulation Tests (Streaming)
    
    func testStreamingFinalTranscriptAddsToState() {
        controller.startEncounter()
        
        let segment = TranscriptSegment(speaker: "Physician", text: "How are you feeling today?")
        mockStreamingClient.simulateFinalTranscript(segment)
        
        // Wait for main thread update
        let expectation = XCTestExpectation(description: "Transcript added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(controller.state?.transcript.count, 1)
        XCTAssertEqual(controller.state?.transcript.first?.speaker, "Physician")
        XCTAssertEqual(controller.state?.transcript.first?.text, "How are you feeling today?")
    }
    
    func testStreamingInterimTranscriptUpdatesInterimState() {
        controller.startEncounter()
        
        mockStreamingClient.simulateInterimTranscript("How are", speaker: "Physician")
        
        // Wait for main thread update
        let expectation = XCTestExpectation(description: "Interim updated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(controller.interimTranscript, "How are")
        XCTAssertEqual(controller.interimSpeaker, "Physician")
    }
    
    func testMultipleFinalTranscriptsAccumulate() {
        controller.startEncounter()
        
        let segment1 = TranscriptSegment(speaker: "Physician", text: "Hello")
        let segment2 = TranscriptSegment(speaker: "Patient", text: "Hi doctor")
        let segment3 = TranscriptSegment(speaker: "Physician", text: "How can I help you?")
        
        mockStreamingClient.simulateFinalTranscript(segment1)
        mockStreamingClient.simulateFinalTranscript(segment2)
        mockStreamingClient.simulateFinalTranscript(segment3)
        
        // Wait for updates
        let expectation = XCTestExpectation(description: "All transcripts added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(controller.state?.transcript.count, 3)
    }
    
    // MARK: - Transcript Accumulation Tests (REST Fallback)
    
    func testRESTFallbackWhenStreamingDisabled() async {
        // Setup with streaming disabled
        mockConfigManager = MockConfigManager.withoutStreaming()
        controller = EncounterController(
            audioManager: mockAudioManager,
            configManager: mockConfigManager,
            sttClient: mockSTTClient,
            streamingClient: nil,
            llmClient: mockLLMClient,
            ollamaClient: nil
        )
        
        // Setup mock response
        mockSTTClient.setupSuccess(segments: [
            TranscriptSegment(speaker: "Physician", text: "Hello patient")
        ])
        
        controller.startEncounter()
        
        // Simulate chunk saved
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_chunk.wav")
        try? Data().write(to: tempURL)
        mockAudioManager.simulateChunkSaved(at: tempURL, chunkNumber: 1)
        
        // Wait for async transcription
        let expectation = XCTestExpectation(description: "REST transcription")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertTrue(mockSTTClient.transcribeCalled)
    }
    
    // MARK: - SOAP Generation Tests
    
    func testSOAPGenerationWithPopulatedTranscript() async {
        controller.startEncounter()
        
        // Add transcript entries
        let segment1 = TranscriptSegment(speaker: "Physician", text: "What brings you in today?")
        let segment2 = TranscriptSegment(speaker: "Patient", text: "I have a headache")
        mockStreamingClient.simulateFinalTranscript(segment1)
        mockStreamingClient.simulateFinalTranscript(segment2)
        
        // Wait for transcripts to be added
        let transcriptExpectation = XCTestExpectation(description: "Transcripts added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            transcriptExpectation.fulfill()
        }
        wait(for: [transcriptExpectation], timeout: 1.0)
        
        // Setup mock LLM response
        mockLLMClient.setupSuccess(response: "# SOAP Note\n\n## Subjective\nPatient reports headache...")
        
        // End encounter triggers SOAP generation
        await controller.endEncounter()
        
        // Wait for SOAP generation
        let soapExpectation = XCTestExpectation(description: "SOAP generated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            soapExpectation.fulfill()
        }
        wait(for: [soapExpectation], timeout: 2.0)
        
        XCTAssertTrue(mockLLMClient.completeCalled)
    }
    
    func testSOAPGenerationSkippedWithEmptyTranscript() async {
        controller.startEncounter()
        
        // Don't add any transcripts
        
        await controller.endEncounter()
        
        // Wait for potential SOAP generation
        let expectation = XCTestExpectation(description: "SOAP check")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        
        // SOAP should not be generated with empty transcript
        XCTAssertFalse(mockLLMClient.completeCalled)
    }
    
    // MARK: - Connection State Tests
    
    func testStreamingConnectionStateUpdates() {
        controller.startEncounter()
        
        mockStreamingClient.simulateConnectionState(connected: true)
        
        let expectation = XCTestExpectation(description: "Connection state")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertTrue(controller.isStreamingConnected)
    }
    
    func testStreamingDisconnectTriggersState() {
        controller.startEncounter()
        
        mockStreamingClient.simulateConnectionState(connected: true)
        
        let connectExpectation = XCTestExpectation(description: "Connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            connectExpectation.fulfill()
        }
        wait(for: [connectExpectation], timeout: 1.0)
        
        mockStreamingClient.simulateConnectionState(connected: false)
        
        let disconnectExpectation = XCTestExpectation(description: "Disconnected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            disconnectExpectation.fulfill()
        }
        wait(for: [disconnectExpectation], timeout: 1.0)
        
        XCTAssertFalse(controller.isStreamingConnected)
    }
    
    // MARK: - Error Handling Tests
    
    func testStreamingErrorUpdatesState() {
        controller.startEncounter()
        
        let error = NSError(domain: "Test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        mockStreamingClient.simulateError(error)
        
        let expectation = XCTestExpectation(description: "Error state")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertNotNil(controller.transcriptionError)
    }
    
    // MARK: - Clinical Notes Tests
    
    func testAddClinicalNote() {
        controller.startEncounter()
        
        controller.addClinicalNote("BP 120/80")
        
        XCTAssertEqual(controller.state?.clinicalNotes.count, 1)
        XCTAssertEqual(controller.state?.clinicalNotes.first?.text, "BP 120/80")
    }
    
    func testAddEmptyClinicalNoteIgnored() {
        controller.startEncounter()
        
        controller.addClinicalNote("")
        controller.addClinicalNote("   ")
        
        XCTAssertEqual(controller.state?.clinicalNotes.count, 0)
    }
    
    // MARK: - Audio Sample Forwarding Tests
    
    func testAudioSamplesForwardedToStreamingClient() {
        controller.startEncounter()
        
        let samples: [Int16] = [100, 200, 300, -100, -200]
        mockAudioManager.simulateAudioSamples(samples)
        
        XCTAssertTrue(mockStreamingClient.sendAudioCalled)
        XCTAssertEqual(mockStreamingClient.lastSentSamples, samples)
    }
}
