import Foundation

struct AppConfig: Codable {
    let openrouterApiKey: String
    let deepgramApiKey: String
    let model: String
    let timing: TimingConfig
    
    enum CodingKeys: String, CodingKey {
        case openrouterApiKey = "openrouter_api_key"
        case deepgramApiKey = "deepgram_api_key"
        case model
        case timing
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

class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    @Published var config: AppConfig?
    @Published var configError: String?
    
    private let configPath: URL
    
    var isConfigured: Bool {
        config != nil
    }
    
    init() {
        let desktopPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("ClinAssist")
        
        configPath = desktopPath.appendingPathComponent("config.json")
        
        // Create ClinAssist folder if needed
        try? FileManager.default.createDirectory(at: desktopPath, withIntermediateDirectories: true)
        
        loadConfig()
    }
    
    func loadConfig() {
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            configError = "Config file not found at ~/Desktop/ClinAssist/config.json"
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
    
    func createSampleConfig() {
        let sampleConfig = """
        {
          "openrouter_api_key": "sk-or-your-key-here",
          "deepgram_api_key": "your-deepgram-key-here",
          "model": "openai/gpt-4.1",
          "timing": {
            "transcription_interval_seconds": 10,
            "helper_update_interval_seconds": 20,
            "soap_update_interval_seconds": 30
          }
        }
        """
        
        try? sampleConfig.write(to: configPath, atomically: true, encoding: .utf8)
    }
}

