import Foundation
import AVFoundation
@testable import ClinAssist

/// Mock AudioManager for testing without actual audio hardware
@MainActor
class MockAudioManager: AudioManager {
    
    // MARK: - Test State Tracking
    
    var startRecordingCalled = false
    var stopRecordingCalled = false
    var startMonitoringCalled = false
    var stopMonitoringCalled = false
    var pauseRecordingCalled = false
    var resumeRecordingCalled = false
    var transitionToRecordingCalled = false
    var transitionToMonitoringCalled = false
    
    var lastEncounterId: UUID?
    
    // MARK: - Configurable Behavior
    
    var shouldFailStartRecording = false
    var shouldFailStartMonitoring = false
    var simulatedPermissionGranted = true
    
    // MARK: - Simulation Methods
    
    private var capturedDelegate: AudioManagerDelegate? {
        return delegate
    }
    
    /// Simulates audio samples being captured (for streaming mode)
    func simulateAudioSamples(_ samples: [Int16]) {
        delegate?.audioManager(self, didCaptureAudioSamples: samples)
    }
    
    /// Simulates a chunk being saved (for backup/REST mode)
    func simulateChunkSaved(at url: URL, chunkNumber: Int) {
        delegate?.audioManager(self, didSaveChunk: url, chunkNumber: chunkNumber)
    }
    
    /// Simulates an audio level update
    func simulateAudioLevel(_ level: Float) {
        currentAudioLevel = level
        delegate?.audioManager(self, didUpdateAudioLevel: level)
    }
    
    /// Simulates an error
    func simulateError(_ error: Error) {
        delegate?.audioManager(self, didEncounterError: error)
    }
    
    // MARK: - Override Methods
    
    override func checkPermissions() {
        permissionGranted = simulatedPermissionGranted
        permissionError = simulatedPermissionGranted ? nil : "Mock permission denied"
    }
    
    override func startRecording(encounterId: UUID) throws {
        startRecordingCalled = true
        lastEncounterId = encounterId
        
        if shouldFailStartRecording {
            throw AudioError.recordingFailed
        }
        
        if !simulatedPermissionGranted {
            throw AudioError.permissionDenied
        }
        
        mode = .recording
        isRecording = true
        isMonitoring = false
    }
    
    override func stopRecording() {
        stopRecordingCalled = true
        mode = .idle
        isRecording = false
    }
    
    override func startMonitoring() throws {
        startMonitoringCalled = true
        
        if shouldFailStartMonitoring {
            throw AudioError.engineSetupFailed
        }
        
        if !simulatedPermissionGranted {
            throw AudioError.permissionDenied
        }
        
        mode = .monitoring
        isMonitoring = true
        isRecording = false
    }
    
    override func stopMonitoring() {
        stopMonitoringCalled = true
        mode = .idle
        isMonitoring = false
    }
    
    override func pauseRecording() {
        pauseRecordingCalled = true
    }
    
    override func resumeRecording() {
        resumeRecordingCalled = true
    }
    
    override func transitionToRecording(encounterId: UUID) throws {
        transitionToRecordingCalled = true
        lastEncounterId = encounterId
        
        if shouldFailStartRecording {
            throw AudioError.recordingFailed
        }
        
        mode = .recording
        isRecording = true
        isMonitoring = false
    }
    
    override func transitionToMonitoring() throws {
        transitionToMonitoringCalled = true
        
        if shouldFailStartMonitoring {
            throw AudioError.engineSetupFailed
        }
        
        mode = .monitoring
        isMonitoring = true
        isRecording = false
    }
    
    // MARK: - Reset
    
    func reset() {
        startRecordingCalled = false
        stopRecordingCalled = false
        startMonitoringCalled = false
        stopMonitoringCalled = false
        pauseRecordingCalled = false
        resumeRecordingCalled = false
        transitionToRecordingCalled = false
        transitionToMonitoringCalled = false
        lastEncounterId = nil
        shouldFailStartRecording = false
        shouldFailStartMonitoring = false
        simulatedPermissionGranted = true
        mode = .idle
        isRecording = false
        isMonitoring = false
        currentAudioLevel = 0
    }
}
