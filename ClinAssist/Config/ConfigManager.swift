import Foundation

extension Notification.Name {
    /// Posted after config.json is saved successfully and in-memory config is updated.
    static let clinAssistConfigDidChange = Notification.Name("clinassist.configDidChange")
}

// MARK: - LLM Function and Scenario Types

/// Functions that use LLM providers
enum LLMFunction: String, CaseIterable {
    case psst = "psst"
    case sessionDetection = "sessionDetection"
    case finalSoap = "finalSoap"
    case chat = "chat"
    case billing = "billing"
    case imageGeneration = "imageGeneration"
    
    var displayName: String {
        switch self {
        case .psst: return "Psst... Predictions"
        case .sessionDetection: return "Session Detection"
        case .finalSoap: return "Final SOAP Note"
        case .chat: return "Chat Assistant"
        case .billing: return "Billing Codes"
        case .imageGeneration: return "Image Generation"
        }
    }
    
    var description: String {
        switch self {
        case .psst: return "Anticipatory suggestions during encounter"
        case .sessionDetection: return "Auto-detect encounter start/end"
        case .finalSoap: return "Polished SOAP note after encounter ends"
        case .chat: return "Conversational assistant during encounter"
        case .billing: return "Suggest billing and diagnostic codes"
        case .imageGeneration: return "Generate images from text prompts"
        }
    }
    
    /// Which scenarios are applicable to this function
    var applicableScenarios: [LLMScenario] {
        switch self {
        case .sessionDetection, .psst:
            return [.standard, .backup]  // No multimodal/large for these
        case .finalSoap:
            return LLMScenario.allCases
        case .chat:
            return [.standard, .multimodal, .backup]  // Chat supports multimodal but not large
        case .billing:
            return [.standard, .backup]  // Simple text analysis
        case .imageGeneration:
            return [.standard]  // Only one model for image gen
        }
    }
}

/// Scenarios that determine which model to use
enum LLMScenario: String, CaseIterable {
    case standard = "standard"
    case large = "large"
    case multimodal = "multimodal"
    case backup = "backup"
    
    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .large: return "Large Transcript"
        case .multimodal: return "Multimodal (Images)"
        case .backup: return "Backup"
        }
    }
    
    var description: String {
        switch self {
        case .standard: return "Regular/small transcripts"
        case .large: return "Long transcripts (>5000 words)"
        case .multimodal: return "When images are included"
        case .backup: return "Fallback if primary unavailable"
        }
    }
}

// MARK: - LLM Model Selection

/// Represents an LLM model with its provider
struct LLMModelOption: Identifiable, Hashable {
    let id: String           // Unique identifier (e.g., "ollama:qwen3:8b")
    let provider: LLMProviderType
    let modelId: String      // Model ID for API calls
    let displayName: String  // Human-readable name
    let isLocal: Bool
    let supportsMultimodal: Bool
    let supportsLargeContext: Bool
    
    static func == (lhs: LLMModelOption, rhs: LLMModelOption) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Available LLM providers
enum LLMProviderType: String, Codable, CaseIterable {
    case ollama = "ollama"
    case groq = "groq"
    case openRouter = "openRouter"
    
    var displayName: String {
        switch self {
        case .ollama: return "Ollama (Local)"
        case .groq: return "Groq (Cloud)"
        case .openRouter: return "OpenRouter (Cloud)"
        }
    }
    
    var icon: String {
        switch self {
        case .ollama: return "desktopcomputer"
        case .groq: return "bolt"
        case .openRouter: return "cloud"
        }
    }
}

/// Pre-defined model options available in the app
struct LLMModelRegistry {
    
    // MARK: - Ollama Models (Local)
    static let ollamaQwen3_8b = LLMModelOption(
        id: "ollama:qwen3:8b",
        provider: .ollama,
        modelId: "qwen3:8b",
        displayName: "Qwen3 8B (Local)",
        isLocal: true,
        supportsMultimodal: false,
        supportsLargeContext: false
    )
    
    static let ollamaQwen3_14b = LLMModelOption(
        id: "ollama:qwen3:14b",
        provider: .ollama,
        modelId: "qwen3:14b",
        displayName: "Qwen3 14B (Local)",
        isLocal: true,
        supportsMultimodal: false,
        supportsLargeContext: false
    )
    
    static let ollamaLlama3_8b = LLMModelOption(
        id: "ollama:llama3:8b",
        provider: .ollama,
        modelId: "llama3:8b",
        displayName: "Llama 3 8B (Local)",
        isLocal: true,
        supportsMultimodal: false,
        supportsLargeContext: false
    )
    
    static let ollamaMistral = LLMModelOption(
        id: "ollama:mistral",
        provider: .ollama,
        modelId: "mistral",
        displayName: "Mistral 7B (Local)",
        isLocal: true,
        supportsMultimodal: false,
        supportsLargeContext: false
    )
    
    // MARK: - Groq Models (Cloud - Fast)
    static let groqGptOss120b = LLMModelOption(
        id: "groq:openai/gpt-oss-120b",
        provider: .groq,
        modelId: "openai/gpt-oss-120b",
        displayName: "GPT-OSS 120B (Groq)",
        isLocal: false,
        supportsMultimodal: false,
        supportsLargeContext: true
    )
    
    static let groqGptOss20b = LLMModelOption(
        id: "groq:openai/gpt-oss-20b",
        provider: .groq,
        modelId: "openai/gpt-oss-20b",
        displayName: "GPT-OSS 20B (Groq)",
        isLocal: false,
        supportsMultimodal: false,
        supportsLargeContext: true
    )
    
    static let groqKimiK2 = LLMModelOption(
        id: "groq:moonshotai/kimi-k2",
        provider: .groq,
        modelId: "moonshotai/kimi-k2",
        displayName: "Kimi K2 (Groq)",
        isLocal: false,
        supportsMultimodal: false,
        supportsLargeContext: true
    )
    
    // MARK: - OpenRouter Models (Cloud - Variety)
    static let openRouterClaude4Sonnet = LLMModelOption(
        id: "openrouter:anthropic/claude-sonnet-4",
        provider: .openRouter,
        modelId: "anthropic/claude-sonnet-4",
        displayName: "Claude Sonnet 4",
        isLocal: false,
        supportsMultimodal: true,
        supportsLargeContext: true
    )
    
    static let openRouterClaude4Opus = LLMModelOption(
        id: "openrouter:anthropic/claude-opus-4",
        provider: .openRouter,
        modelId: "anthropic/claude-opus-4",
        displayName: "Claude Opus 4",
        isLocal: false,
        supportsMultimodal: true,
        supportsLargeContext: true
    )
    
    static let openRouterGPT4o = LLMModelOption(
        id: "openrouter:openai/gpt-4o",
        provider: .openRouter,
        modelId: "openai/gpt-4o",
        displayName: "GPT-4o",
        isLocal: false,
        supportsMultimodal: true,
        supportsLargeContext: true
    )
    
    static let openRouterGPT4oMini = LLMModelOption(
        id: "openrouter:openai/gpt-4o-mini",
        provider: .openRouter,
        modelId: "openai/gpt-4o-mini",
        displayName: "GPT-4o Mini",
        isLocal: false,
        supportsMultimodal: true,
        supportsLargeContext: false
    )
    
    static let openRouterGeminiFlash = LLMModelOption(
        id: "openrouter:google/gemini-2.5-flash",
        provider: .openRouter,
        modelId: "google/gemini-2.5-flash",
        displayName: "Gemini 2.5 Flash",
        isLocal: false,
        supportsMultimodal: true,
        supportsLargeContext: true
    )
    
    static let openRouterGeminiPro = LLMModelOption(
        id: "openrouter:google/gemini-2.5-pro",
        provider: .openRouter,
        modelId: "google/gemini-2.5-pro",
        displayName: "Gemini 2.5 Pro",
        isLocal: false,
        supportsMultimodal: true,
        supportsLargeContext: true
    )
    
    static let openRouterDeepseekChat = LLMModelOption(
        id: "openrouter:deepseek/deepseek-chat",
        provider: .openRouter,
        modelId: "deepseek/deepseek-chat",
        displayName: "DeepSeek Chat",
        isLocal: false,
        supportsMultimodal: false,
        supportsLargeContext: true
    )
    
    static let openRouterDeepseekReasoner = LLMModelOption(
        id: "openrouter:deepseek/deepseek-reasoner",
        provider: .openRouter,
        modelId: "deepseek/deepseek-reasoner",
        displayName: "DeepSeek Reasoner",
        isLocal: false,
        supportsMultimodal: false,
        supportsLargeContext: true
    )
    
    // MARK: - OpenRouter Models (Chat-optimized)
    static let openRouterGemini3Pro = LLMModelOption(
        id: "openrouter:google/gemini-3-pro-preview",
        provider: .openRouter,
        modelId: "google/gemini-3-pro-preview",
        displayName: "Gemini 3 Pro",
        isLocal: false,
        supportsMultimodal: true,
        supportsLargeContext: true
    )
    
    // MARK: - OpenRouter Models (Image Generation)
    static let openRouterGemini3ProImage = LLMModelOption(
        id: "openrouter:google/gemini-3-pro-image-preview",
        provider: .openRouter,
        modelId: "google/gemini-3-pro-image-preview",
        displayName: "Gemini 3 Pro Image",
        isLocal: false,
        supportsMultimodal: true,
        supportsLargeContext: false
    )
    
    // MARK: - All Models
    static let allModels: [LLMModelOption] = [
        // Ollama (Local)
        ollamaQwen3_8b,
        ollamaQwen3_14b,
        ollamaLlama3_8b,
        ollamaMistral,
        // Groq (Fast Cloud)
        groqGptOss120b,
        groqGptOss20b,
        groqKimiK2,
        // OpenRouter (Cloud)
        openRouterClaude4Sonnet,
        openRouterClaude4Opus,
        openRouterGPT4o,
        openRouterGPT4oMini,
        openRouterGeminiFlash,
        openRouterGeminiPro,
        openRouterGemini3Pro,
        openRouterDeepseekChat,
        openRouterDeepseekReasoner
    ]
    
    /// Models specifically for image generation
    static let imageGenerationModels: [LLMModelOption] = [
        openRouterGemini3ProImage
    ]
    
    /// Legacy model ID mappings (old ID -> new ID)
    /// These are NOT shown in the settings UI but allow old configs to continue working
    static let legacyModelAliases: [String: String] = [
        "groq:llama-3.3-70b-versatile": "groq:openai/gpt-oss-120b",
        "groq:llama-3.1-8b-instant": "groq:openai/gpt-oss-20b",
        "groq:mixtral-8x7b-32768": "groq:openai/gpt-oss-120b"
    ]
    
    /// Get models available for a specific scenario and optionally function
    static func modelsFor(scenario: LLMScenario, function: LLMFunction? = nil) -> [LLMModelOption] {
        // Image generation has its own model list
        if function == .imageGeneration {
            return imageGenerationModels
        }
        
        switch scenario {
        case .standard:
            return allModels
        case .large:
            return allModels.filter { !$0.isLocal || $0.supportsLargeContext }
        case .multimodal:
            return allModels.filter { $0.supportsMultimodal }
        case .backup:
            return allModels.filter { !$0.isLocal }  // Cloud only for backup
        }
    }
    
    /// Find model by ID (searches all models, image generation models, and legacy aliases)
    static func model(byId id: String) -> LLMModelOption? {
        // First try direct lookup in all models
        if let model = allModels.first(where: { $0.id == id }) {
            return model
        }
        // Try image generation models
        if let model = imageGenerationModels.first(where: { $0.id == id }) {
            return model
        }
        // Check legacy aliases for backward compatibility
        if let newId = legacyModelAliases[id] {
            debugLog("↪️ Legacy model ID '\(id)' mapped to '\(newId)'", component: "Config")
            return allModels.first { $0.id == newId }
        }
        return nil
    }
    
    /// Get default model for a scenario
    static func defaultModel(for scenario: LLMScenario, function: LLMFunction) -> LLMModelOption {
        switch scenario {
        case .standard:
            // Use fast cloud model as default (not slow local Ollama)
            return groqGptOss120b
        case .large:
            return openRouterGeminiFlash
        case .multimodal:
            return function == .finalSoap ? openRouterGeminiPro : openRouterGeminiFlash
        case .backup:
            return openRouterGeminiFlash
        }
    }
}

/// Configuration for LLM model selection per scenario within a function
/// Stores model IDs (e.g., "ollama:qwen3:8b", "openrouter:anthropic/claude-sonnet-4")
struct FunctionLLMConfig: Codable {
    var standard: String?     // Model ID for regular/small transcripts
    var large: String?        // Model ID for large transcripts
    var multimodal: String?   // Model ID when images are included
    var backup: String?       // Fallback model ID
    
    static var `default`: FunctionLLMConfig {
        FunctionLLMConfig(
            standard: LLMModelRegistry.ollamaQwen3_8b.id,
            large: LLMModelRegistry.openRouterGeminiFlash.id,
            multimodal: LLMModelRegistry.openRouterGeminiFlash.id,
            backup: LLMModelRegistry.openRouterGeminiFlash.id
        )
    }
    
    static var defaultForPsst: FunctionLLMConfig {
        FunctionLLMConfig(
            standard: LLMModelRegistry.groqGptOss20b.id,  // Groq is fast for real-time predictions
            large: nil,      // Not applicable
            multimodal: nil, // Not applicable
            backup: LLMModelRegistry.openRouterGeminiFlash.id
        )
    }
    
    static var defaultForSessionDetection: FunctionLLMConfig {
        FunctionLLMConfig(
            standard: LLMModelRegistry.ollamaQwen3_8b.id,
            large: nil,      // Not applicable
            multimodal: nil, // Not applicable
            backup: LLMModelRegistry.openRouterGeminiFlash.id
        )
    }
    
    static var defaultForFinalSoap: FunctionLLMConfig {
        FunctionLLMConfig(
            standard: LLMModelRegistry.groqGptOss120b.id,
            large: LLMModelRegistry.openRouterGeminiFlash.id,
            multimodal: LLMModelRegistry.openRouterGeminiPro.id,
            backup: LLMModelRegistry.openRouterGeminiFlash.id
        )
    }
    
    static var defaultForChat: FunctionLLMConfig {
        FunctionLLMConfig(
            standard: LLMModelRegistry.openRouterGemini3Pro.id,
            large: nil,      // Not applicable
            multimodal: LLMModelRegistry.openRouterGemini3Pro.id,
            backup: LLMModelRegistry.openRouterGeminiFlash.id
        )
    }
    
    static var defaultForBilling: FunctionLLMConfig {
        FunctionLLMConfig(
            standard: LLMModelRegistry.groqGptOss120b.id,
            large: nil,      // Not applicable
            multimodal: nil, // Not applicable
            backup: LLMModelRegistry.openRouterGeminiFlash.id
        )
    }
    
    static var defaultForImageGeneration: FunctionLLMConfig {
        FunctionLLMConfig(
            standard: LLMModelRegistry.openRouterGemini3ProImage.id,
            large: nil,
            multimodal: nil,
            backup: nil
        )
    }
}

/// Container for all function-specific LLM configurations
struct LLMFunctionConfigs: Codable {
    var psst: FunctionLLMConfig?
    var sessionDetection: FunctionLLMConfig?
    var finalSoap: FunctionLLMConfig?
    var chat: FunctionLLMConfig?
    var billing: FunctionLLMConfig?
    var imageGeneration: FunctionLLMConfig?
    
    enum CodingKeys: String, CodingKey {
        case psst
        case sessionDetection = "session_detection"
        case finalSoap = "final_soap"
        case chat
        case billing
        case imageGeneration = "image_generation"
    }
    
    static var `default`: LLMFunctionConfigs {
        LLMFunctionConfigs(
            psst: .defaultForPsst,
            sessionDetection: .defaultForSessionDetection,
            finalSoap: .defaultForFinalSoap,
            chat: .defaultForChat,
            billing: .defaultForBilling,
            imageGeneration: .defaultForImageGeneration
        )
    }
}

// MARK: - App Configuration

struct AppConfig: Codable {
    var openrouterApiKey: String
    var deepgramApiKey: String
    var geminiApiKey: String?
    var model: String
    var timing: TimingConfig
    var autoDetection: AutoDetectionConfig?
    var ollama: OllamaConfig?
    var deepgram: DeepgramConfig?
    var groq: GroqConfig?
    var llmFunctions: LLMFunctionConfigs?
    
    enum CodingKeys: String, CodingKey {
        case openrouterApiKey = "openrouter_api_key"
        case deepgramApiKey = "deepgram_api_key"
        case geminiApiKey = "gemini_api_key"
        case model
        case timing
        case autoDetection = "auto_detection"
        case ollama
        case deepgram
        case groq
        case llmFunctions = "llm_functions"
    }
    
    static var `default`: AppConfig {
        AppConfig(
            openrouterApiKey: "",
            deepgramApiKey: "",
            geminiApiKey: "",
            model: "anthropic/claude-sonnet-4",
            timing: .default,
            autoDetection: .default,
            ollama: .default,
            deepgram: .default,
            groq: .default,
            llmFunctions: .default
        )
    }
}

struct GroqConfig: Codable {
    var apiKey: String
    var model: String?
    var useForFinalSoap: Bool?
    
    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case model
        case useForFinalSoap = "use_for_final_soap"
    }
    
    static var `default`: GroqConfig {
        GroqConfig(
            apiKey: "",
            model: "openai/gpt-oss-120b",
            useForFinalSoap: true
        )
    }
}

struct DeepgramConfig: Codable {
    var useStreaming: Bool?
    var interimResults: Bool?
    var saveAudioBackup: Bool?
    
    enum CodingKeys: String, CodingKey {
        case useStreaming = "use_streaming"
        case interimResults = "interim_results"
        case saveAudioBackup = "save_audio_backup"
    }
    
    static var `default`: DeepgramConfig {
        DeepgramConfig(
            useStreaming: true,
            interimResults: true,
            saveAudioBackup: true
        )
    }
}

struct OllamaConfig: Codable {
    var enabled: Bool
    var baseUrl: String?
    var model: String?
    var useForHelpers: Bool?
    var useForLiveSoap: Bool?
    var useForSessionDetection: Bool?
    var useForFinalSoap: Bool?  // Uses thinking mode for final SOAP
    
    enum CodingKeys: String, CodingKey {
        case enabled
        case baseUrl = "base_url"
        case model
        case useForHelpers = "use_for_helpers"
        case useForLiveSoap = "use_for_live_soap"
        case useForSessionDetection = "use_for_session_detection"
        case useForFinalSoap = "use_for_final_soap"
    }
    
    static var `default`: OllamaConfig {
        OllamaConfig(
            enabled: true,
            baseUrl: "http://localhost:11434",
            model: "qwen3:8b",
            useForHelpers: true,
            useForLiveSoap: true,
            useForSessionDetection: true,
            useForFinalSoap: false  // Disabled by default, uses Groq/OpenRouter
        )
    }
}

struct TimingConfig: Codable {
    var transcriptionIntervalSeconds: Int
    var helperUpdateIntervalSeconds: Int
    var soapUpdateIntervalSeconds: Int
    
    enum CodingKeys: String, CodingKey {
        case transcriptionIntervalSeconds = "transcription_interval_seconds"
        case helperUpdateIntervalSeconds = "helper_update_interval_seconds"
        case soapUpdateIntervalSeconds = "soap_update_interval_seconds"
    }
    
    static var `default`: TimingConfig {
        TimingConfig(
            transcriptionIntervalSeconds: 10,
            helperUpdateIntervalSeconds: 20,
            soapUpdateIntervalSeconds: 30
        )
    }
}

struct AutoDetectionConfig: Codable {
    var enabled: Bool
    var detectEndOfEncounter: Bool?
    var silenceThresholdSeconds: Int?
    var minEncounterDurationSeconds: Int?
    var speechActivityThreshold: Double?
    var bufferDurationSeconds: Int?
    
    enum CodingKeys: String, CodingKey {
        case enabled
        case detectEndOfEncounter = "detect_end_of_encounter"
        case silenceThresholdSeconds = "silence_threshold_seconds"
        case minEncounterDurationSeconds = "min_encounter_duration_seconds"
        case speechActivityThreshold = "speech_activity_threshold"
        case bufferDurationSeconds = "buffer_duration_seconds"
    }
    
    static var `default`: AutoDetectionConfig {
        AutoDetectionConfig(
            enabled: false,
            detectEndOfEncounter: true,
            silenceThresholdSeconds: 45,
            minEncounterDurationSeconds: 60,
            speechActivityThreshold: 0.02,
            bufferDurationSeconds: 45  // Needs time for: audio record + transcribe + LLM analysis
        )
    }
}

@MainActor
class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    @Published var config: AppConfig?
    @Published var configError: String?
    
    private let configPath: URL
    
    var isConfigured: Bool {
        config != nil
    }
    
    var isAutoDetectionEnabled: Bool {
        config?.autoDetection?.enabled ?? false
    }
    
    var isOllamaEnabled: Bool {
        config?.ollama?.enabled ?? false
    }
    
    var ollamaBaseUrl: String {
        config?.ollama?.baseUrl ?? "http://localhost:11434"
    }
    
    var ollamaModel: String {
        config?.ollama?.model ?? "qwen3:8b"
    }
    
    var useOllamaForHelpers: Bool {
        (config?.ollama?.enabled ?? false) && (config?.ollama?.useForHelpers ?? true)
    }
    
    var useOllamaForLiveSoap: Bool {
        (config?.ollama?.enabled ?? false) && (config?.ollama?.useForLiveSoap ?? true)
    }
    
    var useOllamaForSessionDetection: Bool {
        (config?.ollama?.enabled ?? false) && (config?.ollama?.useForSessionDetection ?? true)
    }
    
    var useOllamaForFinalSoap: Bool {
        (config?.ollama?.enabled ?? false) && (config?.ollama?.useForFinalSoap ?? false)
    }
    
    // MARK: - Groq Config
    
    var isGroqEnabled: Bool {
        guard let apiKey = config?.groq?.apiKey, !apiKey.isEmpty else { return false }
        return true
    }
    
    var groqApiKey: String {
        config?.groq?.apiKey ?? ""
    }
    
    var groqModel: String {
        config?.groq?.model ?? "openai/gpt-oss-120b"
    }
    
    var useGroqForFinalSoap: Bool {
        isGroqEnabled && (config?.groq?.useForFinalSoap ?? true)
    }
    
    // MARK: - Gemini Config
    
    var isGeminiEnabled: Bool {
        guard let apiKey = config?.geminiApiKey, !apiKey.isEmpty else { return false }
        return true
    }
    
    var geminiApiKey: String {
        config?.geminiApiKey ?? ""
    }
    
    // MARK: - Deepgram Streaming Config
    
    var useDeepgramStreaming: Bool {
        config?.deepgram?.useStreaming ?? true  // Default to streaming
    }
    
    var showInterimResults: Bool {
        config?.deepgram?.interimResults ?? true
    }
    
    var saveAudioBackup: Bool {
        config?.deepgram?.saveAudioBackup ?? true
    }
    
    // MARK: - LLM Function Configs
    
    var llmFunctions: LLMFunctionConfigs {
        config?.llmFunctions ?? .default
    }
    
    var psstConfig: FunctionLLMConfig {
        llmFunctions.psst ?? .defaultForPsst
    }
    
    var sessionDetectionConfig: FunctionLLMConfig {
        llmFunctions.sessionDetection ?? .defaultForSessionDetection
    }
    
    var finalSoapConfig: FunctionLLMConfig {
        llmFunctions.finalSoap ?? .defaultForFinalSoap
    }
    
    var chatConfig: FunctionLLMConfig {
        llmFunctions.chat ?? .defaultForChat
    }
    
    var billingConfig: FunctionLLMConfig {
        llmFunctions.billing ?? .defaultForBilling
    }
    
    var imageGenerationConfig: FunctionLLMConfig {
        llmFunctions.imageGeneration ?? .defaultForImageGeneration
    }
    
    /// Get the configured model for a function and scenario
    func getModel(for function: LLMFunction, scenario: LLMScenario) -> LLMModelOption {
        let functionConfig: FunctionLLMConfig
        switch function {
        case .psst:
            functionConfig = psstConfig
        case .sessionDetection:
            functionConfig = sessionDetectionConfig
        case .finalSoap:
            functionConfig = finalSoapConfig
        case .chat:
            functionConfig = chatConfig
        case .billing:
            functionConfig = billingConfig
        case .imageGeneration:
            functionConfig = imageGenerationConfig
        }
        
        let modelId: String?
        switch scenario {
        case .standard:
            modelId = functionConfig.standard
        case .large:
            modelId = functionConfig.large ?? functionConfig.backup
        case .multimodal:
            modelId = functionConfig.multimodal ?? functionConfig.backup
        case .backup:
            modelId = functionConfig.backup
        }
        
        // Look up model by ID
        if let id = modelId, let model = LLMModelRegistry.model(byId: id) {
            return model
        }
        
        // Model ID not found - log warning and try backup before falling back to default
        if let id = modelId {
            debugLog("⚠️ Model ID '\(id)' not found for \(function.displayName), checking backup", component: "Config")
        }
        
        // Try backup model if available (prefer cloud backup over local default)
        if scenario != .backup,  // Don't recurse if already looking for backup
           let backupId = functionConfig.backup,
           let backupModel = LLMModelRegistry.model(byId: backupId) {
            debugLog("↪️ Using backup model: \(backupModel.displayName)", component: "Config")
            return backupModel
        }
        
        // Last resort: use system default
        let defaultModel = LLMModelRegistry.defaultModel(for: scenario, function: function)
        debugLog("↪️ Using system default: \(defaultModel.displayName)", component: "Config")
        return defaultModel
    }
    
    /// Get the appropriate provider for a function based on scenario (legacy compatibility)
    func getProvider(for function: LLMFunction, scenario: LLMScenario) -> LLMProviderType {
        return getModel(for: function, scenario: scenario).provider
    }
    
    /// Create a ConfigManager.
    /// - Parameters:
    ///   - configPath: Path to `config.json`. Defaults to `~/Dropbox/livecode_records/config.json`.
    ///   - shouldLoad: If true, loads config immediately.
    init(configPath: URL? = nil, shouldLoad: Bool = true) {
        if let configPath {
            self.configPath = configPath
        } else {
            let dropboxPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Dropbox")
                .appendingPathComponent("livecode_records")
            self.configPath = dropboxPath.appendingPathComponent("config.json")
        }
        
        // Ensure parent directory exists.
        try? FileManager.default.createDirectory(at: self.configPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        if shouldLoad {
            loadConfig()
        }
    }
    
    func loadConfig() {
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            configError = "Config file not found at ~/Dropbox/livecode_records/config.json"
            return
        }
        
        do {
            let data = try Data(contentsOf: configPath)
            config = try JSONDecoder().decode(AppConfig.self, from: data)
            configError = nil
        } catch {
            configError = "Failed to parse config.json: \(error.localizedDescription)"
            config = nil
        }
    }
    
    /// Save the current config to the config.json file
    func saveConfig(_ newConfig: AppConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(newConfig)
        try persistConfigData(data)
        
        // Update the in-memory config
        config = newConfig
        configError = nil
        
        debugLog("✅ Config saved to \(configPath.path)", component: "ConfigManager")
        
        // Notify listeners (AppDelegate / EncounterController) to refresh clients safely.
        NotificationCenter.default.post(name: .clinAssistConfigDidChange, object: nil)
    }
    
    /// Persist config bytes to storage. Overridable for testing.
    func persistConfigData(_ data: Data) throws {
        try data.write(to: configPath)
    }
    
    /// Get the path to the config file
    var configFilePath: URL {
        configPath
    }
    
    /// Builds SessionDetector.Config from the loaded config
    func buildSessionDetectorConfig() -> SessionDetector.Config {
        var detectorConfig = SessionDetector.Config()
        
        if let autoConfig = config?.autoDetection {
            detectorConfig.enabled = autoConfig.enabled
            detectorConfig.detectEndOfEncounter = autoConfig.detectEndOfEncounter ?? true
            
            if let silenceThreshold = autoConfig.silenceThresholdSeconds {
                detectorConfig.silenceThresholdSeconds = TimeInterval(silenceThreshold)
            }
            
            if let minDuration = autoConfig.minEncounterDurationSeconds {
                detectorConfig.minEncounterDurationSeconds = TimeInterval(minDuration)
            }
            
            if let speechThreshold = autoConfig.speechActivityThreshold {
                detectorConfig.speechActivityThreshold = Float(speechThreshold)
            }
            
            if let bufferDuration = autoConfig.bufferDurationSeconds {
                detectorConfig.bufferDurationSeconds = TimeInterval(bufferDuration)
            }
        } else {
            detectorConfig.enabled = false
        }
        
        return detectorConfig
    }
    
    func createSampleConfig() {
        let sampleConfig = """
        {
          "openrouter_api_key": "sk-or-your-key-here",
          "deepgram_api_key": "your-deepgram-key-here",
          "gemini_api_key": "your-gemini-api-key-here",
          "model": "anthropic/claude-sonnet-4",
          "timing": {
            "transcription_interval_seconds": 10,
            "helper_update_interval_seconds": 10,
            "soap_update_interval_seconds": 15
          },
          "deepgram": {
            "use_streaming": true,
            "interim_results": true,
            "save_audio_backup": true
          },
          "auto_detection": {
            "enabled": false,
            "detect_end_of_encounter": true,
            "silence_threshold_seconds": 45,
            "min_encounter_duration_seconds": 60,
            "speech_activity_threshold": 0.02,
            "buffer_duration_seconds": 45
          },
          "ollama": {
            "enabled": true,
            "base_url": "http://localhost:11434",
            "model": "qwen3:8b",
            "use_for_helpers": true,
            "use_for_live_soap": true,
            "use_for_session_detection": true
          },
          "groq": {
            "api_key": "your-groq-api-key-here",
            "model": "openai/gpt-oss-120b",
            "use_for_final_soap": true
          },
          "llm_functions": {
            "psst": {
              "standard": "groq:openai/gpt-oss-20b",
              "backup": "openrouter:google/gemini-2.5-flash"
            },
            "session_detection": {
              "standard": "ollama:qwen3:8b",
              "backup": "openrouter:google/gemini-2.5-flash"
            },
            "final_soap": {
              "standard": "groq:openai/gpt-oss-120b",
              "large": "openrouter:google/gemini-2.5-flash",
              "multimodal": "openrouter:google/gemini-2.5-pro",
              "backup": "openrouter:google/gemini-2.5-flash"
            },
            "chat": {
              "standard": "openrouter:google/gemini-3-pro-preview",
              "multimodal": "openrouter:google/gemini-3-pro-preview",
              "backup": "openrouter:google/gemini-2.5-flash"
            },
            "billing": {
              "standard": "groq:openai/gpt-oss-120b",
              "backup": "openrouter:google/gemini-2.5-flash"
            },
            "image_generation": {
              "standard": "openrouter:google/gemini-3-pro-image-preview"
            }
          }
        }
        """
        
        try? sampleConfig.write(to: configPath, atomically: true, encoding: .utf8)
    }
}
