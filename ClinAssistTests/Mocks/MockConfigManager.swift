import Foundation
@testable import ClinAssist

/// Mock ConfigManager for testing with controlled configurations
@MainActor
class MockConfigManager: ConfigManager {
    
    // MARK: - Test Configuration Presets
    
    /// Creates a config manager with streaming enabled (default)
    static func withStreaming() -> MockConfigManager {
        let manager = MockConfigManager()
        manager.setupConfig(
            useStreaming: true,
            saveAudioBackup: true,
            autoDetectionEnabled: false
        )
        return manager
    }
    
    /// Creates a config manager with streaming disabled (REST only)
    static func withoutStreaming() -> MockConfigManager {
        let manager = MockConfigManager()
        manager.setupConfig(
            useStreaming: false,
            saveAudioBackup: true,
            autoDetectionEnabled: false
        )
        return manager
    }
    
    /// Creates a config manager with auto-detection enabled
    static func withAutoDetection() -> MockConfigManager {
        let manager = MockConfigManager()
        manager.setupConfig(
            useStreaming: true,
            saveAudioBackup: true,
            autoDetectionEnabled: true,
            ollamaEnabled: true,
            useOllamaForSessionDetection: true
        )
        return manager
    }
    
    /// Creates a config manager with Ollama enabled
    static func withOllama() -> MockConfigManager {
        let manager = MockConfigManager()
        manager.setupConfig(
            useStreaming: true,
            saveAudioBackup: true,
            autoDetectionEnabled: false,
            ollamaEnabled: true,
            useOllamaForHelpers: true,
            useOllamaForLiveSoap: true
        )
        return manager
    }
    
    /// Creates a minimal config manager
    static func minimal() -> MockConfigManager {
        let manager = MockConfigManager()
        manager.setupConfig(
            useStreaming: false,
            saveAudioBackup: false,
            autoDetectionEnabled: false
        )
        return manager
    }
    
    // MARK: - Configuration Setup
    
    func setupConfig(
        useStreaming: Bool = true,
        interimResults: Bool = true,
        saveAudioBackup: Bool = true,
        autoDetectionEnabled: Bool = false,
        ollamaEnabled: Bool = false,
        useOllamaForHelpers: Bool = false,
        useOllamaForLiveSoap: Bool = false,
        useOllamaForSessionDetection: Bool = false,
        openrouterApiKey: String = "test-openrouter-key",
        deepgramApiKey: String = "test-deepgram-key",
        model: String = "test-model"
    ) {
        let deepgramConfig = DeepgramConfig(
            useStreaming: useStreaming,
            interimResults: interimResults,
            saveAudioBackup: saveAudioBackup
        )
        
        let ollamaConfig = OllamaConfig(
            enabled: ollamaEnabled,
            baseUrl: "http://localhost:11434",
            model: "qwen3:8b",
            useForHelpers: useOllamaForHelpers,
            useForLiveSoap: useOllamaForLiveSoap,
            useForSessionDetection: useOllamaForSessionDetection,
            useForFinalSoap: true
        )
        
        let autoDetectionConfig = AutoDetectionConfig(
            enabled: autoDetectionEnabled,
            startKeywords: ["what brings you in", "how can i help"],
            endKeywords: ["take care", "goodbye"],
            silenceThresholdSeconds: 30,
            minEncounterDurationSeconds: 60,
            speechActivityThreshold: 0.02,
            bufferDurationSeconds: 10
        )
        
        let timingConfig = TimingConfig(
            transcriptionIntervalSeconds: 10,
            helperUpdateIntervalSeconds: 15,
            soapUpdateIntervalSeconds: 20
        )
        
        config = AppConfig(
            openrouterApiKey: openrouterApiKey,
            deepgramApiKey: deepgramApiKey,
            geminiApiKey: nil,  // Not needed for tests
            model: model,
            timing: timingConfig,
            autoDetection: autoDetectionConfig,
            ollama: ollamaConfig,
            deepgram: deepgramConfig,
            groq: nil  // Not needed for tests
        )
        
        configError = nil
    }
    
    // MARK: - Reset
    
    func reset() {
        config = nil
        configError = nil
    }
}
