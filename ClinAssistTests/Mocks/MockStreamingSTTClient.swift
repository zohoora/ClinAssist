import Foundation
@testable import ClinAssist

/// Mock streaming STT client for testing without network
class MockStreamingSTTClient: StreamingSTTClient {
    weak var delegate: StreamingSTTClientDelegate?
    
    // State tracking
    var _isConnected = false
    var isConnected: Bool { _isConnected }
    
    var connectCalled = false
    var disconnectCalled = false
    var sendAudioCalled = false
    var sentAudioSamples: [[Int16]] = []
    var lastSentSamples: [Int16]?
    
    // Configurable behavior
    var shouldFailToConnect = false
    var connectError: Error = StreamingSTTError.connectionFailed("Mock connection failed")
    
    // Simulated responses
    var autoRespond = false
    var autoRespondDelay: TimeInterval = 0.1
    var autoRespondTranscript: String = "Mock transcript"
    var autoRespondSpeaker: String = "Physician"
    
    func connect() throws {
        connectCalled = true
        
        if shouldFailToConnect {
            throw connectError
        }
        
        _isConnected = true
        delegate?.streamingClient(self, didChangeConnectionState: true)
    }
    
    func disconnect() {
        disconnectCalled = true
        _isConnected = false
        delegate?.streamingClient(self, didChangeConnectionState: false)
    }
    
    func sendAudio(_ samples: [Int16]) {
        sendAudioCalled = true
        lastSentSamples = samples
        sentAudioSamples.append(samples)
        
        guard _isConnected else { return }
        
        // Auto-respond if configured
        if autoRespond {
            DispatchQueue.main.asyncAfter(deadline: .now() + autoRespondDelay) { [weak self] in
                guard let self = self else { return }
                // Simulate interim first
                self.delegate?.streamingClient(self, didReceiveInterim: self.autoRespondTranscript, speaker: self.autoRespondSpeaker)
                
                // Then final after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self = self else { return }
                    let segment = TranscriptSegment(speaker: self.autoRespondSpeaker, text: self.autoRespondTranscript)
                    self.delegate?.streamingClient(self, didReceiveFinal: segment)
                }
            }
        }
    }
    
    // MARK: - Test Helpers
    
    /// Simulates receiving an interim result
    func simulateInterimResult(text: String, speaker: String = "Physician") {
        delegate?.streamingClient(self, didReceiveInterim: text, speaker: speaker)
    }
    
    /// Simulates receiving an interim transcript (alias)
    func simulateInterimTranscript(_ text: String, speaker: String) {
        delegate?.streamingClient(self, didReceiveInterim: text, speaker: speaker)
    }
    
    /// Simulates receiving a final result
    func simulateFinalResult(text: String, speaker: String = "Physician") {
        let segment = TranscriptSegment(speaker: speaker, text: text)
        delegate?.streamingClient(self, didReceiveFinal: segment)
    }
    
    /// Simulates receiving a final transcript segment
    func simulateFinalTranscript(_ segment: TranscriptSegment) {
        delegate?.streamingClient(self, didReceiveFinal: segment)
    }
    
    /// Simulates an error
    func simulateError(_ error: Error) {
        delegate?.streamingClient(self, didEncounterError: error)
    }
    
    /// Simulates connection state change
    func simulateConnectionState(connected: Bool) {
        _isConnected = connected
        delegate?.streamingClient(self, didChangeConnectionState: connected)
    }
    
    /// Simulates a disconnect
    func simulateDisconnect() {
        _isConnected = false
        delegate?.streamingClient(self, didChangeConnectionState: false)
    }
    
    /// Simulates a reconnection
    func simulateReconnect() {
        _isConnected = true
        delegate?.streamingClient(self, didChangeConnectionState: true)
    }
    
    /// Resets all state
    func reset() {
        _isConnected = false
        connectCalled = false
        disconnectCalled = false
        sendAudioCalled = false
        sentAudioSamples = []
        lastSentSamples = nil
        shouldFailToConnect = false
        autoRespond = false
    }
    
    /// Returns total number of audio samples sent
    var totalSamplesSent: Int {
        sentAudioSamples.reduce(0) { $0 + $1.count }
    }
}

// MARK: - Preconfigured Mocks

extension MockStreamingSTTClient {
    /// Creates a mock that auto-responds with transcript
    static func withAutoResponse(transcript: String = "Hello, how are you?", speaker: String = "Patient") -> MockStreamingSTTClient {
        let mock = MockStreamingSTTClient()
        mock.autoRespond = true
        mock.autoRespondTranscript = transcript
        mock.autoRespondSpeaker = speaker
        return mock
    }
    
    /// Creates a mock that fails to connect
    static func failing(with error: StreamingSTTError = .connectionFailed("Test failure")) -> MockStreamingSTTClient {
        let mock = MockStreamingSTTClient()
        mock.shouldFailToConnect = true
        mock.connectError = error
        return mock
    }
    
    /// Creates a mock that simulates a medical conversation
    static func withMedicalConversation() -> MockStreamingSTTClient {
        let mock = MockStreamingSTTClient()
        
        // Will need manual triggering of responses
        return mock
    }
}

