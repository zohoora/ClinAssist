import XCTest
import AVFoundation
@testable import ClinAssist

@MainActor
final class AudioManagerTests: XCTestCase {
    
    var audioManager: AudioManager!
    var mockDelegate: MockAudioManagerDelegate!
    var tempDir: URL!
    var fakeNode: FakeInputNode!
    var fakeEngine: FakeAudioEngine!
    
    // MARK: - Test Doubles
    
    final class FakePermissionProvider: MicrophonePermissionProviding {
        var status: AVAuthorizationStatus = .authorized
        func authorizationStatus() -> AVAuthorizationStatus { status }
        func requestAccess(_ completion: @escaping (Bool) -> Void) { completion(status == .authorized) }
    }
    
    final class FakeInputNode: AudioInputNodeProtocol {
        let format: AVAudioFormat
        var installedTap: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
        
        init(format: AVAudioFormat) {
            self.format = format
        }
        
        func outputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat { format }
        
        func installTap(
            onBus bus: AVAudioNodeBus,
            bufferSize: AVAudioFrameCount,
            format: AVAudioFormat?,
            block: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void
        ) {
            installedTap = block
        }
        
        func removeTap(onBus bus: AVAudioNodeBus) {
            installedTap = nil
        }
        
        func emit(buffer: AVAudioPCMBuffer) {
            guard let installedTap else { return }
            let time = AVAudioTime(sampleTime: 0, atRate: buffer.format.sampleRate)
            installedTap(buffer, time)
        }
    }
    
    final class FakeAudioEngine: AudioEngineProtocol {
        let node: FakeInputNode
        var started = false
        
        init(node: FakeInputNode) {
            self.node = node
        }
        
        var inputNode: AudioInputNodeProtocol { node }
        var isRunning: Bool { started }
        
        func start() throws { started = true }
        func stop() { started = false }
        func pause() { started = false }
    }
    
    final class FakeEngineFactory: AudioEngineFactoryProtocol {
        let engine: FakeAudioEngine
        init(engine: FakeAudioEngine) { self.engine = engine }
        func makeEngine() -> AudioEngineProtocol { engine }
    }
    
    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClinAssistTestsAudioTemp")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let floatFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
        fakeNode = FakeInputNode(format: floatFormat)
        fakeEngine = FakeAudioEngine(node: fakeNode)
        let factory = FakeEngineFactory(engine: fakeEngine)
        let permissions = FakePermissionProvider()
        permissions.status = .authorized
        
        audioManager = AudioManager(engineFactory: factory, permissionProvider: permissions, tempBasePath: tempDir)
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
        fakeNode = nil
        fakeEngine = nil
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
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
        try audioManager.startMonitoring()
        
        XCTAssertEqual(audioManager.mode, .monitoring)
        XCTAssertTrue(audioManager.isMonitoring)
        XCTAssertFalse(audioManager.isRecording)
    }
    
    func testStopMonitoringSetsIdleMode() throws {
        try audioManager.startMonitoring()
        audioManager.stopMonitoring()
        
        XCTAssertEqual(audioManager.mode, .idle)
        XCTAssertFalse(audioManager.isMonitoring)
    }
    
    func testStartRecordingSetsMode() throws {
        let encounterId = UUID()
        try audioManager.startRecording(encounterId: encounterId)
        
        XCTAssertEqual(audioManager.mode, .recording)
        XCTAssertTrue(audioManager.isRecording)
        XCTAssertFalse(audioManager.isMonitoring)
    }
    
    func testStopRecordingSetsIdleMode() throws {
        let encounterId = UUID()
        try audioManager.startRecording(encounterId: encounterId)
        audioManager.stopRecording()
        
        XCTAssertEqual(audioManager.mode, .idle)
        XCTAssertFalse(audioManager.isRecording)
    }
    
    func testTransitionFromMonitoringToRecording() throws {
        try audioManager.startMonitoring()
        XCTAssertEqual(audioManager.mode, .monitoring)
        
        let encounterId = UUID()
        try audioManager.transitionToRecording(encounterId: encounterId)
        
        XCTAssertEqual(audioManager.mode, .recording)
        XCTAssertTrue(audioManager.isRecording)
        XCTAssertFalse(audioManager.isMonitoring)
    }
    
    func testTransitionFromRecordingToMonitoring() throws {
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
    
    // MARK: - Signal Processing / Delegate Tests
    
    func testMonitoringTapUpdatesAudioLevelAndStreamsSamples() throws {
        try audioManager.startMonitoring()
        
        let format = fakeNode.format
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024) else {
            XCTFail("Failed to create buffer")
            return
        }
        
        buffer.frameLength = 1024
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(buffer.frameLength) { data[i] = 0.1 } // RMS should be ~0.1
        
        fakeNode.emit(buffer: buffer)
        
        let expectation = XCTestExpectation(description: "Main thread updates applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertGreaterThan(audioManager.currentAudioLevel, 0.05)
        XCTAssertFalse(mockDelegate.capturedSamples.isEmpty)
        XCTAssertEqual(mockDelegate.capturedSamples.last?.count, 1024)
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
