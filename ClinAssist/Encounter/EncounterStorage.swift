import Foundation

class EncounterStorage {
    static let shared = EncounterStorage()
    
    private let basePath: URL
    
    init() {
        basePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("ClinAssist")
        
        // Ensure directories exist
        try? FileManager.default.createDirectory(
            at: basePath.appendingPathComponent("encounters"),
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: basePath.appendingPathComponent("temp"),
            withIntermediateDirectories: true
        )
    }
    
    // MARK: - Save Encounter
    
    func saveEncounter(_ state: EncounterState, soapNote: String, keepAudio: Bool = false) throws -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let folderName = dateFormatter.string(from: state.startedAt)
        
        let encounterPath = basePath
            .appendingPathComponent("encounters")
            .appendingPathComponent(folderName)
        
        try FileManager.default.createDirectory(at: encounterPath, withIntermediateDirectories: true)
        
        // Save encounter.json
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let encounterJSON = try encoder.encode(state)
        try encounterJSON.write(to: encounterPath.appendingPathComponent("encounter.json"))
        
        // Save transcript.txt
        let transcriptText = state.transcript
            .map { "[\(formatTimestamp($0.timestamp))] \($0.speaker): \($0.text)" }
            .joined(separator: "\n\n")
        try transcriptText.write(
            to: encounterPath.appendingPathComponent("transcript.txt"),
            atomically: true,
            encoding: .utf8
        )
        
        // Save soap_note.txt
        try soapNote.write(
            to: encounterPath.appendingPathComponent("soap_note.txt"),
            atomically: true,
            encoding: .utf8
        )
        
        // Handle audio files
        let tempAudioPath = basePath
            .appendingPathComponent("temp")
            .appendingPathComponent(state.id.uuidString)
        
        if keepAudio {
            let audioDestPath = encounterPath.appendingPathComponent("audio")
            try? FileManager.default.moveItem(at: tempAudioPath, to: audioDestPath)
        } else {
            try? FileManager.default.removeItem(at: tempAudioPath)
        }
        
        return encounterPath
    }
    
    // MARK: - Clean Up Temp
    
    func cleanupTempFolder(for encounterId: UUID) {
        let tempPath = basePath
            .appendingPathComponent("temp")
            .appendingPathComponent(encounterId.uuidString)
        
        try? FileManager.default.removeItem(at: tempPath)
    }
    
    func cleanupAllTemp() {
        let tempPath = basePath.appendingPathComponent("temp")
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: tempPath,
            includingPropertiesForKeys: nil
        ) else { return }
        
        for item in contents {
            try? FileManager.default.removeItem(at: item)
        }
    }
    
    // MARK: - List Past Encounters
    
    func listPastEncounters() -> [URL] {
        let encountersPath = basePath.appendingPathComponent("encounters")
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: encountersPath,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        return contents.sorted { url1, url2 in
            url1.lastPathComponent > url2.lastPathComponent // Descending order
        }
    }
    
    func loadEncounter(from path: URL) -> EncounterState? {
        let jsonPath = path.appendingPathComponent("encounter.json")
        
        guard let data = try? Data(contentsOf: jsonPath) else { return nil }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try? decoder.decode(EncounterState.self, from: data)
    }
    
    // MARK: - Helpers
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

