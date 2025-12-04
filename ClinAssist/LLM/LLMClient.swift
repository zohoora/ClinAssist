import Foundation

/// OpenRouter LLM client for cloud-based inference
class LLMClient: LLMProvider {
    private let apiKey: String
    private let model: String
    private let baseURL = "https://openrouter.ai/api/v1/chat/completions"
    
    init(apiKey: String, model: String = "openai/gpt-4.1") {
        self.apiKey = apiKey
        self.model = model
    }
    
    func complete(systemPrompt: String, userContent: String, modelOverride: String? = nil) async throws -> String {
        guard let url = URL(string: baseURL) else {
            throw LLMProviderError.invalidURL
        }
        
        let effectiveModel = modelOverride ?? model
        debugLog("🤖 Calling model: \(effectiveModel)", component: "OpenRouter")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://clinassist.local", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("ClinAssist", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 90
        
        let requestBody: [String: Any] = [
            "model": effectiveModel,
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
            debugLog("❌ Invalid response type", component: "OpenRouter")
            throw LLMProviderError.invalidResponse
        }
        
        debugLog("📡 Response status: \(httpResponse.statusCode)", component: "OpenRouter")
        
        if httpResponse.statusCode == 401 {
            debugLog("❌ Invalid API key", component: "OpenRouter")
            throw LLMProviderError.invalidAPIKey(provider: "OpenRouter")
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            debugLog("❌ Error: \(errorMessage)", component: "OpenRouter")
            throw LLMProviderError.requestFailed(provider: "OpenRouter", message: "HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
        
        let result = try LLMResponseParser.parseOpenAIChatResponse(data)
        debugLog("✅ Got response (\(result.count) chars)", component: "OpenRouter")
        return result
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

    **LANGUAGE REQUIREMENT:** The transcript may contain speech in various languages (Spanish, French, etc.). Regardless of the language spoken in the transcript, you MUST write the SOAP note entirely in English. Translate any non-English content into English for the note.

    Your task is to create concise, professional SOAP notes for each patient in the transcript. Follow these specific requirements:

    **Important:** The input includes both:
    1. "transcript" - spoken conversation during the encounter
    2. "clinicalNotes" - additional observations typed by the physician (procedures performed, physical exam findings, etc.)
    
    Integrate BOTH the transcript AND the clinical notes into the SOAP note as if they were all part of the same encounter documentation. The clinical notes often contain important objective findings and procedures that were not verbalized.

    **Patient Header Format:**
    
    Start each patient's section with a header line in this exact format:
    PATIENT: [Name or identifier]
    
    - Use the patient's name if mentioned in the transcript (e.g., "PATIENT: Alex" or "PATIENT: Mr. Jones")
    - If no name is mentioned, use identifying info like gender and chief complaint (e.g., "PATIENT: Male with chest pain")
    
    **WRITING STYLE:** Use concise point-form notes, NOT paragraph style. Each piece of information should be a brief bullet point. Be succinct and clinical.
    
    SOAP Note Format:

    - S (Subjective): Patient's reported symptoms, concerns, and history. Use bullet points for each symptom or concern.

    - O (Objective): Observable findings, vital signs, physical exam results in point form. Do not include any procedure descriptions here. If no objective elements exist at all, omit this section. If a particular detail (such as blood pressure) is not mentioned, simply do not list it.

    - A (Assessment): Clinical impression, diagnosis, or differential diagnosis. Keep this very brief - just list the diagnosis/diagnoses.

    - P (Plan): Procedures performed, Treatment plan, follow-up, referrals, medication changes. Use bullet points for each action item.

    - If multiple patients are discussed, create separate SOAP notes for each

    **Problem Organization:**

    - If a patient has multiple distinct medical problems, separate each problem into its own section within that patient's SOAP note

    - Focus on significant issues; minor factors may be omitted for conciseness

    - If bloodwork is being ordered, do not list the specific tests. Only state that bloodwork is ordered as per requisition.

    - In the body of the SOAP note (S, O, A, P sections), do not write the patient's name as you may misspell it. The name only goes in the PATIENT: header line.

    - Do not number the problems

    Format your final response with clear headings for each patient and use the standard SOAP format outlined above. Make it formatted and easy to copy/paste into the EMR.

    **CRITICAL FORMATTING RULE:** Do NOT use any markdown formatting. No asterisks (*), no bold (**), no underscores (_), no hash symbols (#). Use plain text only with simple dashes (-) for bullet points. The output will be pasted into an EMR that does not support markdown.
    """
    
    static let psstPrediction = """
    You are an anticipatory clinical assistant. Your job is to predict what information will be useful to the physician in the next few moments of the encounter.

    Given the transcript so far, think about:
    1. Where is this conversation likely heading next?
    2. What questions might the physician want to ask?
    3. What clinical information would be useful to have ready?
    4. What red flags or concerns should be watched for?

    Be practical and specific. Think like a knowledgeable medical assistant whispering helpful hints.

    Output ONLY valid JSON in this format:
    {
      "likely_next_topic": "Brief description of what's coming next in the encounter",
      "anticipated_questions": ["Question 1 the physician might ask", "Question 2"],
      "useful_info": ["Relevant clinical fact 1", "Relevant clinical fact 2"],
      "watch_for": ["Red flag or concern to monitor"]
    }

    Keep each item SHORT and actionable. Maximum 2-3 items per array. Empty arrays are fine if nothing relevant.
    Focus on being USEFUL, not comprehensive. Quality over quantity.
    No disclaimers, no explanations - just the JSON.
    """
}

// MARK: - Legacy Error Type (deprecated, use LLMProviderError)

@available(*, deprecated, message: "Use LLMProviderError instead")
typealias LLMError = LLMProviderError

