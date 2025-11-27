import AVFoundation
import Foundation

protocol AudioManagerDelegate: AnyObject {
    func audioManager(_ manager: AudioManager, didSaveChunk chunkURL: URL, chunkNumber: Int)
    func audioManager(_ manager: AudioManager, didEncounterError error: Error)
}

class AudioManager: NSObject, ObservableObject {
    weak var delegate: AudioManagerDelegate?
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    
    @Published var isRecording = false
    @Published var permissionGranted = false
    @Published var permissionError: String?
    
    private var currentEncounterId: UUID?
    private var chunkNumber: Int = 0
    private var audioBuffer: [Int16] = []
    private var chunkTimer: Timer?
    
    private let sampleRate: Double = 16000
    private let chunkDurationSeconds: TimeInterval = 10
    
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
    
    // MARK: - Recording
    
    func startRecording(encounterId: UUID) throws {
        guard permissionGranted else {
            throw AudioError.permissionDenied
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
        }
        
        // Start the engine
        try audioEngine.start()
        isRecording = true
        
        // Start chunk timer
        startChunkTimer()
    }
    
    func stopRecording() {
        stopChunkTimer()
        
        // Save any remaining audio
        if !audioBuffer.isEmpty {
            saveCurrentChunk()
        }
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        
        isRecording = false
        currentEncounterId = nil
    }
    
    func pauseRecording() {
        audioEngine?.pause()
        stopChunkTimer()
    }
    
    func resumeRecording() {
        try? audioEngine?.start()
        startChunkTimer()
    }
    
    // MARK: - Audio Processing
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter?, targetFormat: AVAudioFormat) {
        guard let converter = converter else {
            // If no conversion needed, directly copy
            if let channelData = buffer.int16ChannelData {
                let frameCount = Int(buffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
                DispatchQueue.main.async {
                    self.audioBuffer.append(contentsOf: samples)
                }
            }
            return
        }
        
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
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
            DispatchQueue.main.async {
                self.audioBuffer.append(contentsOf: samples)
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
                DispatchQueue.main.async {
                    self.delegate?.audioManager(self, didSaveChunk: chunkPath, chunkNumber: self.chunkNumber)
                }
            } catch {
                DispatchQueue.main.async {
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
            .appendingPathComponent("Desktop")
            .appendingPathComponent("ClinAssist")
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

