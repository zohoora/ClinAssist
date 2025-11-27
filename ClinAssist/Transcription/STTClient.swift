import Foundation

protocol STTClient {
    func transcribe(audioData: Data) async throws -> [TranscriptSegment]
}

struct TranscriptSegment: Codable, Identifiable {
    let id: UUID
    let speaker: String  // "Physician", "Patient", "Other"
    let text: String
    let timestamp: Date
    
    init(speaker: String, text: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.speaker = speaker
        self.text = text
        self.timestamp = timestamp
    }
}

enum STTError: LocalizedError {
    case invalidAPIKey
    case networkError(Error)
    case invalidResponse
    case transcriptionFailed(String)
    case noTranscript
    
    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid Deepgram API key. Please check your config.json."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from transcription service"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .noTranscript:
            return "No transcript in response"
        }
    }
}

