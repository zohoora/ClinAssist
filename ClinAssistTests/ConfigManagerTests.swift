import XCTest
@testable import ClinAssist

@MainActor
final class ConfigManagerTests: XCTestCase {
    
    var tempConfigURL: URL!
    
    override func setUpWithError() throws {
        // Create a temp directory for test configs
        tempConfigURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClinAssistTests")
            .appendingPathComponent("config.json")
        
        try FileManager.default.createDirectory(
            at: tempConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
    
    override func tearDownWithError() throws {
        // Clean up temp files
        try? FileManager.default.removeItem(at: tempConfigURL.deletingLastPathComponent())
    }
    
    // MARK: - Valid Config Tests
    
    func testValidConfigParsesCorrectly() throws {
        let validConfig = """
        {
          "openrouter_api_key": "sk-test-key",
          "deepgram_api_key": "dg-test-key",
          "model": "anthropic/claude-haiku-4.5",
          "timing": {
            "transcription_interval_seconds": 10,
            "helper_update_interval_seconds": 10,
            "soap_update_interval_seconds": 15
          }
        }
        """
        
        let data = validConfig.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        
        XCTAssertEqual(config.openrouterApiKey, "sk-test-key")
        XCTAssertEqual(config.deepgramApiKey, "dg-test-key")
        XCTAssertEqual(config.model, "anthropic/claude-haiku-4.5")
        XCTAssertEqual(config.timing.transcriptionIntervalSeconds, 10)
        XCTAssertEqual(config.timing.helperUpdateIntervalSeconds, 10)
        XCTAssertEqual(config.timing.soapUpdateIntervalSeconds, 15)
    }
    
    func testConfigWithOllamaParsesCorrectly() throws {
        let configWithOllama = """
        {
          "openrouter_api_key": "sk-test-key",
          "deepgram_api_key": "dg-test-key",
          "model": "anthropic/claude-haiku-4.5",
          "timing": {
            "transcription_interval_seconds": 10,
            "helper_update_interval_seconds": 10,
            "soap_update_interval_seconds": 15
          },
          "ollama": {
            "enabled": true,
            "base_url": "http://localhost:11434",
            "model": "qwen3:8b",
            "use_for_helpers": true,
            "use_for_live_soap": true,
            "use_for_session_detection": true
          }
        }
        """
        
        let data = configWithOllama.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        
        XCTAssertNotNil(config.ollama)
        XCTAssertTrue(config.ollama!.enabled)
        XCTAssertEqual(config.ollama!.baseUrl, "http://localhost:11434")
        XCTAssertEqual(config.ollama!.model, "qwen3:8b")
        XCTAssertTrue(config.ollama!.useForHelpers ?? false)
        XCTAssertTrue(config.ollama!.useForLiveSoap ?? false)
        XCTAssertTrue(config.ollama!.useForSessionDetection ?? false)
    }
    
    func testConfigWithAutoDetectionParsesCorrectly() throws {
        let configWithAutoDetection = """
        {
          "openrouter_api_key": "sk-test-key",
          "deepgram_api_key": "dg-test-key",
          "model": "anthropic/claude-haiku-4.5",
          "timing": {
            "transcription_interval_seconds": 10,
            "helper_update_interval_seconds": 10,
            "soap_update_interval_seconds": 15
          },
          "auto_detection": {
            "enabled": true,
            "detect_end_of_encounter": true,
            "silence_threshold_seconds": 45,
            "min_encounter_duration_seconds": 60
          }
        }
        """
        
        let data = configWithAutoDetection.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        
        XCTAssertNotNil(config.autoDetection)
        XCTAssertTrue(config.autoDetection!.enabled)
        XCTAssertEqual(config.autoDetection!.detectEndOfEncounter, true)
        XCTAssertEqual(config.autoDetection!.silenceThresholdSeconds, 45)
    }
    
    // MARK: - Missing Fields Tests
    
    func testConfigWithMissingOptionalFieldsUsesDefaults() throws {
        let minimalConfig = """
        {
          "openrouter_api_key": "sk-test-key",
          "deepgram_api_key": "dg-test-key",
          "model": "gpt-4",
          "timing": {
            "transcription_interval_seconds": 10,
            "helper_update_interval_seconds": 20,
            "soap_update_interval_seconds": 30
          }
        }
        """
        
        let data = minimalConfig.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        
        // Optional fields should be nil
        XCTAssertNil(config.autoDetection)
        XCTAssertNil(config.ollama)
    }
    
    // MARK: - Invalid Config Tests
    
    func testInvalidJSONThrowsError() {
        let invalidJSON = "{ this is not valid json }"
        let data = invalidJSON.data(using: .utf8)!
        
        XCTAssertThrowsError(try JSONDecoder().decode(AppConfig.self, from: data))
    }
    
    func testMissingRequiredFieldThrowsError() {
        let missingApiKey = """
        {
          "deepgram_api_key": "dg-test-key",
          "model": "gpt-4",
          "timing": {
            "transcription_interval_seconds": 10,
            "helper_update_interval_seconds": 20,
            "soap_update_interval_seconds": 30
          }
        }
        """
        
        let data = missingApiKey.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(AppConfig.self, from: data))
    }
    
    // MARK: - TimingConfig Tests
    
    func testTimingConfigDefaults() {
        let defaults = TimingConfig.default
        
        XCTAssertEqual(defaults.transcriptionIntervalSeconds, 10)
        XCTAssertEqual(defaults.helperUpdateIntervalSeconds, 20)
        XCTAssertEqual(defaults.soapUpdateIntervalSeconds, 30)
    }
    
    // MARK: - OllamaConfig Tests
    
    func testOllamaConfigDefaults() {
        let defaults = OllamaConfig.default
        
        XCTAssertTrue(defaults.enabled)
        XCTAssertEqual(defaults.baseUrl, "http://localhost:11434")
        XCTAssertEqual(defaults.model, "qwen3:8b")
        XCTAssertTrue(defaults.useForHelpers ?? false)
        XCTAssertTrue(defaults.useForLiveSoap ?? false)
        XCTAssertTrue(defaults.useForSessionDetection ?? false)
    }
}
