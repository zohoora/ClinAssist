import Foundation

/// Protocol for streaming STT clients (separate from batch STTClient)
protocol StreamingSTTClient: AnyObject {
    var delegate: StreamingSTTClientDelegate? { get set }
    
    func connect() throws
    func disconnect()
    func sendAudio(_ samples: [Int16])
    var isConnected: Bool { get }
}

/// Delegate for receiving streaming transcription results
@MainActor
protocol StreamingSTTClientDelegate: AnyObject {
    /// Called when an interim (non-final) transcript is received - may change
    func streamingClient(_ client: StreamingSTTClient, didReceiveInterim text: String, speaker: String)
    
    /// Called when a final transcript segment is received - will not change
    func streamingClient(_ client: StreamingSTTClient, didReceiveFinal segment: TranscriptSegment)
    
    /// Called when connection state changes
    func streamingClient(_ client: StreamingSTTClient, didChangeConnectionState connected: Bool)
    
    /// Called when an error occurs
    func streamingClient(_ client: StreamingSTTClient, didEncounterError error: Error)
}

/// Deepgram WebSocket streaming client for real-time transcription
class DeepgramStreamingClient: StreamingSTTClient {
    weak var delegate: StreamingSTTClientDelegate?
    
    private let apiKey: String
    private let webSocketProvider: WebSocketProvider
    private var _isConnected = false
    
    // Configuration
    private let model: String
    private let language: String
    private let enableInterimResults: Bool
    private let enableDiarization: Bool
    
    // Reconnection - high limit for long sessions (hours)
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 100  // Support sessions up to several hours
    private var reconnectTimer: Timer?
    private var shouldReconnect = false
    
    // Keep-alive to prevent Deepgram timeout
    private var keepAliveTimer: Timer?
    private let keepAliveInterval: TimeInterval = 30  // Send keep-alive every 30 seconds
    
    // Audio buffer for reconnection recovery
    private var pendingAudioBuffer: [[Int16]] = []
    private let maxPendingBufferSize = 50  // ~2.5 seconds at 16kHz with 800 samples/chunk
    
    var isConnected: Bool {
        return _isConnected
    }
    
    init(
        apiKey: String,
        model: String = "nova-3-medical",
        language: String = "en",
        enableInterimResults: Bool = true,
        enableDiarization: Bool = true,
        webSocketProvider: WebSocketProvider = URLSessionWebSocketProvider()
    ) {
        self.apiKey = apiKey
        self.model = model
        self.language = language
        self.enableInterimResults = enableInterimResults
        self.enableDiarization = enableDiarization
        self.webSocketProvider = webSocketProvider
        
        setupWebSocketCallbacks()
    }
    
    private func setupWebSocketCallbacks() {
        webSocketProvider.onConnected = { [weak self] in
            guard let self = self else { return }
            
            self._isConnected = true
            self.reconnectAttempts = 0
            self.shouldReconnect = true
            
            debugLog("✅ Connected to Deepgram WebSocket!", component: "Streaming")
            
            // Start keep-alive timer to prevent timeout
            self.startKeepAliveTimer()
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.streamingClient(self, didChangeConnectionState: true)
            }
            
            // Flush any pending audio
            self.flushPendingAudio()
        }
        
        webSocketProvider.onDisconnected = { [weak self] error in
            guard let self = self else { return }
            
            self._isConnected = false
            
            debugLog("❌ Disconnected: \(error?.localizedDescription ?? "clean disconnect")", component: "Streaming")
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.streamingClient(self, didChangeConnectionState: false)
            }
            
            // Attempt reconnection if appropriate
            if self.shouldReconnect {
                self.attemptReconnect()
            }
        }
        
        webSocketProvider.onMessage = { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let jsonString):
                    self.handleMessage(jsonString)
                case .data(let data):
                    if let jsonString = String(data: data, encoding: .utf8) {
                        self.handleMessage(jsonString)
                    }
                }
                
            case .failure(let error):
                debugLog("❌ Message error: \(error.localizedDescription)", component: "Streaming")
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.streamingClient(self, didEncounterError: error)
                }
            }
        }
    }
    
    // MARK: - Connection Management
    
    func connect() throws {
        guard !_isConnected else {
            debugLog("⚠️ Already connected, skipping connect()", component: "Streaming")
            return
        }
        
        debugLog("🔌 connect() called - starting WebSocket connection...", component: "Streaming")
        
        // Build WebSocket URL with query parameters
        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        components.queryItems = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1")
        ]
        
        if enableDiarization {
            components.queryItems?.append(URLQueryItem(name: "diarize", value: "true"))
        }
        
        if enableInterimResults {
            components.queryItems?.append(URLQueryItem(name: "interim_results", value: "true"))
        }
        
        guard let url = components.url else {
            throw StreamingSTTError.invalidConfiguration
        }
        
        let headers = [
            "Authorization": "Token \(apiKey)"
        ]
        
        shouldReconnect = true
        pendingAudioBuffer = []
        
        debugLog("🌐 Connecting to: \(url.absoluteString.prefix(80))...", component: "Streaming")
        webSocketProvider.connect(to: url, headers: headers)
    }
    
    func disconnect() {
        shouldReconnect = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        stopKeepAliveTimer()
        
        if _isConnected {
            // Send close stream message for graceful shutdown
            webSocketProvider.send("{\"type\": \"CloseStream\"}")
        }
        
        webSocketProvider.disconnect()
        _isConnected = false
        pendingAudioBuffer = []
        
        debugLog("🔌 Disconnected (intentional)", component: "Streaming")
    }
    
    private func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            debugLog("❌ Max reconnect attempts (\(maxReconnectAttempts)) reached - giving up", component: "Streaming")
            let error = StreamingSTTError.connectionFailed("Max reconnection attempts exceeded")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.streamingClient(self, didEncounterError: error)
            }
            return
        }
        
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 10.0)  // Exponential backoff, max 10s
        
        debugLog("🔄 Reconnecting \(reconnectAttempts)/\(maxReconnectAttempts) in \(String(format: "%.1f", delay))s...", component: "Streaming")
        
        // Use DispatchQueue instead of Timer for reliability
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.shouldReconnect else {
                debugLog("⏹️ Reconnect cancelled (shouldReconnect=false)", component: "Streaming")
                return
            }
            
            debugLog("🔌 Executing reconnect attempt \(self.reconnectAttempts)...", component: "Streaming")
            do {
                try self.connect()
            } catch {
                debugLog("❌ Reconnect failed: \(error.localizedDescription)", component: "Streaming")
                // Try again
                self.attemptReconnect()
            }
        }
    }
    
    // MARK: - Keep-Alive
    
    private func startKeepAliveTimer() {
        stopKeepAliveTimer()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.keepAliveTimer = Timer.scheduledTimer(withTimeInterval: self.keepAliveInterval, repeats: true) { [weak self] _ in
                self?.sendKeepAlive()
            }
            
            debugLog("💓 Keep-alive timer started (every \(Int(self.keepAliveInterval))s)", component: "Streaming")
        }
    }
    
    private func stopKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }
    
    private func sendKeepAlive() {
        guard _isConnected else { return }
        
        // Send a KeepAlive message to Deepgram
        // Deepgram accepts empty audio data or we can send the KeepAlive message type
        webSocketProvider.send("{\"type\": \"KeepAlive\"}")
        debugLog("💓 Keep-alive sent", component: "Streaming")
    }
    
    // MARK: - Audio Streaming
    
    private var sendAudioLogCount: Int = 0
    
    func sendAudio(_ samples: [Int16]) {
        guard !samples.isEmpty else { return }
        
        sendAudioLogCount += 1
        
        if !_isConnected {
            // Buffer audio for when we reconnect
            if pendingAudioBuffer.count < maxPendingBufferSize {
                pendingAudioBuffer.append(samples)
            }
            // Log occasionally when buffering
            if sendAudioLogCount % 50 == 1 {
                debugLog("📦 Buffering audio (not connected): \(pendingAudioBuffer.count) chunks", component: "Streaming")
            }
            return
        }
        
        // Log occasionally when sending
        if sendAudioLogCount % 100 == 1 {
            debugLog("🎤 Sending audio: \(samples.count) samples", component: "Streaming")
        }
        
        // Convert Int16 samples to Data (little-endian)
        let data = samples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        
        webSocketProvider.send(data)
    }
    
    private func flushPendingAudio() {
        guard !pendingAudioBuffer.isEmpty else { return }
        
        debugLog("📤 Flushing \(pendingAudioBuffer.count) pending audio chunks", component: "Streaming")
        
        for samples in pendingAudioBuffer {
            sendAudio(samples)
        }
        
        pendingAudioBuffer = []
    }
    
    // MARK: - Message Parsing
    
    private func handleMessage(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        // Check message type
        if let type = json["type"] as? String {
            switch type {
            case "Results":
                parseResultsMessage(json)
            case "Metadata":
                // Connection metadata - log and ignore
                debugLog("📋 Received metadata from Deepgram", component: "Streaming")
            case "Error":
                if let errorMessage = json["message"] as? String {
                    debugLog("❌ Error from Deepgram: \(errorMessage)", component: "Streaming")
                    let error = StreamingSTTError.transcriptionFailed(errorMessage)
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.streamingClient(self, didEncounterError: error)
                    }
                }
            default:
                debugLog("📨 Unknown message type: \(type)", component: "Streaming")
            }
        } else {
            // Older API format - try parsing as results directly
            parseResultsMessage(json)
        }
    }
    
    private func parseResultsMessage(_ json: [String: Any]) {
        // Extract the is_final flag
        let isFinal = json["is_final"] as? Bool ?? false
        
        // Navigate to transcript data
        guard let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let firstAlternative = alternatives.first else {
            return
        }
        
        // Get transcript text
        guard let transcript = firstAlternative["transcript"] as? String,
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        if isFinal {
            // Parse with diarization for final results
            if let words = firstAlternative["words"] as? [[String: Any]], !words.isEmpty {
                let segments = parseWordsWithDiarization(words)
                for segment in segments {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.streamingClient(self, didReceiveFinal: segment)
                    }
                }
            } else {
                // No word-level data, use full transcript
                let segment = TranscriptSegment(speaker: "Unknown", text: transcript)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.streamingClient(self, didReceiveFinal: segment)
                }
            }
        } else {
            // Interim result - extract speaker if available
            var speaker = "Unknown"
            if let words = firstAlternative["words"] as? [[String: Any]],
               let firstWord = words.first,
               let speakerIndex = firstWord["speaker"] as? Int {
                speaker = mapSpeakerLabel(speakerIndex)
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.streamingClient(self, didReceiveInterim: transcript, speaker: speaker)
            }
        }
    }
    
    private func parseWordsWithDiarization(_ words: [[String: Any]]) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        var currentSpeaker: Int = -1
        var currentText: [String] = []
        
        for word in words {
            guard let text = word["word"] as? String else { continue }
            let speaker = word["speaker"] as? Int ?? 0
            
            if speaker != currentSpeaker {
                // Save previous segment if exists
                if !currentText.isEmpty {
                    let speakerName = mapSpeakerLabel(currentSpeaker)
                    segments.append(TranscriptSegment(
                        speaker: speakerName,
                        text: currentText.joined(separator: " ")
                    ))
                }
                
                // Start new segment
                currentSpeaker = speaker
                currentText = [text]
            } else {
                currentText.append(text)
            }
        }
        
        // Don't forget the last segment
        if !currentText.isEmpty {
            let speakerName = mapSpeakerLabel(currentSpeaker)
            segments.append(TranscriptSegment(
                speaker: speakerName,
                text: currentText.joined(separator: " ")
            ))
        }
        
        return segments
    }
    
    private func mapSpeakerLabel(_ speakerIndex: Int) -> String {
        switch speakerIndex {
        case 0:
            return "Physician"
        case 1:
            return "Patient"
        default:
            return "Other"
        }
    }
}

// MARK: - Errors

enum StreamingSTTError: LocalizedError {
    case invalidConfiguration
    case connectionFailed(String)
    case transcriptionFailed(String)
    case notConnected
    
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Invalid streaming configuration"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .notConnected:
            return "Not connected to transcription service"
        }
    }
}

