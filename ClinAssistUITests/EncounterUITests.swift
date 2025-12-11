import XCTest

/// UI Tests for encounter-related functionality
final class EncounterUITests: XCTestCase {
    
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
    
    // MARK: - Encounter Lifecycle Tests
    
    func testEncounterStartStop() throws {
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        // Find the Start Encounter button
        let startButton = mainWindow.buttons["Start Encounter"]
        let startManuallyButton = mainWindow.buttons["Start Encounter Manually"]
        
        // Click start (either button depending on auto-detection state)
        if startButton.waitForExistence(timeout: 2) {
            startButton.click()
        } else if startManuallyButton.waitForExistence(timeout: 2) {
            startManuallyButton.click()
        } else {
            XCTFail("No start button found")
            return
        }
        
        // Wait for encounter to start
        sleep(1)
        
        // Look for End Encounter button (indicates encounter started)
        let endButton = mainWindow.buttons["End Encounter"]
        
        if endButton.waitForExistence(timeout: 5) {
            // Encounter started successfully
            XCTAssertTrue(endButton.isEnabled)
            
            // Click End Encounter
            endButton.click()
            
            // Wait for processing to complete
            let processingText = mainWindow.staticTexts["Processing..."]
            let finalizingText = mainWindow.staticTexts["Finalizing"]
            
            // Wait up to 30 seconds for SOAP generation
            let timeout: TimeInterval = 30
            let startTime = Date()
            
            while Date().timeIntervalSince(startTime) < timeout {
                if !processingText.exists && !finalizingText.exists {
                    break
                }
                sleep(1)
            }
            
            // Verify end encounter sheet appears
            // This might be a sheet or overlay
        }
    }
    
    func testAutoDetectionToggle() throws {
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        // Look for auto-detection toggle
        let autoDetectToggle = mainWindow.switches["Auto-detect encounters"]
        
        if autoDetectToggle.waitForExistence(timeout: 2) {
            // Get initial state
            let initialValue = autoDetectToggle.value as? String == "1"
            
            // Toggle
            autoDetectToggle.click()
            
            // Verify state changed
            sleep(1)
            let newValue = autoDetectToggle.value as? String == "1"
            XCTAssertNotEqual(initialValue, newValue)
            
            // Toggle back to original state
            autoDetectToggle.click()
        }
    }
    
    // MARK: - Transcript View Tests
    
    func testTranscriptViewExists() throws {
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        // Start an encounter to see transcript view
        let startButton = mainWindow.buttons["Start Encounter"]
        let startManuallyButton = mainWindow.buttons["Start Encounter Manually"]
        
        if startButton.waitForExistence(timeout: 2) {
            startButton.click()
        } else if startManuallyButton.waitForExistence(timeout: 2) {
            startManuallyButton.click()
        }
        
        sleep(2)
        
        // Look for transcript section
        let transcriptHeader = mainWindow.staticTexts["Transcript"]
        XCTAssertTrue(transcriptHeader.waitForExistence(timeout: 5))
        
        // End encounter to clean up
        let endButton = mainWindow.buttons["End Encounter"]
        if endButton.exists {
            endButton.click()
            sleep(5) // Wait for SOAP generation
        }
    }
    
    // MARK: - Clinical Notes Tests
    
    func testClinicalNotesInput() throws {
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        // Start an encounter
        let startButton = mainWindow.buttons["Start Encounter"]
        let startManuallyButton = mainWindow.buttons["Start Encounter Manually"]
        
        if startButton.waitForExistence(timeout: 2) {
            startButton.click()
        } else if startManuallyButton.waitForExistence(timeout: 2) {
            startManuallyButton.click()
        }
        
        sleep(2)
        
        // Look for clinical notes input
        let notesField = mainWindow.textFields.firstMatch
        
        if notesField.waitForExistence(timeout: 5) {
            notesField.click()
            notesField.typeText("BP 120/80")
            
            // Press Enter to add the note
            notesField.typeKey(.return, modifierFlags: [])
            
            sleep(1)
            
            // Verify the note was added (would appear in a list)
        }
        
        // End encounter to clean up
        let endButton = mainWindow.buttons["End Encounter"]
        if endButton.exists {
            endButton.click()
            sleep(5)
        }
    }
    
    // MARK: - Timer Display Tests
    
    func testEncounterTimerDisplay() throws {
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        // Start an encounter
        let startButton = mainWindow.buttons["Start Encounter"]
        let startManuallyButton = mainWindow.buttons["Start Encounter Manually"]
        
        if startButton.waitForExistence(timeout: 2) {
            startButton.click()
        } else if startManuallyButton.waitForExistence(timeout: 2) {
            startManuallyButton.click()
        }
        
        // Wait for timer to appear
        sleep(2)
        
        // Look for timer display (format: 00:00:00)
        // The timer should show something like "00:00:01" or higher
        let timerPattern = mainWindow.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "\\d{2}:\\d{2}:\\d{2}"))
        
        XCTAssertGreaterThan(timerPattern.count, 0, "Timer display should be visible")
        
        // End encounter to clean up
        let endButton = mainWindow.buttons["End Encounter"]
        if endButton.exists {
            endButton.click()
            sleep(5)
        }
    }
}
