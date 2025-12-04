import Foundation
@testable import ClinAssist

/// Mock STT Client for testing REST transcription
class MockSTTClient: STTClient {
    
    // MARK: - Test State Tracking
    
    var transcribeCalled = false
    var transcribeCallCount = 0
    var lastAudioData: Data?
    
    // MARK: - Configurable Behavior
    
    var transcribeResult: [TranscriptSegment] = []
    var shouldFail = false
    var errorToThrow: Error = NSError(domain: "MockSTTClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mock transcription failed"])
    var delaySeconds: TimeInterval = 0
    
    // MARK: - STTClient Protocol
    
    func transcribe(audioData: Data) async throws -> [TranscriptSegment] {
        transcribeCalled = true
        transcribeCallCount += 1
        lastAudioData = audioData
        
        if delaySeconds > 0 {
            try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        }
        
        if shouldFail {
            throw errorToThrow
        }
        
        return transcribeResult
    }
    
    // MARK: - Convenience Methods
    
    /// Sets up a successful transcription result
    func setupSuccess(segments: [TranscriptSegment]) {
        shouldFail = false
        transcribeResult = segments
    }
    
    /// Sets up a successful transcription with simple text
    func setupSuccess(text: String, speaker: String = "Physician") {
        shouldFail = false
        transcribeResult = [TranscriptSegment(speaker: speaker, text: text)]
    }
    
    /// Sets up a failure response
    func setupFailure(error: Error? = nil) {
        shouldFail = true
        if let error = error {
            errorToThrow = error
        }
    }
    
    // MARK: - Reset
    
    func reset() {
        transcribeCalled = false
        transcribeCallCount = 0
        lastAudioData = nil
        transcribeResult = []
        shouldFail = false
        delaySeconds = 0
    }
}

// MARK: - STT Errors for Testing

enum MockSTTError: LocalizedError {
    case networkError
    case invalidApiKey
    case rateLimited
    case emptyAudio
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network connection failed"
        case .invalidApiKey:
            return "Invalid API key"
        case .rateLimited:
            return "Rate limit exceeded"
        case .emptyAudio:
            return "Audio data is empty"
        case .timeout:
            return "Request timed out"
        }
    }
}
