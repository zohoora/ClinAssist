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
    
    func testRESTFallbackConfiguration() {
        // Test that controller is properly configured for REST mode
        mockConfigManager = MockConfigManager.withoutStreaming()
        
        let restController = EncounterController(
            audioManager: mockAudioManager,
            configManager: mockConfigManager,
            sttClient: mockSTTClient,
            streamingClient: nil,  // No streaming client = REST mode
            llmClient: mockLLMClient,
            ollamaClient: nil
        )
        
        restController.startEncounter()
        
        // Verify state is created
        XCTAssertNotNil(restController.state, "Encounter state should be created")
        XCTAssertTrue(restController.state?.transcript.isEmpty ?? false, "Transcript should start empty")
        
        // Verify no streaming client is connected
        XCTAssertFalse(restController.isStreamingConnected, "Streaming should not be connected in REST mode")
    }
    
    // MARK: - SOAP Generation Tests
    
    func testSOAPGenerationWithPopulatedTranscript() async {
        // Setup mock LLM response BEFORE starting encounter
        mockLLMClient.setupSuccess(response: "# SOAP Note\n\n## Subjective\nPatient reports headache...")
        
        controller.startEncounter()
        
        // Add transcript entries directly to state (simulating what streaming would do)
        let entry1 = TranscriptEntry(timestamp: Date(), speaker: "Physician", text: "What brings you in today?")
        let entry2 = TranscriptEntry(timestamp: Date(), speaker: "Patient", text: "I have a headache")
        controller.state?.transcript.append(entry1)
        controller.state?.transcript.append(entry2)
        
        // Verify transcripts were added
        XCTAssertEqual(controller.state?.transcript.count, 2, "Expected 2 transcript entries")
        
        // End encounter triggers SOAP generation
        await controller.endEncounter()
        
        // Verify LLM was called (orchestrator should use our mock)
        XCTAssertTrue(mockLLMClient.completeCalled, "Expected LLM complete() to be called for SOAP generation")
        XCTAssertNotNil(mockLLMClient.lastSystemPrompt, "Expected system prompt to be set")
        XCTAssertNotNil(mockLLMClient.lastUserContent, "Expected user content to be set")
    }
    
    func testSOAPGenerationSkippedWithEmptyTranscript() async {
        controller.startEncounter()
        
        // Don't add any transcripts - verify state is empty
        XCTAssertEqual(controller.state?.transcript.count ?? 0, 0, "Transcript should be empty")
        
        await controller.endEncounter()
        
        // SOAP should not be generated with empty transcript
        XCTAssertFalse(mockLLMClient.completeCalled, "LLM should NOT be called for empty transcript")
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
    
    // MARK: - Encounter Attachments Tests
    
    func testAddEncounterAttachment() {
        controller.startEncounter()
        
        let attachment = EncounterAttachment(
            name: "test_image.png",
            type: .image,
            base64Data: "base64encodeddata",
            mimeType: "image/png"
        )
        
        controller.addEncounterAttachment(attachment)
        
        XCTAssertEqual(controller.encounterAttachments.count, 1)
        XCTAssertEqual(controller.encounterAttachments.first?.name, "test_image.png")
        XCTAssertEqual(controller.encounterAttachments.first?.type, .image)
    }
    
    func testEncounterAttachmentsResetOnStart() {
        controller.startEncounter()
        
        let attachment = EncounterAttachment(
            name: "test.pdf",
            type: .pdf,
            base64Data: "pdfdata",
            mimeType: "application/pdf"
        )
        controller.addEncounterAttachment(attachment)
        
        XCTAssertEqual(controller.encounterAttachments.count, 1)
        
        // Start a new encounter - attachments should be reset
        controller.startEncounter()
        
        XCTAssertEqual(controller.encounterAttachments.count, 0)
    }
    
    func testHasMultimodalAttachmentsWithImage() {
        controller.startEncounter()
        
        let imageAttachment = EncounterAttachment(
            name: "photo.jpg",
            type: .image,
            base64Data: "imagedata",
            mimeType: "image/jpeg"
        )
        
        controller.addEncounterAttachment(imageAttachment)
        
        XCTAssertTrue(controller.hasMultimodalAttachments)
    }
    
    func testHasMultimodalAttachmentsWithPDF() {
        controller.startEncounter()
        
        let pdfAttachment = EncounterAttachment(
            name: "report.pdf",
            type: .pdf,
            base64Data: "pdfdata",
            mimeType: "application/pdf"
        )
        
        controller.addEncounterAttachment(pdfAttachment)
        
        XCTAssertTrue(controller.hasMultimodalAttachments)
    }
    
    func testHasMultimodalAttachmentsWithTextOnly() {
        controller.startEncounter()
        
        let textAttachment = EncounterAttachment(
            name: "notes.txt",
            type: .textFile,
            textContent: "Some text content"
        )
        
        controller.addEncounterAttachment(textAttachment)
        
        XCTAssertFalse(controller.hasMultimodalAttachments)
    }
    
    func testMultipleAttachmentTypes() {
        controller.startEncounter()
        
        let textAttachment = EncounterAttachment(
            name: "notes.txt",
            type: .textFile,
            textContent: "Some text"
        )
        
        let imageAttachment = EncounterAttachment(
            name: "photo.png",
            type: .image,
            base64Data: "imagedata",
            mimeType: "image/png"
        )
        
        let pdfAttachment = EncounterAttachment(
            name: "report.pdf",
            type: .pdf,
            base64Data: "pdfdata",
            mimeType: "application/pdf"
        )
        
        controller.addEncounterAttachment(textAttachment)
        controller.addEncounterAttachment(imageAttachment)
        controller.addEncounterAttachment(pdfAttachment)
        
        XCTAssertEqual(controller.encounterAttachments.count, 3)
        XCTAssertTrue(controller.hasMultimodalAttachments)
    }
}
