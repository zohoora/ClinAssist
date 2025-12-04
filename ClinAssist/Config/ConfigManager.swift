import Foundation

struct AppConfig: Codable {
    let openrouterApiKey: String
    let deepgramApiKey: String
    let model: String
    let timing: TimingConfig
    let autoDetection: AutoDetectionConfig?
    let ollama: OllamaConfig?
    let deepgram: DeepgramConfig?
    let groq: GroqConfig?
    
    enum CodingKeys: String, CodingKey {
        case openrouterApiKey = "openrouter_api_key"
        case deepgramApiKey = "deepgram_api_key"
        case model
        case timing
        case autoDetection = "auto_detection"
        case ollama
        case deepgram
        case groq
    }
}

struct GroqConfig: Codable {
    let apiKey: String
    let model: String?
    let useForFinalSoap: Bool?
    
    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case model
        case useForFinalSoap = "use_for_final_soap"
    }
    
    static var `default`: GroqConfig {
        GroqConfig(
            apiKey: "",
            model: "moonshotai/kimi-k2-instruct-0905",
            useForFinalSoap: true
        )
    }
}

struct DeepgramConfig: Codable {
    let useStreaming: Bool?
    let interimResults: Bool?
    let saveAudioBackup: Bool?
    
    enum CodingKeys: String, CodingKey {
        case useStreaming = "use_streaming"
        case interimResults = "interim_results"
        case saveAudioBackup = "save_audio_backup"
    }
    
    static var `default`: DeepgramConfig {
        DeepgramConfig(
            useStreaming: true,
            interimResults: true,
            saveAudioBackup: true
        )
    }
}

struct OllamaConfig: Codable {
    let enabled: Bool
    let baseUrl: String?
    let model: String?
    let useForHelpers: Bool?
    let useForLiveSoap: Bool?
    let useForSessionDetection: Bool?
    let useForFinalSoap: Bool?  // Uses thinking mode for final SOAP
    
    enum CodingKeys: String, CodingKey {
        case enabled
        case baseUrl = "base_url"
        case model
        case useForHelpers = "use_for_helpers"
        case useForLiveSoap = "use_for_live_soap"
        case useForSessionDetection = "use_for_session_detection"
        case useForFinalSoap = "use_for_final_soap"
    }
    
    static var `default`: OllamaConfig {
        OllamaConfig(
            enabled: true,
            baseUrl: "http://localhost:11434",
            model: "qwen3:8b",
            useForHelpers: true,
            useForLiveSoap: true,
            useForSessionDetection: true,
            useForFinalSoap: false  // Disabled by default, uses Groq/OpenRouter
        )
    }
}

struct TimingConfig: Codable {
    let transcriptionIntervalSeconds: Int
    let helperUpdateIntervalSeconds: Int
    let soapUpdateIntervalSeconds: Int
    
    enum CodingKeys: String, CodingKey {
        case transcriptionIntervalSeconds = "transcription_interval_seconds"
        case helperUpdateIntervalSeconds = "helper_update_interval_seconds"
        case soapUpdateIntervalSeconds = "soap_update_interval_seconds"
    }
    
    static var `default`: TimingConfig {
        TimingConfig(
            transcriptionIntervalSeconds: 10,
            helperUpdateIntervalSeconds: 20,
            soapUpdateIntervalSeconds: 30
        )
    }
}

struct AutoDetectionConfig: Codable {
    let enabled: Bool
    let startKeywords: [String]?
    let endKeywords: [String]?
    let silenceThresholdSeconds: Int?
    let minEncounterDurationSeconds: Int?
    let speechActivityThreshold: Double?
    let bufferDurationSeconds: Int?
    
    enum CodingKeys: String, CodingKey {
        case enabled
        case startKeywords = "start_keywords"
        case endKeywords = "end_keywords"
        case silenceThresholdSeconds = "silence_threshold_seconds"
        case minEncounterDurationSeconds = "min_encounter_duration_seconds"
        case speechActivityThreshold = "speech_activity_threshold"
        case bufferDurationSeconds = "buffer_duration_seconds"
    }
    
    static var `default`: AutoDetectionConfig {
        AutoDetectionConfig(
            enabled: false,
            startKeywords: nil,
            endKeywords: nil,
            silenceThresholdSeconds: 45,
            minEncounterDurationSeconds: 60,
            speechActivityThreshold: 0.02,
            bufferDurationSeconds: 45  // Needs time for: audio record + transcribe + LLM analysis (increased)
        )
    }
}

@MainActor
class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    @Published var config: AppConfig?
    @Published var configError: String?
    
    private let configPath: URL
    
    var isConfigured: Bool {
        config != nil
    }
    
    var isAutoDetectionEnabled: Bool {
        config?.autoDetection?.enabled ?? false
    }
    
    var isOllamaEnabled: Bool {
        config?.ollama?.enabled ?? false
    }
    
    var ollamaBaseUrl: String {
        config?.ollama?.baseUrl ?? "http://localhost:11434"
    }
    
    var ollamaModel: String {
        config?.ollama?.model ?? "qwen3:8b"
    }
    
    var useOllamaForHelpers: Bool {
        (config?.ollama?.enabled ?? false) && (config?.ollama?.useForHelpers ?? true)
    }
    
    var useOllamaForLiveSoap: Bool {
        (config?.ollama?.enabled ?? false) && (config?.ollama?.useForLiveSoap ?? true)
    }
    
    var useOllamaForSessionDetection: Bool {
        (config?.ollama?.enabled ?? false) && (config?.ollama?.useForSessionDetection ?? true)
    }
    
    var useOllamaForFinalSoap: Bool {
        (config?.ollama?.enabled ?? false) && (config?.ollama?.useForFinalSoap ?? false)
    }
    
    // MARK: - Groq Config
    
    var isGroqEnabled: Bool {
        guard let apiKey = config?.groq?.apiKey, !apiKey.isEmpty else { return false }
        return true
    }
    
    var groqApiKey: String {
        config?.groq?.apiKey ?? ""
    }
    
    var groqModel: String {
        config?.groq?.model ?? "moonshotai/kimi-k2-instruct-0905"
    }
    
    var useGroqForFinalSoap: Bool {
        isGroqEnabled && (config?.groq?.useForFinalSoap ?? true)
    }
    
    // MARK: - Deepgram Streaming Config
    
    var useDeepgramStreaming: Bool {
        config?.deepgram?.useStreaming ?? true  // Default to streaming
    }
    
    var showInterimResults: Bool {
        config?.deepgram?.interimResults ?? true
    }
    
    var saveAudioBackup: Bool {
        config?.deepgram?.saveAudioBackup ?? true
    }
    
    init() {
        let dropboxPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Dropbox")
            .appendingPathComponent("livecode_records")
        
        configPath = dropboxPath.appendingPathComponent("config.json")
        
        // Create livecode_records folder if needed
        try? FileManager.default.createDirectory(at: dropboxPath, withIntermediateDirectories: true)
        
        loadConfig()
    }
    
    func loadConfig() {
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            configError = "Config file not found at ~/Dropbox/livecode_records/config.json"
            return
        }
        
        do {
            let data = try Data(contentsOf: configPath)
            config = try JSONDecoder().decode(AppConfig.self, from: data)
            configError = nil
        } catch {
            configError = "Failed to parse config.json: \(error.localizedDescription)"
            config = nil
        }
    }
    
    /// Builds SessionDetector.Config from the loaded config
    func buildSessionDetectorConfig() -> SessionDetector.Config {
        var detectorConfig = SessionDetector.Config()
        
        if let autoConfig = config?.autoDetection {
            detectorConfig.enabled = autoConfig.enabled
            
            if let startKeywords = autoConfig.startKeywords, !startKeywords.isEmpty {
                detectorConfig.startKeywords = startKeywords
            }
            
            if let endKeywords = autoConfig.endKeywords, !endKeywords.isEmpty {
                detectorConfig.endKeywords = endKeywords
            }
            
            if let silenceThreshold = autoConfig.silenceThresholdSeconds {
                detectorConfig.silenceThresholdSeconds = TimeInterval(silenceThreshold)
            }
            
            if let minDuration = autoConfig.minEncounterDurationSeconds {
                detectorConfig.minEncounterDurationSeconds = TimeInterval(minDuration)
            }
            
            if let speechThreshold = autoConfig.speechActivityThreshold {
                detectorConfig.speechActivityThreshold = Float(speechThreshold)
            }
            
            if let bufferDuration = autoConfig.bufferDurationSeconds {
                detectorConfig.bufferDurationSeconds = TimeInterval(bufferDuration)
            }
        } else {
            detectorConfig.enabled = false
        }
        
        return detectorConfig
    }
    
    func createSampleConfig() {
        let sampleConfig = """
        {
          "openrouter_api_key": "sk-or-your-key-here",
          "deepgram_api_key": "your-deepgram-key-here",
          "model": "anthropic/claude-sonnet-4",
          "timing": {
            "transcription_interval_seconds": 10,
            "helper_update_interval_seconds": 10,
            "soap_update_interval_seconds": 15
          },
          "deepgram": {
            "use_streaming": true,
            "interim_results": true,
            "save_audio_backup": true
          },
          "auto_detection": {
            "enabled": false,
            "start_keywords": [
              "what brings you in",
              "how can i help",
              "what's going on",
              "come on in",
              "have a seat"
            ],
            "end_keywords": [
              "take care",
              "see you",
              "any questions",
              "front desk",
              "feel better"
            ],
            "silence_threshold_seconds": 45,
            "min_encounter_duration_seconds": 60,
            "speech_activity_threshold": 0.02,
            "buffer_duration_seconds": 10
          },
          "ollama": {
            "enabled": true,
            "base_url": "http://localhost:11434",
            "model": "qwen3:8b",
            "use_for_helpers": true,
            "use_for_live_soap": true,
            "use_for_session_detection": true
          },
          "groq": {
            "api_key": "your-groq-api-key-here",
            "model": "moonshotai/kimi-k2-instruct-0905",
            "use_for_final_soap": true
          }
        }
        """
        
        try? sampleConfig.write(to: configPath, atomically: true, encoding: .utf8)
    }
}
