import XCTest
import AVFoundation
@testable import ClinAssist

final class AudioManagerTests: XCTestCase {
    
    var audioManager: AudioManager!
    var mockDelegate: MockAudioManagerDelegate!
    
    override func setUpWithError() throws {
        audioManager = AudioManager()
        mockDelegate = MockAudioManagerDelegate()
        audioManager.delegate = mockDelegate
        
        // Enable streaming by default
        audioManager.streamingEnabled = true
        audioManager.saveAudioBackup = true
    }
    
    override func tearDownWithError() throws {
        audioManager.stopRecording()
        audioManager.stopMonitoring()
        audioManager = nil
        mockDelegate = nil
    }
    
    // MARK: - Initial State Tests
    
    func testInitialStateIsIdle() {
        XCTAssertEqual(audioManager.mode, .idle)
        XCTAssertFalse(audioManager.isRecording)
        XCTAssertFalse(audioManager.isMonitoring)
    }
    
    func testInitialAudioLevelIsZero() {
        XCTAssertEqual(audioManager.currentAudioLevel, 0)
    }
    
    // MARK: - Mode Transition Tests
    
    func testStartMonitoringSetsMode() throws {
        // Skip if no permission (CI environment)
        guard audioManager.permissionGranted else {
            throw XCTSkip("Microphone permission not granted")
        }
        
        try audioManager.startMonitoring()
        
        XCTAssertEqual(audioManager.mode, .monitoring)
        XCTAssertTrue(audioManager.isMonitoring)
        XCTAssertFalse(audioManager.isRecording)
    }
    
    func testStopMonitoringSetsIdleMode() throws {
        guard audioManager.permissionGranted else {
            throw XCTSkip("Microphone permission not granted")
        }
        
        try audioManager.startMonitoring()
        audioManager.stopMonitoring()
        
        XCTAssertEqual(audioManager.mode, .idle)
        XCTAssertFalse(audioManager.isMonitoring)
    }
    
    func testStartRecordingSetsMode() throws {
        guard audioManager.permissionGranted else {
            throw XCTSkip("Microphone permission not granted")
        }
        
        let encounterId = UUID()
        try audioManager.startRecording(encounterId: encounterId)
        
        XCTAssertEqual(audioManager.mode, .recording)
        XCTAssertTrue(audioManager.isRecording)
        XCTAssertFalse(audioManager.isMonitoring)
    }
    
    func testStopRecordingSetsIdleMode() throws {
        guard audioManager.permissionGranted else {
            throw XCTSkip("Microphone permission not granted")
        }
        
        let encounterId = UUID()
        try audioManager.startRecording(encounterId: encounterId)
        audioManager.stopRecording()
        
        XCTAssertEqual(audioManager.mode, .idle)
        XCTAssertFalse(audioManager.isRecording)
    }
    
    func testTransitionFromMonitoringToRecording() throws {
        guard audioManager.permissionGranted else {
            throw XCTSkip("Microphone permission not granted")
        }
        
        try audioManager.startMonitoring()
        XCTAssertEqual(audioManager.mode, .monitoring)
        
        let encounterId = UUID()
        try audioManager.transitionToRecording(encounterId: encounterId)
        
        XCTAssertEqual(audioManager.mode, .recording)
        XCTAssertTrue(audioManager.isRecording)
        XCTAssertFalse(audioManager.isMonitoring)
    }
    
    func testTransitionFromRecordingToMonitoring() throws {
        guard audioManager.permissionGranted else {
            throw XCTSkip("Microphone permission not granted")
        }
        
        let encounterId = UUID()
        try audioManager.startRecording(encounterId: encounterId)
        XCTAssertEqual(audioManager.mode, .recording)
        
        try audioManager.transitionToMonitoring()
        
        XCTAssertEqual(audioManager.mode, .monitoring)
        XCTAssertFalse(audioManager.isRecording)
        XCTAssertTrue(audioManager.isMonitoring)
    }
    
    // MARK: - Streaming Configuration Tests
    
    func testStreamingEnabledProperty() {
        audioManager.streamingEnabled = true
        XCTAssertTrue(audioManager.streamingEnabled)
        
        audioManager.streamingEnabled = false
        XCTAssertFalse(audioManager.streamingEnabled)
    }
    
    func testSaveAudioBackupProperty() {
        audioManager.saveAudioBackup = true
        XCTAssertTrue(audioManager.saveAudioBackup)
        
        audioManager.saveAudioBackup = false
        XCTAssertFalse(audioManager.saveAudioBackup)
    }
    
    // MARK: - Permission Tests
    
    func testPermissionErrorWhenDenied() {
        // This test verifies the error handling path
        // Note: We can't actually deny permission in tests, so we test the error type
        XCTAssertNotNil(AudioError.permissionDenied.errorDescription)
        XCTAssertTrue(AudioError.permissionDenied.errorDescription?.contains("Microphone") ?? false)
    }
    
    // MARK: - Pause/Resume Tests
    
    func testPauseAndResumeRecording() throws {
        guard audioManager.permissionGranted else {
            throw XCTSkip("Microphone permission not granted")
        }
        
        let encounterId = UUID()
        try audioManager.startRecording(encounterId: encounterId)
        
        // Pause should not change mode
        audioManager.pauseRecording()
        XCTAssertEqual(audioManager.mode, .recording)
        
        // Resume should not change mode
        audioManager.resumeRecording()
        XCTAssertEqual(audioManager.mode, .recording)
    }
    
    // MARK: - Error Type Tests
    
    func testAudioErrorDescriptions() {
        XCTAssertNotNil(AudioError.permissionDenied.errorDescription)
        XCTAssertNotNil(AudioError.engineSetupFailed.errorDescription)
        XCTAssertNotNil(AudioError.formatError.errorDescription)
        XCTAssertNotNil(AudioError.recordingFailed.errorDescription)
    }
    
    // MARK: - Mode Enum Tests
    
    func testModeEnumValues() {
        let idle: AudioManager.Mode = .idle
        let monitoring: AudioManager.Mode = .monitoring
        let recording: AudioManager.Mode = .recording
        
        XCTAssertNotEqual(idle, monitoring)
        XCTAssertNotEqual(monitoring, recording)
        XCTAssertNotEqual(idle, recording)
    }
}

// MARK: - Mock Audio Manager Delegate

class MockAudioManagerDelegate: AudioManagerDelegate {
    var savedChunks: [(url: URL, number: Int)] = []
    var errors: [Error] = []
    var audioLevels: [Float] = []
    var capturedSamples: [[Int16]] = []
    
    func audioManager(_ manager: AudioManager, didSaveChunk chunkURL: URL, chunkNumber: Int) {
        savedChunks.append((chunkURL, chunkNumber))
    }
    
    func audioManager(_ manager: AudioManager, didEncounterError error: Error) {
        errors.append(error)
    }
    
    func audioManager(_ manager: AudioManager, didUpdateAudioLevel level: Float) {
        audioLevels.append(level)
    }
    
    func audioManager(_ manager: AudioManager, didCaptureAudioSamples samples: [Int16]) {
        capturedSamples.append(samples)
    }
    
    func reset() {
        savedChunks = []
        errors = []
        audioLevels = []
        capturedSamples = []
    }
}
