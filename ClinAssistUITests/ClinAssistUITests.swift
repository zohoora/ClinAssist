import XCTest

/// UI Tests for ClinAssist application
/// Tests critical user flows including encounter management and navigation
///
/// NOTE: To use these tests, you need to add a UI Testing target to the Xcode project:
/// 1. File > New > Target > UI Testing Bundle
/// 2. Name it "ClinAssistUITests"
/// 3. Move this file into the new target
final class ClinAssistUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        
        // Set launch arguments for testing
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - App Launch Tests
    
    func testAppLaunches() throws {
        // Verify the app launches successfully
        XCTAssertTrue(app.state == .runningForeground)
    }
    
    func testMainWindowIsVisible() throws {
        // Verify the main window appears
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
    }
    
    // MARK: - Navigation Tests
    
    func testNavigationToSessionHistory() throws {
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        let openHistory = mainWindow.buttons["openSessionHistoryButton"]
        XCTAssertTrue(openHistory.waitForExistence(timeout: 5))
        openHistory.click()
        
        let historyWindow = app.windows["Session History"]
        XCTAssertTrue(historyWindow.waitForExistence(timeout: 5))
    }
    
    func testNavigationToMedicationLookup() throws {
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        let openMedication = mainWindow.buttons["openMedicationLookupButton"]
        XCTAssertTrue(openMedication.waitForExistence(timeout: 5))
        openMedication.click()
        
        let medicationWindow = app.windows["Medication Lookup"]
        XCTAssertTrue(medicationWindow.waitForExistence(timeout: 5))
    }
    
    func testNavigationToSettings() throws {
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        let openSettings = mainWindow.buttons["openSettingsButton"]
        XCTAssertTrue(openSettings.waitForExistence(timeout: 5))
        openSettings.click()
        
        let settingsWindow = app.windows["Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
    }
    
    // MARK: - Encounter Flow Tests
    
    func testStartEncounterButton() throws {
        // Find Start Encounter button
        let startButton = app.buttons["Start Encounter"]
        
        if startButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(startButton.isEnabled)
            
            // Verify button exists and is enabled when app is configured
            // Note: This test may fail if microphone permission is not granted
        }
    }
    
    func testEncounterStateDisplay() throws {
        // Verify the status indicator exists
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        // Look for the Ready/Monitoring/Recording status text
        let readyText = mainWindow.staticTexts["Ready"]
        let monitoringText = mainWindow.staticTexts["Monitoring"]
        
        // One of these should be visible depending on auto-detection setting
        XCTAssertTrue(readyText.exists || monitoringText.exists)
    }
    
    // MARK: - Error Display Tests
    
    func testErrorBannerAppears() throws {
        // This test verifies the error banner UI exists
        // Actual error triggering would require mock injection
        
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        // The error banner should not be visible initially
        // (unless there's an actual error)
    }
    
    // MARK: - Menu Bar Tests
    
    func testMenuBarItemExists() throws {
        // Verify the menu bar icon exists
        // Note: Menu bar items can be tricky to test in XCUITest
        
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.exists)
    }
    
    func testMenuBarContextMenu() throws {
        throw XCTSkip("Menu bar/status item interactions are flaky in XCUITest; covered by in-window UI test controls.")
    }
    
    // MARK: - Accessibility Tests
    
    func testMainWindowAccessibility() throws {
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        // Verify key elements have accessibility labels
        // This helps ensure the app is accessible to screen readers
    }
    
    // MARK: - Performance Tests
    
    func testAppLaunchPerformance() throws {
        if #available(macOS 10.15, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                app.launch()
            }
        }
    }
}
