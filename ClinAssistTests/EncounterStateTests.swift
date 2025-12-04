import XCTest
@testable import ClinAssist

@MainActor
final class EncounterStateTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testEncounterStateInitialization() {
        let id = UUID()
        let state = EncounterState(id: id)
        
        XCTAssertEqual(state.id, id)
        XCTAssertNotNil(state.startedAt)
        XCTAssertNil(state.endedAt)
        XCTAssertTrue(state.transcript.isEmpty)
        XCTAssertTrue(state.clinicalNotes.isEmpty)
    }
    
    // MARK: - Transcript Tests
    
    func testAddingTranscriptEntries() {
        var state = EncounterState(id: UUID())
        
        let entry1 = TranscriptEntry(timestamp: Date(), speaker: "Physician", text: "How are you feeling?")
        let entry2 = TranscriptEntry(timestamp: Date(), speaker: "Patient", text: "I have a headache.")
        
        state.transcript.append(entry1)
        state.transcript.append(entry2)
        
        XCTAssertEqual(state.transcript.count, 2)
        XCTAssertEqual(state.transcript[0].speaker, "Physician")
        XCTAssertEqual(state.transcript[1].text, "I have a headache.")
    }
    
    func testTranscriptEntrySpeakerMapping() {
        let physicianEntry = TranscriptEntry(timestamp: Date(), speaker: "Physician", text: "Hello")
        let patientEntry = TranscriptEntry(timestamp: Date(), speaker: "Patient", text: "Hi")
        let otherEntry = TranscriptEntry(timestamp: Date(), speaker: "Other", text: "Hello there")
        
        XCTAssertEqual(physicianEntry.speaker, "Physician")
        XCTAssertEqual(patientEntry.speaker, "Patient")
        XCTAssertEqual(otherEntry.speaker, "Other")
    }
    
    func testTranscriptEntrySpeakerColors() {
        let physicianEntry = TranscriptEntry(timestamp: Date(), speaker: "Physician", text: "Hello")
        let patientEntry = TranscriptEntry(timestamp: Date(), speaker: "Patient", text: "Hi")
        let otherEntry = TranscriptEntry(timestamp: Date(), speaker: "Unknown", text: "Hello")
        
        XCTAssertEqual(physicianEntry.speakerColor, "blue")
        XCTAssertEqual(patientEntry.speakerColor, "green")
        XCTAssertEqual(otherEntry.speakerColor, "gray")
    }
    
    // MARK: - Clinical Notes Tests
    
    func testAddingClinicalNotes() {
        var state = EncounterState(id: UUID())
        
        let note1 = ClinicalNote(text: "BP 120/80")
        let note2 = ClinicalNote(text: "Heart rate regular")
        
        state.clinicalNotes.append(note1)
        state.clinicalNotes.append(note2)
        
        XCTAssertEqual(state.clinicalNotes.count, 2)
        XCTAssertEqual(state.clinicalNotes[0].text, "BP 120/80")
    }
    
    func testClinicalNoteTimestamp() {
        let note = ClinicalNote(text: "Test note")
        
        XCTAssertNotNil(note.timestamp)
        // Timestamp should be recent (within last second)
        XCTAssertLessThan(Date().timeIntervalSince(note.timestamp), 1.0)
    }
    
    // MARK: - Encoding/Decoding Tests
    
    func testEncounterStateEncodeDecode() throws {
        var state = EncounterState(id: UUID())
        state.transcript.append(TranscriptEntry(timestamp: Date(), speaker: "Physician", text: "Hello"))
        state.clinicalNotes.append(ClinicalNote(text: "BP normal"))
        state.endedAt = Date()
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EncounterState.self, from: data)
        
        XCTAssertEqual(decoded.id, state.id)
        XCTAssertEqual(decoded.transcript.count, 1)
        XCTAssertEqual(decoded.clinicalNotes.count, 1)
        XCTAssertNotNil(decoded.endedAt)
    }
    
    func testTranscriptEntryEncodeDecode() throws {
        let entry = TranscriptEntry(timestamp: Date(), speaker: "Patient", text: "I feel better")
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(entry)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TranscriptEntry.self, from: data)
        
        XCTAssertEqual(decoded.speaker, "Patient")
        XCTAssertEqual(decoded.text, "I feel better")
    }
    
    func testClinicalNoteEncodeDecode() throws {
        let note = ClinicalNote(text: "Performed lumbar puncture")
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(note)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ClinicalNote.self, from: data)
        
        XCTAssertEqual(decoded.text, "Performed lumbar puncture")
        XCTAssertNotNil(decoded.timestamp)
    }
    
    // MARK: - Duration Tests
    
    func testDurationCalculation() {
        var state = EncounterState(id: UUID())
        
        // Set startedAt to 5 minutes ago
        state.startedAt = Date().addingTimeInterval(-300)
        state.endedAt = Date()
        
        let duration = state.endedAt!.timeIntervalSince(state.startedAt)
        
        XCTAssertEqual(duration, 300, accuracy: 1.0)
    }
    
    // MARK: - Empty State Tests
    
    func testEmptyTranscriptIsEncodable() throws {
        let state = EncounterState(id: UUID())
        
        let encoder = JSONEncoder()
        XCTAssertNoThrow(try encoder.encode(state))
    }
    
    // MARK: - Problem Tests
    
    func testProblemInitialization() {
        let problem = Problem(name: "Hypertension")
        
        XCTAssertEqual(problem.name, "Hypertension")
        XCTAssertEqual(problem.status, "active")
        XCTAssertTrue(problem.subjective.isEmpty)
        XCTAssertTrue(problem.objective.isEmpty)
        XCTAssertTrue(problem.assessment.isEmpty)
        XCTAssertTrue(problem.plan.isEmpty)
    }
    
    // MARK: - Issue Tests
    
    func testIssueInitialization() {
        let issue = Issue(label: "Chest pain")
        
        XCTAssertEqual(issue.label, "Chest pain")
        XCTAssertFalse(issue.addressedInPlan)
        XCTAssertNotNil(issue.firstMentionedAt)
    }
}

// MARK: - HelperSuggestions Tests

@MainActor
final class HelperSuggestionsTests: XCTestCase {
    
    func testHelperSuggestionsInitialization() {
        let suggestions = HelperSuggestions()
        
        XCTAssertTrue(suggestions.ddx.isEmpty)
        XCTAssertTrue(suggestions.issues.isEmpty)
        XCTAssertTrue(suggestions.drugCards.isEmpty)
        XCTAssertTrue(suggestions.redFlags.isEmpty)
        XCTAssertTrue(suggestions.suggestedQuestions.isEmpty)
    }
    
    func testHelperSuggestionsDecoding() throws {
        let json = """
        {
            "ddx": ["Migraine", "Tension headache"],
            "red_flags": ["Sudden onset"],
            "suggested_questions": ["How long have you had the headache?"],
            "issues": [
                {"label": "Headache for 3 days", "addressed_in_plan": false}
            ],
            "drug_cards": [
                {"name": "Ibuprofen", "class": "NSAID", "typical_adult_dose": "400mg TID", "key_cautions": ["GI bleeding"]}
            ]
        }
        """
        
        let data = json.data(using: .utf8)!
        let suggestions = try JSONDecoder().decode(HelperSuggestions.self, from: data)
        
        XCTAssertEqual(suggestions.ddx.count, 2)
        XCTAssertEqual(suggestions.ddx[0], "Migraine")
        
        XCTAssertEqual(suggestions.issues.count, 1)
        XCTAssertEqual(suggestions.issues[0].label, "Headache for 3 days")
        XCTAssertFalse(suggestions.issues[0].addressedInPlan)
        
        XCTAssertEqual(suggestions.drugCards.count, 1)
        XCTAssertEqual(suggestions.drugCards[0].name, "Ibuprofen")
        XCTAssertEqual(suggestions.drugCards[0].drugClass, "NSAID")
    }
    
    func testIssueAddressedState() throws {
        let json = """
        {
            "ddx": [],
            "red_flags": [],
            "suggested_questions": [],
            "issues": [
                {"label": "Pain", "addressed_in_plan": true},
                {"label": "Fatigue", "addressed_in_plan": false}
            ],
            "drug_cards": []
        }
        """
        
        let data = json.data(using: .utf8)!
        let suggestions = try JSONDecoder().decode(HelperSuggestions.self, from: data)
        
        XCTAssertTrue(suggestions.issues[0].addressedInPlan)
        XCTAssertFalse(suggestions.issues[1].addressedInPlan)
    }
    
    func testDrugCardFields() throws {
        let json = """
        {
            "ddx": [],
            "red_flags": [],
            "suggested_questions": [],
            "issues": [],
            "drug_cards": [
                {"name": "Aspirin", "class": "Antiplatelet", "typical_adult_dose": "81mg daily", "key_cautions": ["Bleeding risk", "Allergy"]}
            ]
        }
        """
        
        let data = json.data(using: .utf8)!
        let suggestions = try JSONDecoder().decode(HelperSuggestions.self, from: data)
        
        XCTAssertEqual(suggestions.drugCards[0].name, "Aspirin")
        XCTAssertEqual(suggestions.drugCards[0].drugClass, "Antiplatelet")
        XCTAssertEqual(suggestions.drugCards[0].typicalAdultDose, "81mg daily")
        XCTAssertEqual(suggestions.drugCards[0].keyCautions.count, 2)
    }
    
    func testEmptyHelperSuggestionsDecoding() throws {
        let json = """
        {
            "ddx": [],
            "red_flags": [],
            "suggested_questions": [],
            "issues": [],
            "drug_cards": []
        }
        """
        
        let data = json.data(using: .utf8)!
        let suggestions = try JSONDecoder().decode(HelperSuggestions.self, from: data)
        
        XCTAssertTrue(suggestions.ddx.isEmpty)
        XCTAssertTrue(suggestions.issues.isEmpty)
        XCTAssertTrue(suggestions.drugCards.isEmpty)
    }
}
