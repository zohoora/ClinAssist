import Foundation

struct EncounterState: Codable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var transcript: [TranscriptEntry]
    var problems: [Problem]
    var issuesMentioned: [Issue]
    var medicationsMentioned: [MedicationMention]
    var clinicalNotes: [ClinicalNote]  // Manual notes entered during encounter
    
    init(id: UUID = UUID(), startedAt: Date = Date()) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = nil
        self.transcript = []
        self.problems = []
        self.issuesMentioned = []
        self.medicationsMentioned = []
        self.clinicalNotes = []
    }
}

struct ClinicalNote: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let text: String
    
    init(text: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.timestamp = timestamp
        self.text = text
    }
}

struct TranscriptEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let speaker: String
    let text: String
    
    init(timestamp: Date = Date(), speaker: String, text: String) {
        self.id = UUID()
        self.timestamp = timestamp
        self.speaker = speaker
        self.text = text
    }
    
    var speakerColor: String {
        switch speaker {
        case "Physician":
            return "blue"
        case "Patient":
            return "green"
        default:
            return "gray"
        }
    }
}

struct Problem: Codable, Identifiable {
    let id: UUID
    var name: String
    var subjective: [String]
    var objective: [String]
    var assessment: [String]
    var plan: [String]
    var status: String  // "active", "resolved"
    
    init(name: String, status: String = "active") {
        self.id = UUID()
        self.name = name
        self.subjective = []
        self.objective = []
        self.assessment = []
        self.plan = []
        self.status = status
    }
}

struct Issue: Codable, Identifiable {
    let id: UUID
    var label: String
    var firstMentionedAt: Date
    var addressedInPlan: Bool
    
    init(label: String, firstMentionedAt: Date = Date(), addressedInPlan: Bool = false) {
        self.id = UUID()
        self.label = label
        self.firstMentionedAt = firstMentionedAt
        self.addressedInPlan = addressedInPlan
    }
}

struct MedicationMention: Codable, Identifiable {
    let id: UUID
    var name: String
    var context: String  // snippet from transcript
    
    init(name: String, context: String) {
        self.id = UUID()
        self.name = name
        self.context = context
    }
}

// MARK: - Helper Suggestions

struct HelperSuggestions: Codable {
    var ddx: [String]
    var redFlags: [String]
    var suggestedQuestions: [String]
    var drugCards: [DrugCard]
    var issues: [IssueFromLLM]
    
    enum CodingKeys: String, CodingKey {
        case ddx
        case redFlags = "red_flags"
        case suggestedQuestions = "suggested_questions"
        case drugCards = "drug_cards"
        case issues
    }
    
    init() {
        self.ddx = []
        self.redFlags = []
        self.suggestedQuestions = []
        self.drugCards = []
        self.issues = []
    }
}

struct IssueFromLLM: Codable, Identifiable {
    var id: UUID { UUID() }
    var label: String
    var addressedInPlan: Bool
    
    enum CodingKeys: String, CodingKey {
        case label
        case addressedInPlan = "addressed_in_plan"
    }
}

struct DrugCard: Codable, Identifiable {
    let id: UUID
    var name: String
    var drugClass: String
    var typicalAdultDose: String
    var keyCautions: [String]
    
    enum CodingKeys: String, CodingKey {
        case name
        case drugClass = "class"
        case typicalAdultDose = "typical_adult_dose"
        case keyCautions = "key_cautions"
    }
    
    init(name: String, drugClass: String, typicalAdultDose: String, keyCautions: [String]) {
        self.id = UUID()
        self.name = name
        self.drugClass = drugClass
        self.typicalAdultDose = typicalAdultDose
        self.keyCautions = keyCautions
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.drugClass = try container.decode(String.self, forKey: .drugClass)
        self.typicalAdultDose = try container.decode(String.self, forKey: .typicalAdultDose)
        self.keyCautions = try container.decode([String].self, forKey: .keyCautions)
    }
}

