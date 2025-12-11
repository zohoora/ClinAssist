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
        // LLM client is required for monitoring
        detector.setLLMClient(MockOllamaClient())
        detector.startMonitoring()
        
        XCTAssertEqual(detector.detectionStatus, .monitoring)
        XCTAssertTrue(detector.isMonitoring)
    }
    
    func testStopMonitoringResetsState() {
        // LLM client is required for monitoring
        detector.setLLMClient(MockOllamaClient())
        detector.startMonitoring()
        detector.stopMonitoring()
        
        XCTAssertEqual(detector.detectionStatus, .idle)
        XCTAssertFalse(detector.isMonitoring)
    }
    
    // MARK: - Auto-Detection Requires LLM Tests
    
    func testMonitoringRequiresLLM() {
        // Without LLM, monitoring should not start
        detector.startMonitoring()
        
        XCTAssertEqual(detector.detectionStatus, .idle)
        XCTAssertFalse(detector.isMonitoring)
    }
    
    func testSpeechDetectionStartsBufferingWithLLM() {
        // Set up mock LLM client
        detector.setLLMClient(MockOllamaClient())
        detector.startMonitoring()
        
        XCTAssertEqual(detector.detectionStatus, .monitoring)
        
        // Simulate speech activity above threshold
        detector.processSpeechActivity(level: 0.05)
        
        // Should start buffering for LLM analysis, not immediately start encounter
        XCTAssertEqual(detector.detectionStatus, .buffering)
        XCTAssertTrue(mockDelegate.didStartBuffering)
    }
    
    func testLowAudioLevelDoesNotStartBuffering() {
        detector.setLLMClient(MockOllamaClient())
        detector.startMonitoring()
        
        // Simulate audio below threshold
        detector.processSpeechActivity(level: 0.01)
        
        XCTAssertEqual(detector.detectionStatus, .monitoring)
        XCTAssertFalse(mockDelegate.didStartBuffering)
    }
    
    // MARK: - State Transition Tests
    
    func testManualEncounterStart() {
        detector.encounterStartedManually()
        
        XCTAssertEqual(detector.detectionStatus, .encounterActive)
        XCTAssertEqual(detector.currentSilenceDuration, 0)
    }
    
    func testManualEncounterEndWhileMonitoring() {
        detector.setLLMClient(MockOllamaClient())
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
        // Start encounter manually and set to potential end
        detector.encounterStartedManually()
        
        XCTAssertEqual(detector.detectionStatus, .encounterActive)
        
        // Reset should work from encounterActive (no-op) or potentialEnd
        detector.resetEndDetection()
        
        XCTAssertEqual(detector.detectionStatus, .encounterActive)
        XCTAssertNil(detector.lastDetectedPattern)
    }
    
    // MARK: - Silence Duration Tests
    
    func testSilenceDurationResetOnSpeech() {
        detector.setLLMClient(MockOllamaClient())
        detector.startMonitoring()
        detector.encounterStartedManually()
        
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
        detector.setLLMClient(MockOllamaClient())
        
        detector.startMonitoring()
        
        // Should remain idle when disabled
        XCTAssertEqual(detector.detectionStatus, .idle)
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
