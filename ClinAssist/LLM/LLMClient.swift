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

// MARK: - SessionDetector quick completions

extension LLMClient: SessionDetectorLLMClient {
    /// Fast short response completion used by SessionDetector (expects 1-word outputs like START/WAIT/END/CONTINUE).
    func quickComplete(prompt: String, modelOverride: String? = nil) async throws -> String {
        guard let url = URL(string: baseURL) else {
            throw LLMProviderError.invalidURL
        }
        
        let effectiveModel = modelOverride ?? model
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://clinassist.local", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("ClinAssist", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 30
        
        // Keep this deterministic and short.
        let requestBody: [String: Any] = [
            "model": effectiveModel,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.1,
            "max_tokens": 64
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw LLMProviderError.invalidAPIKey(provider: "OpenRouter")
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMProviderError.requestFailed(provider: "OpenRouter", message: "HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
        
        return try LLMResponseParser.parseOpenAIChatResponse(data)
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
    What is the physician likely to want to know in the next couple of minutes? Take your best guess. Keep it really short as though you're whispering a short phrase to the physician as an assist. Start with "pssstt..."
    """
    
    // MARK: - SOAP Format Options
    
    static let problemBasedFormat = """
    
    **FORMAT: PROBLEM-BASED**
    
    Organize the SOAP note by PROBLEM. If a patient has multiple distinct medical problems or concerns, create a SEPARATE complete SOAP section for each problem. Each problem should have its own S, O, A, P sections.
    
    Example structure:
    PATIENT: [Name]
    
    PROBLEM: [First problem title]
    S: [Subjective for this problem]
    O: [Objective for this problem]
    A: [Assessment for this problem]
    P: [Plan for this problem]
    
    PROBLEM: [Second problem title]
    S: [Subjective for this problem]
    ...and so on
    """
    
    static let comprehensiveFormat = """
    
    **FORMAT: COMPREHENSIVE (SINGLE NOTE)**
    
    Create ONE unified SOAP note that covers ALL problems together. Do NOT separate by problem. Combine all subjective findings into one S section, all objective findings into one O section, list all diagnoses together in Assessment, and combine all plan items into one P section.
    
    The note should flow as a single cohesive document covering the entire encounter.
    """
    
    // MARK: - Detail Level System (1-10)
    
    /// Returns a detail level modifier based on a 1-10 scale
    /// 1 = extremely brief, 5 = standard, 10 = maximum detail
    static func detailModifier(level: Int) -> String {
        let clampedLevel = max(1, min(10, level))
        
        switch clampedLevel {
        case 1:
            return """
            
            **DETAIL LEVEL: 1/10 (ULTRA-BRIEF)**
            
            Create the SHORTEST possible note:
            - Maximum 1-2 bullet points per section
            - Only the single most important finding/symptom
            - One-word or very short phrase bullet points
            - Omit anything that isn't absolutely critical
            - Skip sections entirely if minimal relevant info
            """
        case 2:
            return """
            
            **DETAIL LEVEL: 2/10 (MINIMAL)**
            
            Create a very abbreviated note:
            - Maximum 2-3 bullet points per section
            - Only key symptoms and findings
            - Brief, telegraphic style
            - Omit context and history details
            """
        case 3:
            return """
            
            **DETAIL LEVEL: 3/10 (BRIEF)**
            
            Create a concise note:
            - 3-4 bullet points per section maximum
            - Focus on primary complaint
            - Minimal background information
            - Essential findings only
            """
        case 4:
            return """
            
            **DETAIL LEVEL: 4/10 (SHORT)**
            
            Create a shorter-than-standard note:
            - Fewer bullet points than usual
            - Combine related items where possible
            - Limited contextual information
            - Focus on main issues
            """
        case 5:
            return "" // Standard - no modifier needed
        case 6:
            return """
            
            **DETAIL LEVEL: 6/10 (EXPANDED)**
            
            Create a slightly more detailed note:
            - Include additional symptom descriptors
            - Add relevant context
            - More thorough but still concise
            """
        case 7:
            return """
            
            **DETAIL LEVEL: 7/10 (DETAILED)**
            
            Create a more comprehensive note:
            - Include symptom timing, severity, quality
            - Add relevant history context
            - More complete objective findings
            - Expanded assessment reasoning
            """
        case 8:
            return """
            
            **DETAIL LEVEL: 8/10 (THOROUGH)**
            
            Create a thorough, detailed note:
            - Comprehensive symptom description with all OPQRST elements where relevant
            - Include pertinent negatives
            - Detailed physical exam findings
            - Full differential consideration in assessment
            - Detailed plan with rationale
            """
        case 9:
            return """
            
            **DETAIL LEVEL: 9/10 (COMPREHENSIVE)**
            
            Create a highly detailed note:
            - Extensive history with full context
            - All mentioned symptoms with complete descriptors
            - Comprehensive review of systems mentioned
            - Detailed examination findings
            - Thorough assessment with reasoning
            - Complete plan with patient education points
            """
        case 10:
            return """
            
            **DETAIL LEVEL: 10/10 (MAXIMUM)**
            
            Create the MOST comprehensive note possible:
            - Include every detail mentioned in the transcript
            - Full symptom characterization with all available details
            - Complete history including all context
            - Every objective finding documented
            - Extensive differential diagnosis discussion
            - Comprehensive plan with detailed instructions
            - Include relevant patient statements and concerns verbatim where helpful
            - Nothing should be omitted
            """
        default:
            return ""
        }
    }
    
    /// Returns the SOAP renderer prompt with detail level, format options, custom instructions, and attachment handling
    static func soapRendererWithOptions(detailLevel: Int, format: SOAPFormat, customInstructions: String = "", hasAttachments: Bool = false) -> String {
        var prompt = soapRenderer
        
        // Add format modifier
        switch format {
        case .problemBased:
            prompt += problemBasedFormat
        case .comprehensive:
            prompt += comprehensiveFormat
        }
        
        // Add detail level modifier (skip for level 5 which is standard)
        prompt += detailModifier(level: detailLevel)
        
        // Add attachment handling instructions if attachments are present
        if hasAttachments {
            prompt += attachmentInstructions
        }
        
        // Add custom instructions if provided
        if !customInstructions.isEmpty {
            prompt += """
            
            **ADDITIONAL INSTRUCTIONS FROM PHYSICIAN:**
            
            \(customInstructions)
            
            Please incorporate these instructions when generating the SOAP note.
            """
        }
        
        return prompt
    }
    
    // MARK: - Attachment Instructions
    
    static let attachmentInstructions = """
    
    **ATTACHED IMAGES/DOCUMENTS:**
    
    The encounter includes attached images, screenshots, or PDF documents. These may contain:
    - Clinical images (skin conditions, wounds, X-rays, etc.)
    - Lab results or reports
    - Medication lists or prescription images
    - Prior medical records or referral letters
    - Screenshots of relevant medical information
    
    Instructions for handling attachments:
    1. Carefully analyze any clinical images and describe relevant findings in the Objective section
    2. Extract pertinent information from documents/PDFs and integrate into appropriate sections
    3. If an image shows a skin condition, wound, or visible finding, describe its appearance, location, size, and characteristics
    4. If lab results or vitals are shown, include the values in the Objective section
    5. Reference the source of information when relevant (e.g., "Per attached lab report...")
    6. Do NOT hallucinate or assume details not visible in the attachments
    7. If an image is unclear or you cannot determine its contents, note this in the documentation
    """
}

/// Format style for SOAP note
enum SOAPFormat: String, CaseIterable {
    case problemBased = "problem"
    case comprehensive = "comprehensive"
    
    var displayName: String {
        switch self {
        case .problemBased: return "By Problem"
        case .comprehensive: return "Comprehensive"
        }
    }
    
    var icon: String {
        switch self {
        case .problemBased: return "list.bullet.indent"
        case .comprehensive: return "doc.text"
        }
    }
}

/// Detail level for SOAP note generation (legacy - kept for compatibility)
enum SOAPDetailLevel: String, CaseIterable {
    case normal = "normal"
    case more = "more"
    case less = "less"
}

// MARK: - Legacy Error Type (deprecated, use LLMProviderError)

@available(*, deprecated, message: "Use LLMProviderError instead")
typealias LLMError = LLMProviderError

