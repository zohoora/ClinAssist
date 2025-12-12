import XCTest
@testable import ClinAssist

@MainActor
final class ConfigManagerSaveTests: XCTestCase {
    
    final class TestConfigManager: ConfigManager {
        var persistedData: Data?
        
        override func persistConfigData(_ data: Data) throws {
            persistedData = data
        }
    }
    
    func testSaveConfigUpdatesInMemoryAndPostsNotification() throws {
        let manager = TestConfigManager(configPath: FileManager.default.temporaryDirectory.appendingPathComponent("config.json"), shouldLoad: false)
        
        let exp = expectation(forNotification: .clinAssistConfigDidChange, object: nil, handler: nil)
        
        let newConfig = AppConfig.default
        try manager.saveConfig(newConfig)
        
        wait(for: [exp], timeout: 1.0)
        
        XCTAssertNotNil(manager.config)
        XCTAssertNil(manager.configError)
        XCTAssertNotNil(manager.persistedData)
        
        // Verify it is valid JSON for AppConfig
        let decoded = try JSONDecoder().decode(AppConfig.self, from: manager.persistedData ?? Data())
        XCTAssertEqual(decoded.model, newConfig.model)
    }
}

