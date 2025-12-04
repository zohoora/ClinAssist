import AVFoundation
import Foundation

@MainActor
protocol AudioManagerDelegate: AnyObject {
    func audioManager(_ manager: AudioManager, didSaveChunk chunkURL: URL, chunkNumber: Int)
    func audioManager(_ manager: AudioManager, didEncounterError error: Error)
    func audioManager(_ manager: AudioManager, didUpdateAudioLevel level: Float)
    /// Called in streaming mode with real-time audio samples (16kHz, mono, Int16)
    func audioManager(_ manager: AudioManager, didCaptureAudioSamples samples: [Int16])
}

// Make delegate methods optional with default implementations
extension AudioManagerDelegate {
    func audioManager(_ manager: AudioManager, didUpdateAudioLevel level: Float) {}
    func audioManager(_ manager: AudioManager, didCaptureAudioSamples samples: [Int16]) {}
}

@MainActor
class AudioManager: NSObject, ObservableObject {
    weak var delegate: AudioManagerDelegate?
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    
    @Published var isRecording = false
    @Published var isMonitoring = false
    @Published var permissionGranted = false
    @Published var permissionError: String?
    @Published var currentAudioLevel: Float = 0
    
    private var currentEncounterId: UUID?
    private var chunkNumber: Int = 0
    private var audioBuffer: [Int16] = []
    private var chunkTimer: Timer?
    private var levelTimer: Timer?
    
    // Audio level tracking for VAD
    private var recentLevels: [Float] = []
    private let levelHistorySize = 10
    
    private let sampleRate: Double = 16000
    private let chunkDurationSeconds: TimeInterval = 10
    
    // Streaming mode configuration
    @Published var streamingEnabled: Bool = true  // Stream audio in real-time
    @Published var saveAudioBackup: Bool = true   // Also save chunks as backup
    
    // Mode of operation
    enum Mode {
        case idle
        case monitoring  // Low-power listening for speech detection
        case recording   // Full recording for transcription
    }
    
    @Published var mode: Mode = .idle
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    // MARK: - Permissions
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            permissionGranted = true
            permissionError = nil
        case .notDetermined:
            requestPermissions()
        case .denied, .restricted:
            permissionGranted = false
            permissionError = "Microphone access is required. Please enable it in System Settings > Privacy & Security > Microphone."
        @unknown default:
            permissionGranted = false
            permissionError = "Unknown permission status"
        }
    }
    
    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.permissionGranted = granted
                if !granted {
                    self?.permissionError = "Microphone access is required. Please enable it in System Settings > Privacy & Security > Microphone."
                }
            }
        }
    }
    
    // MARK: - Monitoring Mode (VAD)
    
    func startMonitoring() throws {
        debugLog("startMonitoring called - current mode: \(mode)", component: "Audio")
        guard permissionGranted else {
            throw AudioError.permissionDenied
        }
        
        guard mode == .idle else {
            debugLog("⚠️ startMonitoring skipped - already in \(mode) mode", component: "Audio")
            return
        }
        
        // Setup audio engine for monitoring
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw AudioError.engineSetupFailed
        }
        
        inputNode = audioEngine.inputNode
        
        guard let node = inputNode else {
            throw AudioError.engineSetupFailed
        }
        
        let nativeFormat = node.outputFormat(forBus: 0)
        guard nativeFormat.sampleRate > 0 else {
            debugLog("❌ Invalid audio format - sample rate is 0", component: "Audio")
            throw AudioError.engineSetupFailed
        }
        
        // Install tap for level monitoring (lower buffer size for responsiveness)
        node.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, time in
            self?.processLevelBuffer(buffer)
        }
        
        try audioEngine.start()
        mode = .monitoring
        isMonitoring = true
        
        // Start level reporting timer
        startLevelTimer()
        
        debugLog("✅ Started monitoring mode", component: "Audio")
    }
    
    func stopMonitoring() {
        guard mode == .monitoring else { return }
        
        stopLevelTimer()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        
        mode = .idle
        isMonitoring = false
        currentAudioLevel = 0
        
        debugLog("Stopped monitoring mode", component: "Audio")
    }
    
    private func processLevelBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { 
            debugLog("⚠️ No channel data in buffer", component: "Audio")
            return 
        }
        
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            debugLog("⚠️ Empty buffer received", component: "Audio")
            return
        }
        
        let channelDataValue = channelData[0]
        
        // Calculate RMS (Root Mean Square) for audio level
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelDataValue[i]
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(frameLength))
        
        // Also send raw samples to delegate for streaming
        if mode == .monitoring {
            var samples: [Int16] = []
            for i in 0..<frameLength {
                let sample = channelDataValue[i]
                let clipped = max(-1.0, min(1.0, sample))
                samples.append(Int16(clipped * 32767.0))
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.audioManager(self, didCaptureAudioSamples: samples)
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Smooth the level with recent history
            self.recentLevels.append(rms)
            if self.recentLevels.count > self.levelHistorySize {
                self.recentLevels.removeFirst()
            }
            
            let averageLevel = self.recentLevels.reduce(0, +) / Float(self.recentLevels.count)
            self.currentAudioLevel = averageLevel
        }
    }
    
    private func startLevelTimer() {
        debugLog("🕐 Starting level timer", component: "Audio")
        // Ensure timer runs on main thread's run loop
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.delegate?.audioManager(self, didUpdateAudioLevel: self.currentAudioLevel)
            }
            debugLog("✅ Level timer scheduled on main run loop", component: "Audio")
        }
    }
    
    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
    }
    
    // MARK: - Recording Mode
    
    func startRecording(encounterId: UUID) throws {
        guard permissionGranted else {
            throw AudioError.permissionDenied
        }
        
        // If monitoring, transition to recording
        if mode == .monitoring {
            stopMonitoring()
        }
        
        currentEncounterId = encounterId
        chunkNumber = 0
        audioBuffer = []
        
        // Create temp directory for this encounter
        let tempPath = encounterTempPath(for: encounterId)
        try FileManager.default.createDirectory(at: tempPath, withIntermediateDirectories: true)
        
        // Setup audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw AudioError.engineSetupFailed
        }
        
        inputNode = audioEngine.inputNode
        
        // Get the native format
        let nativeFormat = inputNode!.outputFormat(forBus: 0)
        
        // Create target format (16kHz, mono, Int16)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioError.formatError
        }
        
        // Create converter if needed
        let converter = AVAudioConverter(from: nativeFormat, to: targetFormat)
        
        // Install tap on input node
        inputNode!.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
            // Also process for level monitoring during recording
            self?.processLevelBuffer(buffer)
        }
        
        // Start the engine
        try audioEngine.start()
        mode = .recording
        isRecording = true
        isMonitoring = false
        
        // Start chunk timer only if backup is enabled
        if saveAudioBackup {
            startChunkTimer()
        }
        // Keep level timer running
        startLevelTimer()
        
        debugLog("✅ Started recording mode for encounter: \(encounterId) (streaming: \(streamingEnabled), backup: \(saveAudioBackup))", component: "Audio")
    }
    
    func stopRecording() {
        debugLog("stopRecording called - current mode: \(mode)", component: "Audio")
        guard mode == .recording else { 
            debugLog("⚠️ stopRecording skipped - not in recording mode", component: "Audio")
            return 
        }
        
        stopChunkTimer()
        stopLevelTimer()
        
        // Save any remaining audio if backup is enabled
        if saveAudioBackup && !audioBuffer.isEmpty {
            saveCurrentChunk()
        }
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        
        mode = .idle
        isRecording = false
        currentEncounterId = nil
        currentAudioLevel = 0
        audioBuffer = []
        
        debugLog("Stopped recording mode", component: "Audio")
    }
    
    func pauseRecording() {
        audioEngine?.pause()
        stopChunkTimer()
    }
    
    func resumeRecording() {
        try? audioEngine?.start()
        startChunkTimer()
    }
    
    // MARK: - Transition: Monitoring → Recording
    
    /// Seamlessly transition from monitoring to recording without losing audio
    func transitionToRecording(encounterId: UUID) throws {
        if mode == .monitoring {
            // Stop monitoring tap
            audioEngine?.inputNode.removeTap(onBus: 0)
            stopLevelTimer()
            
            currentEncounterId = encounterId
            chunkNumber = 0
            audioBuffer = []
            
            // Create temp directory
            let tempPath = encounterTempPath(for: encounterId)
            try FileManager.default.createDirectory(at: tempPath, withIntermediateDirectories: true)
            
            guard let audioEngine = audioEngine else {
                throw AudioError.engineSetupFailed
            }
            
            inputNode = audioEngine.inputNode
            let nativeFormat = inputNode!.outputFormat(forBus: 0)
            
            guard let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: true
            ) else {
                throw AudioError.formatError
            }
            
            let converter = AVAudioConverter(from: nativeFormat, to: targetFormat)
            
            // Install recording tap
            inputNode!.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, time in
                self?.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
                self?.processLevelBuffer(buffer)
            }
            
            mode = .recording
            isRecording = true
            isMonitoring = false
            
            if saveAudioBackup {
                startChunkTimer()
            }
            startLevelTimer()
            
            debugLog("✅ Transitioned from monitoring to recording (streaming: \(streamingEnabled), backup: \(saveAudioBackup))", component: "Audio")
        } else {
            // Not monitoring, do regular start
            try startRecording(encounterId: encounterId)
        }
    }
    
    /// Transition from recording back to monitoring
    func transitionToMonitoring() throws {
        if mode == .recording {
            stopChunkTimer()
            
            // Save remaining audio
            if !audioBuffer.isEmpty {
                saveCurrentChunk()
            }
            
            // Remove recording tap
            audioEngine?.inputNode.removeTap(onBus: 0)
            
            guard let audioEngine = audioEngine else {
                throw AudioError.engineSetupFailed
            }
            
            // Clear level history for fresh monitoring
            recentLevels = []
            currentAudioLevel = 0
            
            guard let node = inputNode else {
                throw AudioError.engineSetupFailed
            }
            
            let nativeFormat = node.outputFormat(forBus: 0)
            guard nativeFormat.sampleRate > 0 else {
                debugLog("❌ Invalid audio format - sample rate is 0", component: "Audio")
                throw AudioError.engineSetupFailed
            }
            
            debugLog("📊 Installing monitoring tap - format: \(nativeFormat.sampleRate)Hz, \(nativeFormat.channelCount) ch", component: "Audio")
            
            // Install monitoring tap
            node.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, time in
                self?.processLevelBuffer(buffer)
            }
            
            // Ensure engine is running
            if !audioEngine.isRunning {
                debugLog("⚠️ Audio engine not running after tap install, restarting...", component: "Audio")
                try audioEngine.start()
            }
            
            mode = .monitoring
            isRecording = false
            isMonitoring = true
            currentEncounterId = nil
            
            // Start level timer for audio level reporting
            startLevelTimer()
            
            debugLog("✅ Transitioned from recording to monitoring", component: "Audio")
        } else {
            try startMonitoring()
        }
    }
    
    // MARK: - Audio Processing
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter?, targetFormat: AVAudioFormat) {
        var samples: [Int16] = []
        
        if let converter = converter {
            // Convert to target format
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * (sampleRate / buffer.format.sampleRate)
            )
            
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
                return
            }
            
            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            if status == .haveData, let channelData = convertedBuffer.int16ChannelData {
                let frameCount = Int(convertedBuffer.frameLength)
                samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
            }
        } else {
            // If no conversion needed, directly copy
            if let channelData = buffer.int16ChannelData {
                let frameCount = Int(buffer.frameLength)
                samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
            }
        }
        
        guard !samples.isEmpty else { return }
        
        // Stream samples in real-time if streaming is enabled
        if streamingEnabled {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.audioManager(self, didCaptureAudioSamples: samples)
            }
        } else {
            // Log once that streaming is disabled
            struct Once { static var logged = false }
            if !Once.logged {
                debugLog("⚠️ streamingEnabled is FALSE - not sending to streaming client", component: "Audio")
                Once.logged = true
            }
        }
        
        // Also buffer for chunk backup if enabled
        if saveAudioBackup {
            DispatchQueue.main.async { [weak self] in
                self?.audioBuffer.append(contentsOf: samples)
            }
        }
    }
    
    // MARK: - Chunk Management
    
    private func startChunkTimer() {
        chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkDurationSeconds, repeats: true) { [weak self] _ in
            self?.saveCurrentChunk()
        }
    }
    
    private func stopChunkTimer() {
        chunkTimer?.invalidate()
        chunkTimer = nil
    }
    
    private func saveCurrentChunk() {
        guard let encounterId = currentEncounterId, !audioBuffer.isEmpty else { return }
        
        chunkNumber += 1
        let samples = audioBuffer
        audioBuffer = []
        
        // Save in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let chunkPath = self.encounterTempPath(for: encounterId)
                .appendingPathComponent(String(format: "chunk_%03d.wav", self.chunkNumber))
            
            do {
                try self.writeWAVFile(samples: samples, to: chunkPath)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.audioManager(self, didSaveChunk: chunkPath, chunkNumber: self.chunkNumber)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.audioManager(self, didEncounterError: error)
                }
            }
        }
    }
    
    // MARK: - WAV File Writing
    
    private func writeWAVFile(samples: [Int16], to url: URL) throws {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let sampleRateInt: UInt32 = UInt32(sampleRate)
        let byteRate: UInt32 = sampleRateInt * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)
        let dataSize: UInt32 = UInt32(samples.count * 2)
        let chunkSize: UInt32 = 36 + dataSize
        
        var data = Data()
        
        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        
        // fmt subchunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // Subchunk1Size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // AudioFormat (PCM)
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRateInt.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        
        // data subchunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        
        // Audio samples
        for sample in samples {
            data.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }
        
        try data.write(to: url)
    }
    
    // MARK: - Paths
    
    private func encounterTempPath(for encounterId: UUID) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Dropbox")
            .appendingPathComponent("livecode_records")
            .appendingPathComponent("temp")
            .appendingPathComponent(encounterId.uuidString)
    }
    
    func getChunksForEncounter(_ encounterId: UUID) -> [URL] {
        let tempPath = encounterTempPath(for: encounterId)
        guard let files = try? FileManager.default.contentsOfDirectory(at: tempPath, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { $0.pathExtension == "wav" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

// MARK: - Errors

enum AudioError: LocalizedError {
    case permissionDenied
    case engineSetupFailed
    case formatError
    case recordingFailed
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access is required. Please enable it in System Settings > Privacy & Security > Microphone."
        case .engineSetupFailed:
            return "Failed to setup audio engine"
        case .formatError:
            return "Failed to create audio format"
        case .recordingFailed:
            return "Recording failed"
        }
    }
}