import AVFoundation
import Foundation

// MARK: - Audio Engine Abstractions (for testability)

protocol AudioInputNodeProtocol: AnyObject {
    func outputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat
    func installTap(
        onBus bus: AVAudioNodeBus,
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        block: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void
    )
    func removeTap(onBus bus: AVAudioNodeBus)
}

protocol AudioEngineProtocol: AnyObject {
    var inputNode: AudioInputNodeProtocol { get }
    var isRunning: Bool { get }
    func start() throws
    func stop()
    func pause()
}

protocol AudioEngineFactoryProtocol {
    func makeEngine() -> AudioEngineProtocol
}

final class SystemAudioEngineFactory: AudioEngineFactoryProtocol {
    func makeEngine() -> AudioEngineProtocol { AVAudioEngineWrapper() }
}

final class AVAudioInputNodeWrapper: AudioInputNodeProtocol {
    private let node: AVAudioInputNode
    
    init(_ node: AVAudioInputNode) {
        self.node = node
    }
    
    func outputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat {
        node.outputFormat(forBus: bus)
    }
    
    func installTap(
        onBus bus: AVAudioNodeBus,
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        block: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) {
        node.installTap(onBus: bus, bufferSize: bufferSize, format: format, block: block)
    }
    
    func removeTap(onBus bus: AVAudioNodeBus) {
        node.removeTap(onBus: bus)
    }
}

final class AVAudioEngineWrapper: AudioEngineProtocol {
    private let engine: AVAudioEngine
    private let input: AudioInputNodeProtocol
    
    init(engine: AVAudioEngine = AVAudioEngine()) {
        self.engine = engine
        self.input = AVAudioInputNodeWrapper(engine.inputNode)
    }
    
    var inputNode: AudioInputNodeProtocol { input }
    var isRunning: Bool { engine.isRunning }
    
    func start() throws { try engine.start() }
    func stop() { engine.stop() }
    func pause() { engine.pause() }
}

// MARK: - Microphone Permission Abstraction

protocol MicrophonePermissionProviding {
    func authorizationStatus() -> AVAuthorizationStatus
    func requestAccess(_ completion: @escaping (Bool) -> Void)
}

final class SystemMicrophonePermissionProvider: MicrophonePermissionProviding {
    func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }
    
    func requestAccess(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }
}

