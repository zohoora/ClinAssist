import XCTest

/// UI Tests for encounter-related functionality
final class EncounterUITests: XCTestCase {
    
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
    
    // MARK: - Encounter Lifecycle Tests
    
    func testEncounterStartStop() throws {
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        let startEndButton = mainWindow.buttons["startEndEncounterButton"]
        XCTAssertTrue(startEndButton.waitForExistence(timeout: 5))
        startEndButton.click()
        
        // Wait for encounter to start
        Thread.sleep(forTimeInterval: 0.5)
        
        // End encounter
        XCTAssertTrue(startEndButton.waitForExistence(timeout: 2))
        startEndButton.click()
        
        // Verify end encounter sheet appears (Copy/Done buttons)
        let done = mainWindow.buttons["doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.click()
    }
    
    func testAutoDetectionToggle() throws {
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        // Look for auto-detection toggle
        let autoDetectToggle = mainWindow.switches["autoDetectToggle"]
        
        if autoDetectToggle.waitForExistence(timeout: 2) {
            // Get initial state
            let initialValue = autoDetectToggle.value as? String == "1"
            
            // Toggle
            autoDetectToggle.click()
            
            // Verify state changed
            Thread.sleep(forTimeInterval: 0.5)
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
        let startEndButton = mainWindow.buttons["startEndEncounterButton"]
        XCTAssertTrue(startEndButton.waitForExistence(timeout: 5))
        startEndButton.click()
        
        // Look for transcript section
        let transcriptHeader = mainWindow.staticTexts["TRANSCRIPT"]
        XCTAssertTrue(transcriptHeader.waitForExistence(timeout: 5))
        
        // End encounter to clean up
        startEndButton.click()
        let done = mainWindow.buttons["doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.click()
    }
    
    // MARK: - Clinical Notes Tests
    
    func testClinicalNotesInput() throws {
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        // Start an encounter
        let startEndButton = mainWindow.buttons["startEndEncounterButton"]
        XCTAssertTrue(startEndButton.waitForExistence(timeout: 5))
        startEndButton.click()
        
        // Look for clinical notes input
        let notesField = mainWindow.textFields["clinicalNotesTextField"]
        if !notesField.exists {
            // Scroll down to bring notes into view (SwiftUI ScrollView can lazily create content)
            let scroll = mainWindow.scrollViews.firstMatch
            for _ in 0..<5 {
                if notesField.exists { break }
                scroll.swipeUp()
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        XCTAssertTrue(notesField.waitForExistence(timeout: 10))
        notesField.click()
        notesField.typeText("BP 120/80")
        notesField.typeKey(.return, modifierFlags: [])
        
        // End encounter to clean up
        startEndButton.click()
        let done = mainWindow.buttons["doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.click()
    }
    
    // MARK: - Timer Display Tests
    
    func testEncounterTimerDisplay() throws {
        let mainWindow = app.windows["ClinAssist"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        // Start an encounter
        let startEndButton = mainWindow.buttons["startEndEncounterButton"]
        XCTAssertTrue(startEndButton.waitForExistence(timeout: 5))
        startEndButton.click()
        
        // Wait for timer to appear
        Thread.sleep(forTimeInterval: 1.0)
        
        let timer = mainWindow.staticTexts["encounterTimerText"]
        XCTAssertTrue(timer.waitForExistence(timeout: 10), "Timer display should be visible")
        
        // End encounter to clean up
        startEndButton.click()
        let done = mainWindow.buttons["doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.click()
    }
}
