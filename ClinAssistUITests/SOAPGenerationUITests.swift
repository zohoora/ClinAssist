import XCTest

/// UI Tests for SOAP note generation and customization
final class SOAPGenerationUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment["UI_TESTING"] = "1"
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
        let startEndButton = mainWindow.buttons["startEndEncounterButton"]
        XCTAssertTrue(startEndButton.waitForExistence(timeout: 5))
        startEndButton.click()
        Thread.sleep(forTimeInterval: 0.5)
        startEndButton.click()
        
        let copyButton = mainWindow.buttons["copyToClipboardButton"]
        XCTAssertTrue(copyButton.waitForExistence(timeout: 10))
        let doneButton = mainWindow.buttons["doneButton"]
        XCTAssertTrue(doneButton.exists)
        doneButton.click()
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
        let startEndButton = mainWindow.buttons["startEndEncounterButton"]
        XCTAssertTrue(startEndButton.waitForExistence(timeout: 5))
        startEndButton.click()
        Thread.sleep(forTimeInterval: 1.0)
        startEndButton.click()
        
        // Find and click Copy to Clipboard
        let copyButton = mainWindow.buttons["copyToClipboardButton"]
        
        XCTAssertTrue(copyButton.waitForExistence(timeout: 30))
        XCTAssertTrue(copyButton.isEnabled)
        copyButton.click()
        
        // Dismiss sheet
        let doneButton = mainWindow.buttons["doneButton"]
        XCTAssertTrue(doneButton.exists)
        doneButton.click()
    }
    
    func testRegenerateSOAP() throws {
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        let startEndButton = mainWindow.buttons["startEndEncounterButton"]
        XCTAssertTrue(startEndButton.waitForExistence(timeout: 5))
        startEndButton.click()
        Thread.sleep(forTimeInterval: 1.0)
        startEndButton.click()
        
        // Find and click Regenerate button
        let regenerateButton = mainWindow.buttons["regenerateSoapButton"]
        
        XCTAssertTrue(regenerateButton.waitForExistence(timeout: 30))
        XCTAssertTrue(regenerateButton.isEnabled)
        regenerateButton.click()
        
        // Dismiss sheet
        let doneButton = mainWindow.buttons["doneButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 10))
        doneButton.click()
    }
}
