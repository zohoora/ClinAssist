import Foundation

class LLMClient {
    private let apiKey: String
    private let model: String
    private let baseURL = "https://openrouter.ai/api/v1/chat/completions"
    
    init(apiKey: String, model: String = "openai/gpt-4.1") {
        self.apiKey = apiKey
        self.model = model
    }
    
    func complete(systemPrompt: String, userContent: String) async throws -> String {
        guard let url = URL(string: baseURL) else {
            throw LLMError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://clinassist.local", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("ClinAssist", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 60
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "temperature": 0.3,
            "max_tokens": 4096
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw LLMError.invalidAPIKey
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.requestFailed("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
        
        return try parseResponse(data)
    }
    
    private func parseResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse
        }
        
        return content
    }
}

// MARK: - LLM Prompts

struct LLMPrompts {
    static let stateUpdater = """
    You are a clinical scribe for a family physician. You receive:
    1. The current encounter state as JSON
    2. New transcript text since the last update
    
    Your tasks:
    - Update the list of problems with S/O/A/P bullet points based ONLY on transcript content
    - Track issues_mentioned: symptoms, concerns, or problems the patient raises
    - Mark issues as addressed_in_plan when clearly addressed
    - Track medications_mentioned when drug names appear
    - Do NOT invent information not in the transcript
    
    Output ONLY valid JSON matching the EncounterState schema. No markdown, no explanation.
    """
    
    static let helperSuggestions = """
    You are a clinical decision support assistant for a family physician.
    
    Given the encounter state and recent transcript, provide concise suggestions.
    
    Output JSON only:
    {
      "ddx": ["diagnosis1", "diagnosis2"],
      "red_flags": ["flag1", "flag2"],
      "suggested_questions": ["q1", "q2"],
      "drug_cards": [
        {
          "name": "Drug Name",
          "class": "Drug class",
          "typical_adult_dose": "Dosing info",
          "key_cautions": ["caution1", "caution2"]
        }
      ],
      "issues": [
        {
          "label": "Patient concern or symptom",
          "addressed_in_plan": false
        }
      ]
    }
    
    For "issues": Track all symptoms, concerns, or problems the patient mentions. Set "addressed_in_plan" to true if the physician has clearly addressed it in the conversation.
    
    Include drug cards for EVERY medication mentioned. If nothing useful for a category, return empty array.
    Keep everything short and practical. No disclaimers.
    """
    
    static let soapRenderer = """
    You will be analyzing the provided medical transcript or recording to create professional SOAP notes for each patient mentioned.

    Your task is to create concise, professional SOAP notes for each patient in the transcript. Follow these specific requirements:

    **Patient Header Format:**
    
    Start each patient's section with a header line in this exact format:
    PATIENT: [Name or identifier]
    
    - Use the patient's name if mentioned in the transcript (e.g., "PATIENT: Alex" or "PATIENT: Mr. Jones")
    - If no name is mentioned, use identifying info like gender and chief complaint (e.g., "PATIENT: Male with chest pain")
    
    SOAP Note Format:

    - S (Subjective): Patient's reported symptoms, concerns, and history

    - O (Objective): Observable findings, vital signs, physical exam results. Do not include any procedure descriptions here. If no objective elements exist at all, omit this section. If a particular detail (such as blood pressure) is not mentioned, simply do not list it. For example, do not say things like '(No other vitals/exam documented)'.

    - A (Assessment): Clinical impression, diagnosis, or differential diagnosis. Keep this brief.

    - P (Plan): Procedures performed, Treatment plan, follow-up, referrals, medication changes.

    - If multiple patients are discussed, create separate SOAP notes for each

    **Problem Organization:**

    - If a patient has multiple distinct medical problems, separate each problem into its own section within that patient's SOAP note

    - Focus on significant issues; minor factors may be omitted for conciseness

    - If bloodwork is being ordered, do not list the specific tests. Only state that bloodwork is ordered as per requisition.

    - In the body of the SOAP note (S, O, A, P sections), do not write the patient's name as you may misspell it. The name only goes in the PATIENT: header line.

    - Do not number the problems

    Format your final response with clear headings for each patient and use the standard SOAP format outlined above. Make it formatted and easy to copy/paste into the EMR.

    **CRITICAL FORMATTING RULE:** Do NOT use any markdown formatting. No asterisks (*), no bold (**), no underscores (_), no hash symbols (#). Use plain text only. The output will be pasted into an EMR that does not support markdown.
    """
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case invalidURL
    case invalidAPIKey
    case invalidResponse
    case requestFailed(String)
    case parsingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidAPIKey:
            return "Invalid OpenRouter API key. Please check your config.json."
        case .invalidResponse:
            return "Invalid response from LLM service"
        case .requestFailed(let message):
            return "LLM request failed: \(message)"
        case .parsingFailed:
            return "Failed to parse LLM response"
        }
    }
}

