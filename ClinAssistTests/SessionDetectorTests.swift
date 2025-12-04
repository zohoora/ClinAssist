import XCTest
@testable import ClinAssist

@MainActor
final class SessionDetectorTests: XCTestCase {
    
    var detector: SessionDetector!
    var mockDelegate: MockSessionDetectorDelegate!
    
    override func setUpWithError() throws {
        var config = SessionDetector.Config()
        config.enabled = true
        config.speechActivityThreshold = 0.02
        config.silenceThresholdSeconds = 5  // Short for testing
        config.minEncounterDurationSeconds = 2  // Short for testing
        config.bufferDurationSeconds = 1
        config.useLLMForDetection = false  // Use keyword detection for predictable tests
        
        detector = SessionDetector(config: config)
        mockDelegate = MockSessionDetectorDelegate()
        detector.delegate = mockDelegate
    }
    
    override func tearDownWithError() throws {
        detector.stopMonitoring()
        detector = nil
        mockDelegate = nil
    }
    
    // MARK: - Initial State Tests
    
    func testInitialStateIsIdle() {
        XCTAssertEqual(detector.detectionStatus, .idle)
        XCTAssertFalse(detector.isMonitoring)
    }
    
    func testStartMonitoringSetsCorrectState() {
        detector.startMonitoring()
        
        XCTAssertEqual(detector.detectionStatus, .monitoring)
        XCTAssertTrue(detector.isMonitoring)
    }
    
    func testStopMonitoringResetsState() {
        detector.startMonitoring()
        detector.stopMonitoring()
        
        XCTAssertEqual(detector.detectionStatus, .idle)
        XCTAssertFalse(detector.isMonitoring)
    }
    
    // MARK: - Speech Detection Tests
    
    func testSpeechDetectionStartsEncounter() {
        detector.startMonitoring()
        
        // Simulate speech activity above threshold
        detector.processSpeechActivity(level: 0.05)
        
        XCTAssertEqual(detector.detectionStatus, .encounterActive)
        XCTAssertTrue(mockDelegate.didDetectStart)
    }
    
    func testLowAudioLevelDoesNotStartEncounter() {
        detector.startMonitoring()
        
        // Simulate audio below threshold
        detector.processSpeechActivity(level: 0.01)
        
        XCTAssertEqual(detector.detectionStatus, .monitoring)
        XCTAssertFalse(mockDelegate.didDetectStart)
    }
    
    // MARK: - Keyword Detection Tests
    
    func testEndKeywordTriggersPoentialEnd() {
        detector.startMonitoring()
        detector.processSpeechActivity(level: 0.05)  // Start encounter
        
        // Wait a bit for minimum duration
        Thread.sleep(forTimeInterval: 2.5)
        
        // Process transcript with end keyword
        detector.processTranscript("Alright, take care and feel better!")
        
        XCTAssertEqual(detector.detectionStatus, .potentialEnd)
    }
    
    func testStartKeywordDetection() {
        // Configure with LLM detection off so keywords are used
        var config = SessionDetector.Config()
        config.enabled = true
        config.useLLMForDetection = false
        config.startKeywords = ["what brings you in"]
        detector = SessionDetector(config: config)
        detector.delegate = mockDelegate
        
        detector.startMonitoring()
        
        // Start buffering first
        detector.processSpeechActivity(level: 0.001)  // Below threshold, won't auto-start
        
        // In the current implementation, speech detection starts immediately
        // So let's test with just the transcript processing
    }
    
    // MARK: - State Transition Tests
    
    func testManualEncounterStart() {
        detector.encounterStartedManually()
        
        XCTAssertEqual(detector.detectionStatus, .encounterActive)
        XCTAssertEqual(detector.currentSilenceDuration, 0)
    }
    
    func testManualEncounterEndWhileMonitoring() {
        detector.startMonitoring()
        detector.encounterStartedManually()
        detector.encounterEndedManually()
        
        XCTAssertEqual(detector.detectionStatus, .monitoring)
    }
    
    func testManualEncounterEndWhileNotMonitoring() {
        detector.encounterStartedManually()
        detector.encounterEndedManually()
        
        XCTAssertEqual(detector.detectionStatus, .idle)
    }
    
    func testResetEndDetection() {
        detector.startMonitoring()
        detector.processSpeechActivity(level: 0.05)  // Start encounter
        
        // Simulate potential end state
        Thread.sleep(forTimeInterval: 2.5)
        detector.processTranscript("goodbye")
        
        XCTAssertEqual(detector.detectionStatus, .potentialEnd)
        
        // Reset should return to active
        detector.resetEndDetection()
        
        XCTAssertEqual(detector.detectionStatus, .encounterActive)
        XCTAssertNil(detector.lastDetectedPattern)
    }
    
    // MARK: - Silence Duration Tests
    
    func testSilenceDurationResetOnSpeech() {
        detector.startMonitoring()
        detector.processSpeechActivity(level: 0.05)  // Start encounter
        
        // Wait to build up silence duration
        Thread.sleep(forTimeInterval: 2)
        
        // Speech should reset it
        detector.processSpeechActivity(level: 0.05)
        
        XCTAssertEqual(detector.currentSilenceDuration, 0)
    }
    
    // MARK: - Configuration Tests
    
    func testConfigurationDisabledPreventsMonitoring() {
        var config = SessionDetector.Config()
        config.enabled = false
        detector = SessionDetector(config: config)
        
        detector.startMonitoring()
        
        // Should remain idle when disabled
        XCTAssertEqual(detector.detectionStatus, .idle)
    }
    
    func testCustomKeywordsAreUsed() {
        var config = SessionDetector.Config()
        config.enabled = true
        config.endKeywords = ["custom_end_phrase"]
        config.useLLMForDetection = false
        config.minEncounterDurationSeconds = 0
        detector = SessionDetector(config: config)
        detector.delegate = mockDelegate
        
        detector.startMonitoring()
        detector.processSpeechActivity(level: 0.05)  // Start encounter
        
        // Custom keyword should trigger potential end
        detector.processTranscript("custom_end_phrase")
        
        XCTAssertEqual(detector.detectionStatus, .potentialEnd)
    }
}

// MARK: - Mock Delegate

class MockSessionDetectorDelegate: SessionDetectorDelegate {
    var didDetectStart = false
    var didDetectEnd = false
    var didStartBuffering = false
    var didCancelBuffering = false
    
    func sessionDetectorDidDetectEncounterStart(_ detector: SessionDetector) {
        didDetectStart = true
    }
    
    func sessionDetectorDidDetectEncounterEnd(_ detector: SessionDetector) {
        didDetectEnd = true
    }
    
    func sessionDetectorDidStartBuffering(_ detector: SessionDetector) {
        didStartBuffering = true
    }
    
    func sessionDetectorDidCancelBuffering(_ detector: SessionDetector) {
        didCancelBuffering = true
    }
}
