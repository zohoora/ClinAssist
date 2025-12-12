import AVFoundation
import Foundation

enum UITestingSupport {
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting") ||
        ProcessInfo.processInfo.environment["UI_TESTING"] == "1"
    }
}

// MARK: - UI testing service stubs

final class UITestingPermissionProvider: MicrophonePermissionProviding {
    func authorizationStatus() -> AVAuthorizationStatus { .authorized }
    func requestAccess(_ completion: @escaping (Bool) -> Void) { completion(true) }
}

final class UITestingAudioInputNode: AudioInputNodeProtocol {
    private let format: AVAudioFormat
    private var tap: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    
    init() {
        // Float32 makes RMS calculation path safe.
        self.format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    }
    
    func outputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat { format }
    func installTap(onBus bus: AVAudioNodeBus, bufferSize: AVAudioFrameCount, format: AVAudioFormat?, block: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void) {
        tap = block
    }
    func removeTap(onBus bus: AVAudioNodeBus) { tap = nil }
}

final class UITestingAudioEngine: AudioEngineProtocol {
    let input = UITestingAudioInputNode()
    var isRunning: Bool = false
    var inputNode: AudioInputNodeProtocol { input }
    func start() throws { isRunning = true }
    func stop() { isRunning = false }
    func pause() { isRunning = false }
}

final class UITestingAudioEngineFactory: AudioEngineFactoryProtocol {
    func makeEngine() -> AudioEngineProtocol { UITestingAudioEngine() }
}

final class UITestingSTTClient: STTClient {
    func transcribe(audioData: Data) async throws -> [TranscriptSegment] {
        [
            TranscriptSegment(speaker: "Physician", text: "Hello"),
            TranscriptSegment(speaker: "Patient", text: "Hi doctor")
        ]
    }
}

final class UITestingStreamingClient: StreamingSTTClient {
    weak var delegate: StreamingSTTClientDelegate?
    private(set) var isConnected: Bool = false
    
    func connect() throws {
        isConnected = true
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.delegate?.streamingClient(self, didChangeConnectionState: true)
            // Provide deterministic transcript so SOAP generation has input.
            self.delegate?.streamingClient(
                self,
                didReceiveFinal: TranscriptSegment(speaker: "Physician", text: "Good morning. What brings you in today?")
            )
            self.delegate?.streamingClient(
                self,
                didReceiveFinal: TranscriptSegment(speaker: "Patient", text: "I have a headache for three days with nausea.")
            )
        }
    }
    
    func disconnect() {
        isConnected = false
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.delegate?.streamingClient(self, didChangeConnectionState: false)
        }
    }
    
    func sendAudio(_ samples: [Int16]) {
        // No-op: UI tests don't need actual transcription.
    }
}

final class UITestingLLMClient: LLMClient {
    override func complete(systemPrompt: String, userContent: String, modelOverride: String? = nil) async throws -> String {
        // Minimal deterministic SOAP-like output.
        return """
        PATIENT: UITest

        S:
        - Test subjective

        O:
        - Test objective

        A:
        - Test assessment

        P:
        - Test plan
        """
    }
}

