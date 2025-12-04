import Foundation

class DeepgramRESTClient: STTClient {
    private let apiKey: String
    private let baseURL = "https://api.deepgram.com/v1/listen"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func transcribe(audioData: Data) async throws -> [TranscriptSegment] {
        // Build URL with query parameters
        // Note: nova-3-medical requires language=en (doesn't support multi/detect_language)
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "model", value: "nova-3-medical"),  // Medical-optimized model with 63% better accuracy
            URLQueryItem(name: "language", value: "en"),           // English (required for nova-3-medical)
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "diarize", value: "true"),
            URLQueryItem(name: "punctuate", value: "true")
        ]
        
        guard let url = components.url else {
            throw STTError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData
        request.timeoutInterval = 30
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw STTError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw STTError.invalidAPIKey
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw STTError.transcriptionFailed("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
        
        return try parseResponse(data)
    }
    
    private func parseResponse(_ data: Data) throws -> [TranscriptSegment] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let channels = results["channels"] as? [[String: Any]],
              let firstChannel = channels.first,
              let alternatives = firstChannel["alternatives"] as? [[String: Any]],
              let firstAlternative = alternatives.first else {
            throw STTError.invalidResponse
        }
        
        // Try to get diarized words first
        if let words = firstAlternative["words"] as? [[String: Any]], !words.isEmpty {
            return parseWordsWithDiarization(words)
        }
        
        // Fall back to full transcript
        if let transcript = firstAlternative["transcript"] as? String, !transcript.isEmpty {
            return [TranscriptSegment(speaker: "Unknown", text: transcript)]
        }
        
        throw STTError.noTranscript
    }
    
    private func parseWordsWithDiarization(_ words: [[String: Any]]) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        var currentSpeaker: Int = -1
        var currentText: [String] = []
        
        for word in words {
            guard let text = word["word"] as? String else { continue }
            let speaker = word["speaker"] as? Int ?? 0
            
            if speaker != currentSpeaker {
                // Save previous segment if exists
                if !currentText.isEmpty {
                    let speakerName = mapSpeakerLabel(currentSpeaker)
                    segments.append(TranscriptSegment(
                        speaker: speakerName,
                        text: currentText.joined(separator: " ")
                    ))
                }
                
                // Start new segment
                currentSpeaker = speaker
                currentText = [text]
            } else {
                currentText.append(text)
            }
        }
        
        // Don't forget the last segment
        if !currentText.isEmpty {
            let speakerName = mapSpeakerLabel(currentSpeaker)
            segments.append(TranscriptSegment(
                speaker: speakerName,
                text: currentText.joined(separator: " ")
            ))
        }
        
        return segments
    }
    
    private func mapSpeakerLabel(_ speakerIndex: Int) -> String {
        switch speakerIndex {
        case 0:
            return "Physician"
        case 1:
            return "Patient"
        default:
            return "Other"
        }
    }
}

