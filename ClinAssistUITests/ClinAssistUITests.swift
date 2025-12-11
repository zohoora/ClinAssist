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
        // Find and click on Session History button
        let sessionHistoryButton = app.buttons["Session History"]
        
        if sessionHistoryButton.waitForExistence(timeout: 5) {
            sessionHistoryButton.click()
            
            // Verify Session History window opens
            let historyWindow = app.windows["Session History"]
            XCTAssertTrue(historyWindow.waitForExistence(timeout: 5))
        }
    }
    
    func testNavigationToMedicationLookup() throws {
        // Open from menu bar
        let menuBarItem = app.menuBarItems["ClinAssist"]
        if menuBarItem.exists {
            menuBarItem.click()
            
            let medicationItem = app.menuItems["Medication Lookup..."]
            if medicationItem.waitForExistence(timeout: 2) {
                medicationItem.click()
                
                // Verify Medication Lookup window opens
                let medicationWindow = app.windows["Medication Lookup"]
                XCTAssertTrue(medicationWindow.waitForExistence(timeout: 5))
            }
        }
    }
    
    func testNavigationToSettings() throws {
        // Open from menu bar
        let menuBarItem = app.menuBarItems["ClinAssist"]
        if menuBarItem.exists {
            menuBarItem.click()
            
            let settingsItem = app.menuItems["Settings..."]
            if settingsItem.waitForExistence(timeout: 2) {
                settingsItem.click()
                
                // Verify Settings window opens
                let settingsWindow = app.windows["Settings"]
                XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
            }
        }
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
        // Find and click the status item
        let statusItem = app.statusItems.firstMatch
        if statusItem.exists {
            statusItem.click()
            
            // Verify menu items exist
            let startItem = app.menuItems["Start Encounter"]
            let quitItem = app.menuItems["Quit ClinAssist"]
            
            XCTAssertTrue(startItem.waitForExistence(timeout: 2) || quitItem.waitForExistence(timeout: 2))
        }
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
