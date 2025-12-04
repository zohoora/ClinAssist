import Foundation
@testable import ClinAssist

/// Mock WebSocket provider for testing streaming transcription
class MockWebSocketProvider: WebSocketProvider {
    var onMessage: ((Result<WebSocketMessage, Error>) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: ((Error?) -> Void)?
    
    // Test state tracking
    var isConnected = false
    var connectCalled = false
    var disconnectCalled = false
    var sentData: [Data] = []
    var sentStrings: [String] = []
    var lastConnectURL: URL?
    var lastConnectHeaders: [String: String]?
    
    // Configurable behavior
    var shouldFailToConnect = false
    var connectionError: Error?
    var autoConnect = true  // Automatically call onConnected after connect()
    
    func connect(to url: URL, headers: [String: String]) {
        connectCalled = true
        lastConnectURL = url
        lastConnectHeaders = headers
        
        if shouldFailToConnect {
            let error = connectionError ?? NSError(domain: "MockWebSocket", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mock connection failed"])
            onDisconnected?(error)
            return
        }
        
        if autoConnect {
            isConnected = true
            onConnected?()
        }
    }
    
    func send(_ data: Data) {
        guard isConnected else { return }
        sentData.append(data)
    }
    
    func send(_ string: String) {
        guard isConnected else { return }
        sentStrings.append(string)
    }
    
    func disconnect() {
        disconnectCalled = true
        isConnected = false
        onDisconnected?(nil)
    }
    
    // MARK: - Test Helpers
    
    /// Simulates receiving a message from the server
    func simulateMessage(_ message: WebSocketMessage) {
        onMessage?(.success(message))
    }
    
    /// Simulates receiving a JSON string message
    func simulateJSONMessage(_ json: String) {
        onMessage?(.success(.string(json)))
    }
    
    /// Simulates a connection error
    func simulateError(_ error: Error) {
        onMessage?(.failure(error))
    }
    
    /// Simulates a disconnect
    func simulateDisconnect(error: Error? = nil) {
        isConnected = false
        onDisconnected?(error)
    }
    
    /// Simulates a successful connection (for manual connection testing)
    func simulateConnect() {
        isConnected = true
        onConnected?()
    }
    
    /// Resets all state for a fresh test
    func reset() {
        isConnected = false
        connectCalled = false
        disconnectCalled = false
        sentData = []
        sentStrings = []
        lastConnectURL = nil
        lastConnectHeaders = nil
        shouldFailToConnect = false
        connectionError = nil
        autoConnect = true
    }
}

// MARK: - Sample Deepgram Responses

extension MockWebSocketProvider {
    
    /// Creates a sample interim result JSON
    static func interimResultJSON(transcript: String, speaker: Int = 0) -> String {
        """
        {
            "type": "Results",
            "channel_index": [0, 1],
            "duration": 1.0,
            "start": 0.0,
            "is_final": false,
            "channel": {
                "alternatives": [{
                    "transcript": "\(transcript)",
                    "confidence": 0.95,
                    "words": [{
                        "word": "\(transcript)",
                        "start": 0.0,
                        "end": 1.0,
                        "confidence": 0.95,
                        "speaker": \(speaker)
                    }]
                }]
            }
        }
        """
    }
    
    /// Creates a sample final result JSON with diarization
    static func finalResultJSON(words: [(String, Int)]) -> String {
        let wordsJSON = words.enumerated().map { index, item in
            let (word, speaker) = item
            return """
            {
                "word": "\(word)",
                "start": \(Double(index) * 0.2),
                "end": \(Double(index + 1) * 0.2),
                "confidence": 0.98,
                "speaker": \(speaker)
            }
            """
        }.joined(separator: ",")
        
        let transcript = words.map { $0.0 }.joined(separator: " ")
        
        return """
        {
            "type": "Results",
            "channel_index": [0, 1],
            "duration": \(Double(words.count) * 0.2),
            "start": 0.0,
            "is_final": true,
            "channel": {
                "alternatives": [{
                    "transcript": "\(transcript)",
                    "confidence": 0.98,
                    "words": [\(wordsJSON)]
                }]
            }
        }
        """
    }
    
    /// Creates a simple final result JSON
    static func simpleFinalResultJSON(transcript: String, speaker: Int = 0) -> String {
        return finalResultJSON(words: transcript.split(separator: " ").map { (String($0), speaker) })
    }
    
    /// Creates an error message JSON
    static func errorJSON(message: String) -> String {
        """
        {
            "type": "Error",
            "message": "\(message)"
        }
        """
    }
    
    /// Creates a metadata message JSON
    static func metadataJSON() -> String {
        """
        {
            "type": "Metadata",
            "transaction_key": "test-key",
            "request_id": "test-request-id",
            "sha256": "test-sha256",
            "created": "2024-01-01T00:00:00.000Z",
            "duration": 0.0,
            "channels": 1
        }
        """
    }
}

