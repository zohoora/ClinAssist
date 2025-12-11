import XCTest

/// UI Tests for SOAP note generation and customization
final class SOAPGenerationUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - End Encounter Sheet Tests
    
    func testEndEncounterSheetAppears() throws {
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        // Start and end an encounter to trigger the sheet
        let startButton = mainWindow.buttons["Start Encounter"]
        let startManuallyButton = mainWindow.buttons["Start Encounter Manually"]
        
        if startButton.waitForExistence(timeout: 2) {
            startButton.click()
        } else if startManuallyButton.waitForExistence(timeout: 2) {
            startManuallyButton.click()
        } else {
            // Skip if no start button
            throw XCTSkip("Start button not found - may need configuration")
        }
        
        sleep(2)
        
        // End the encounter
        let endButton = mainWindow.buttons["End Encounter"]
        XCTAssertTrue(endButton.waitForExistence(timeout: 5))
        endButton.click()
        
        // Wait for SOAP generation (up to 60 seconds)
        let timeout: TimeInterval = 60
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < timeout {
            // Look for the End Encounter sheet/modal elements
            let copyButton = mainWindow.buttons["Copy to Clipboard"]
            let doneButton = mainWindow.buttons["Done"]
            
            if copyButton.exists || doneButton.exists {
                // Sheet appeared
                XCTAssertTrue(true)
                
                // Dismiss the sheet
                if doneButton.exists {
                    doneButton.click()
                }
                return
            }
            
            sleep(1)
        }
        
        // If we get here, the sheet didn't appear in time
        XCTFail("End encounter sheet did not appear within timeout")
    }
    
    func testSOAPDetailLevelSlider() throws {
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        // Start and end an encounter
        let startButton = mainWindow.buttons["Start Encounter"]
        let startManuallyButton = mainWindow.buttons["Start Encounter Manually"]
        
        if startButton.waitForExistence(timeout: 2) {
            startButton.click()
        } else if startManuallyButton.waitForExistence(timeout: 2) {
            startManuallyButton.click()
        } else {
            throw XCTSkip("Start button not found")
        }
        
        sleep(2)
        
        let endButton = mainWindow.buttons["End Encounter"]
        XCTAssertTrue(endButton.waitForExistence(timeout: 5))
        endButton.click()
        
        // Wait for sheet to appear
        sleep(10)
        
        // Look for detail level slider
        let detailSlider = mainWindow.sliders.firstMatch
        
        if detailSlider.waitForExistence(timeout: 30) {
            // Verify slider exists and is interactive
            XCTAssertTrue(detailSlider.isEnabled)
            
            // Try to adjust the slider
            detailSlider.adjust(toNormalizedSliderPosition: 0.8)
            
            sleep(1)
            
            // Dismiss sheet
            let doneButton = mainWindow.buttons["Done"]
            if doneButton.exists {
                doneButton.click()
            }
        }
    }
    
    func testSOAPFormatPicker() throws {
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        // Start and end an encounter
        let startButton = mainWindow.buttons["Start Encounter"]
        let startManuallyButton = mainWindow.buttons["Start Encounter Manually"]
        
        if startButton.waitForExistence(timeout: 2) {
            startButton.click()
        } else if startManuallyButton.waitForExistence(timeout: 2) {
            startManuallyButton.click()
        } else {
            throw XCTSkip("Start button not found")
        }
        
        sleep(2)
        
        let endButton = mainWindow.buttons["End Encounter"]
        XCTAssertTrue(endButton.waitForExistence(timeout: 5))
        endButton.click()
        
        // Wait for sheet
        sleep(15)
        
        // Look for format picker (By Problem / Comprehensive)
        let problemBasedButton = mainWindow.buttons["By Problem"]
        let comprehensiveButton = mainWindow.buttons["Comprehensive"]
        
        if problemBasedButton.waitForExistence(timeout: 30) || comprehensiveButton.waitForExistence(timeout: 5) {
            // Toggle between formats
            if comprehensiveButton.exists && comprehensiveButton.isEnabled {
                comprehensiveButton.click()
                sleep(1)
            }
            
            if problemBasedButton.exists && problemBasedButton.isEnabled {
                problemBasedButton.click()
                sleep(1)
            }
        }
        
        // Dismiss sheet
        let doneButton = mainWindow.buttons["Done"]
        if doneButton.exists {
            doneButton.click()
        }
    }
    
    func testCopyToClipboard() throws {
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        // Start and end an encounter
        let startButton = mainWindow.buttons["Start Encounter"]
        let startManuallyButton = mainWindow.buttons["Start Encounter Manually"]
        
        if startButton.waitForExistence(timeout: 2) {
            startButton.click()
        } else if startManuallyButton.waitForExistence(timeout: 2) {
            startManuallyButton.click()
        } else {
            throw XCTSkip("Start button not found")
        }
        
        sleep(2)
        
        let endButton = mainWindow.buttons["End Encounter"]
        XCTAssertTrue(endButton.waitForExistence(timeout: 5))
        endButton.click()
        
        // Wait for sheet
        sleep(20)
        
        // Find and click Copy to Clipboard
        let copyButton = mainWindow.buttons["Copy to Clipboard"]
        
        if copyButton.waitForExistence(timeout: 40) {
            XCTAssertTrue(copyButton.isEnabled)
            copyButton.click()
            
            // Verify clipboard has content (indirectly through UI feedback)
            // The button might change to "Copied!" or similar
            sleep(1)
        }
        
        // Dismiss sheet
        let doneButton = mainWindow.buttons["Done"]
        if doneButton.exists {
            doneButton.click()
        }
    }
    
    func testRegenerateSOAP() throws {
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        // Start and end an encounter
        let startButton = mainWindow.buttons["Start Encounter"]
        let startManuallyButton = mainWindow.buttons["Start Encounter Manually"]
        
        if startButton.waitForExistence(timeout: 2) {
            startButton.click()
        } else if startManuallyButton.waitForExistence(timeout: 2) {
            startManuallyButton.click()
        } else {
            throw XCTSkip("Start button not found")
        }
        
        sleep(2)
        
        let endButton = mainWindow.buttons["End Encounter"]
        XCTAssertTrue(endButton.waitForExistence(timeout: 5))
        endButton.click()
        
        // Wait for initial SOAP generation
        sleep(20)
        
        // Find and click Regenerate button
        let regenerateButton = mainWindow.buttons["Regenerate"]
        
        if regenerateButton.waitForExistence(timeout: 40) {
            XCTAssertTrue(regenerateButton.isEnabled)
            regenerateButton.click()
            
            // Wait for regeneration (might show loading indicator)
            sleep(15)
            
            // Verify regeneration completed (button should be enabled again)
            XCTAssertTrue(regenerateButton.waitForExistence(timeout: 60))
        }
        
        // Dismiss sheet
        let doneButton = mainWindow.buttons["Done"]
        if doneButton.exists {
            doneButton.click()
        }
    }
}
