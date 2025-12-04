import Foundation
@testable import ClinAssist

/// Sample transcripts and SOAP notes for testing
enum SampleTranscripts {
    
    // MARK: - Simple Transcripts
    
    static let simpleGreeting: [TranscriptEntry] = [
        TranscriptEntry(timestamp: Date(), speaker: "Physician", text: "Hello, how are you today?"),
        TranscriptEntry(timestamp: Date(), speaker: "Patient", text: "I'm not feeling well, doctor.")
    ]
    
    static let headacheComplaint: [TranscriptEntry] = [
        TranscriptEntry(timestamp: Date(), speaker: "Physician", text: "What brings you in today?"),
        TranscriptEntry(timestamp: Date(), speaker: "Patient", text: "I've had a terrible headache for the past three days."),
        TranscriptEntry(timestamp: Date(), speaker: "Physician", text: "Can you describe the headache? Where exactly does it hurt?"),
        TranscriptEntry(timestamp: Date(), speaker: "Patient", text: "It's mostly on the right side, kind of throbbing."),
        TranscriptEntry(timestamp: Date(), speaker: "Physician", text: "On a scale of 1 to 10, how would you rate the pain?"),
        TranscriptEntry(timestamp: Date(), speaker: "Patient", text: "About a 7. It gets worse in bright light.")
    ]
    
    // MARK: - Transcript Segments
    
    static let simpleSegments: [TranscriptSegment] = [
        TranscriptSegment(speaker: "Physician", text: "Hello, how can I help you today?"),
        TranscriptSegment(speaker: "Patient", text: "I have a sore throat and fever.")
    ]
    
    static let multiSpeakerSegments: [TranscriptSegment] = [
        TranscriptSegment(speaker: "Physician", text: "Good morning, please have a seat."),
        TranscriptSegment(speaker: "Patient", text: "Thank you, doctor."),
        TranscriptSegment(speaker: "Physician", text: "What brings you in today?"),
        TranscriptSegment(speaker: "Patient", text: "I've been having chest pain."),
        TranscriptSegment(speaker: "Other", text: "Should I step out?"),
        TranscriptSegment(speaker: "Patient", text: "No, it's okay, this is my spouse.")
    ]
    
    // MARK: - SOAP Notes
    
    static let soapNote = """
    # SOAP Note
    
    ## Subjective
    - Chief complaint: Headache for 3 days
    - Location: Right-sided, throbbing
    - Severity: 7/10
    - Aggravating factors: Bright light (photophobia)
    - No nausea or vomiting reported
    
    ## Objective
    - Patient appears uncomfortable but alert
    - Vital signs pending
    
    ## Assessment
    - Primary: Migraine headache
    - Differential: Tension headache, cluster headache
    
    ## Plan
    1. Ibuprofen 600mg PO TID with food
    2. Rest in dark, quiet room
    3. Follow up in 1 week if no improvement
    4. Return immediately if fever, stiff neck, or worsening symptoms
    """
    
    static let minimalSoapNote = """
    # SOAP Note
    
    ## Subjective
    - Chief complaint: Follow-up visit
    
    ## Objective
    - Stable condition
    
    ## Assessment
    - Chronic condition stable
    
    ## Plan
    - Continue current medications
    """
    
    // MARK: - Helper Suggestions
    
    static let helperSuggestionsJSON = """
    {
        "ddx": ["Migraine", "Tension headache", "Cluster headache"],
        "red_flags": ["Sudden severe headache", "Fever with headache", "Stiff neck"],
        "suggested_questions": [
            "Have you had any visual changes?",
            "Any nausea or vomiting?",
            "Family history of migraines?"
        ],
        "issues": [
            {"label": "Headache for 3 days", "addressed_in_plan": false, "first_mentioned_at": "2024-01-01T10:00:00Z"},
            {"label": "Photophobia", "addressed_in_plan": false, "first_mentioned_at": "2024-01-01T10:05:00Z"}
        ],
        "drug_cards": [
            {
                "name": "Ibuprofen",
                "class": "NSAID",
                "typical_adult_dose": "400-600mg TID",
                "key_cautions": ["GI bleeding", "Renal impairment", "Cardiovascular risk"]
            }
        ]
    }
    """
    
    // MARK: - Clinical Notes
    
    static let clinicalNotes: [ClinicalNote] = [
        ClinicalNote(text: "BP 120/80"),
        ClinicalNote(text: "HR 72 regular"),
        ClinicalNote(text: "Temp 98.6F"),
        ClinicalNote(text: "No acute distress")
    ]
    
    // MARK: - Complete Encounter State
    
    static func createSampleEncounterState() -> EncounterState {
        var state = EncounterState(id: UUID())
        
        for entry in headacheComplaint {
            state.transcript.append(entry)
        }
        
        for note in clinicalNotes {
            state.clinicalNotes.append(note)
        }
        
        return state
    }
}
