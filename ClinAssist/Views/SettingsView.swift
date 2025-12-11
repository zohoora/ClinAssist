import SwiftUI

struct SettingsView: View {
    @ObservedObject var configManager: ConfigManager
    @Environment(\.dismiss) private var dismiss
    
    // Editable copy of the config
    @State private var editableConfig: AppConfig
    @State private var hasUnsavedChanges: Bool = false
    @State private var saveError: String?
    @State private var showingSaveError: Bool = false
    
    init(configManager: ConfigManager) {
        self.configManager = configManager
        // Initialize with current config or default
        _editableConfig = State(initialValue: configManager.config ?? .default)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab View with settings sections
            TabView {
                LLMSettingsTab(config: $editableConfig, hasChanges: $hasUnsavedChanges)
                    .tabItem {
                        Label("AI Models", systemImage: "brain")
                    }
                
                TranscriptionSettingsTab(config: $editableConfig, hasChanges: $hasUnsavedChanges)
                    .tabItem {
                        Label("Transcription", systemImage: "waveform")
                    }
                
                TimingSettingsTab(config: $editableConfig, hasChanges: $hasUnsavedChanges)
                    .tabItem {
                        Label("Timing", systemImage: "clock")
                    }
                
                AutoDetectionSettingsTab(config: $editableConfig, hasChanges: $hasUnsavedChanges)
                    .tabItem {
                        Label("Auto-Detection", systemImage: "ear.badge.waveform")
                    }
            }
            .padding()
            
            Divider()
            
            // Bottom bar with save/cancel buttons
            HStack {
                if hasUnsavedChanges {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                        Text("Unsaved changes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button("Open Config File") {
                    NSWorkspace.shared.open(configManager.configFilePath)
                }
                .buttonStyle(.bordered)
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape)
                
                Button("Save") {
                    saveConfig()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(!hasUnsavedChanges)
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 500)
        .alert("Failed to Save", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveError ?? "Unknown error")
        }
    }
    
    private func saveConfig() {
        do {
            try configManager.saveConfig(editableConfig)
            hasUnsavedChanges = false
            dismiss()
        } catch {
            saveError = error.localizedDescription
            showingSaveError = true
        }
    }
}

// MARK: - LLM Settings Tab

struct LLMSettingsTab: View {
    @Binding var config: AppConfig
    @Binding var hasChanges: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Function-based LLM Configuration Sections
                ForEach(LLMFunction.allCases, id: \.self) { function in
                    FunctionLLMConfigSection(
                        function: function,
                        config: $config,
                        hasChanges: $hasChanges
                    )
                }
            }
            .padding()
        }
    }
}

// MARK: - Function LLM Config Section

struct FunctionLLMConfigSection: View {
    let function: LLMFunction
    @Binding var config: AppConfig
    @Binding var hasChanges: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Label(function.displayName, systemImage: iconForFunction(function))
                .font(.headline)
                .padding(.horizontal, 4)
            
            // Subtitle (right below header)
            Text(function.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.top, 2)
                .padding(.bottom, 8)
            
            // Content card
            VStack(spacing: 0) {
                ForEach(Array(function.applicableScenarios.enumerated()), id: \.element) { index, scenario in
                    ScenarioModelRow(
                        scenario: scenario,
                        function: function,
                        selectedModelId: getModelId(for: scenario),
                        availableModels: LLMModelRegistry.modelsFor(scenario: scenario, function: function),
                        onSelect: { setModelId($0, for: scenario) }
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    
                    // Divider between rows (not after last)
                    if index < function.applicableScenarios.count - 1 {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
    }
    
    private func iconForFunction(_ function: LLMFunction) -> String {
        switch function {
        case .psst: return "sparkle"
        case .sessionDetection: return "ear.badge.waveform"
        case .finalSoap: return "checkmark.seal"
        case .chat: return "bubble.left.and.bubble.right"
        case .billing: return "dollarsign.circle"
        case .imageGeneration: return "photo.artframe"
        }
    }
    
    private func getModelId(for scenario: LLMScenario) -> String {
        let functionConfig = getFunctionConfig()
        let modelId: String?
        switch scenario {
        case .standard:
            modelId = functionConfig.standard
        case .large:
            modelId = functionConfig.large
        case .multimodal:
            modelId = functionConfig.multimodal
        case .backup:
            modelId = functionConfig.backup
        }
        return modelId ?? LLMModelRegistry.defaultModel(for: scenario, function: function).id
    }
    
    private func getFunctionConfig() -> FunctionLLMConfig {
        ensureLLMFunctionsConfig()
        switch function {
        case .psst:
            return config.llmFunctions?.psst ?? .defaultForPsst
        case .sessionDetection:
            return config.llmFunctions?.sessionDetection ?? .defaultForSessionDetection
        case .finalSoap:
            return config.llmFunctions?.finalSoap ?? .defaultForFinalSoap
        case .chat:
            return config.llmFunctions?.chat ?? .defaultForChat
        case .billing:
            return config.llmFunctions?.billing ?? .defaultForBilling
        case .imageGeneration:
            return config.llmFunctions?.imageGeneration ?? .defaultForImageGeneration
        }
    }
    
    private func setModelId(_ modelId: String, for scenario: LLMScenario) {
        ensureLLMFunctionsConfig()
        
        switch function {
        case .psst:
            if config.llmFunctions?.psst == nil {
                config.llmFunctions?.psst = .defaultForPsst
            }
            setModelOnConfig(&config.llmFunctions!.psst!, modelId: modelId, scenario: scenario)
        case .sessionDetection:
            if config.llmFunctions?.sessionDetection == nil {
                config.llmFunctions?.sessionDetection = .defaultForSessionDetection
            }
            setModelOnConfig(&config.llmFunctions!.sessionDetection!, modelId: modelId, scenario: scenario)
        case .finalSoap:
            if config.llmFunctions?.finalSoap == nil {
                config.llmFunctions?.finalSoap = .defaultForFinalSoap
            }
            setModelOnConfig(&config.llmFunctions!.finalSoap!, modelId: modelId, scenario: scenario)
        case .chat:
            if config.llmFunctions?.chat == nil {
                config.llmFunctions?.chat = .defaultForChat
            }
            setModelOnConfig(&config.llmFunctions!.chat!, modelId: modelId, scenario: scenario)
        case .billing:
            if config.llmFunctions?.billing == nil {
                config.llmFunctions?.billing = .defaultForBilling
            }
            setModelOnConfig(&config.llmFunctions!.billing!, modelId: modelId, scenario: scenario)
        case .imageGeneration:
            if config.llmFunctions?.imageGeneration == nil {
                config.llmFunctions?.imageGeneration = .defaultForImageGeneration
            }
            setModelOnConfig(&config.llmFunctions!.imageGeneration!, modelId: modelId, scenario: scenario)
        }
        
        hasChanges = true
    }
    
    private func setModelOnConfig(_ functionConfig: inout FunctionLLMConfig, modelId: String, scenario: LLMScenario) {
        switch scenario {
        case .standard:
            functionConfig.standard = modelId
        case .large:
            functionConfig.large = modelId
        case .multimodal:
            functionConfig.multimodal = modelId
        case .backup:
            functionConfig.backup = modelId
        }
    }
    
    private func ensureLLMFunctionsConfig() {
        if config.llmFunctions == nil {
            config.llmFunctions = .default
        }
    }
}

// MARK: - Scenario Model Row

struct ScenarioModelRow: View {
    let scenario: LLMScenario
    let function: LLMFunction
    let selectedModelId: String
    let availableModels: [LLMModelOption]
    let onSelect: (String) -> Void
    
    // Group models by provider for organized display
    private var modelsByProvider: [(provider: LLMProviderType, models: [LLMModelOption])] {
        let grouped = Dictionary(grouping: availableModels) { $0.provider }
        return LLMProviderType.allCases.compactMap { provider in
            if let models = grouped[provider], !models.isEmpty {
                return (provider, models)
            }
            return nil
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(scenario.displayName)
                Text(scenario.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Picker("", selection: Binding(
                get: { selectedModelId },
                set: { onSelect($0) }
            )) {
                ForEach(modelsByProvider, id: \.provider) { group in
                    Section(header: Text(group.provider.displayName)) {
                        ForEach(group.models) { model in
                            HStack {
                                Image(systemName: model.provider.icon)
                                Text(model.displayName)
                            }
                            .tag(model.id)
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 200)
        }
    }
}

// MARK: - Transcription Settings Tab

struct TranscriptionSettingsTab: View {
    @Binding var config: AppConfig
    @Binding var hasChanges: Bool
    
    var body: some View {
        Form {
            Section {
                Toggle("Use Streaming", isOn: Binding(
                    get: { config.deepgram?.useStreaming ?? true },
                    set: { 
                        ensureDeepgramConfig()
                        config.deepgram?.useStreaming = $0
                        hasChanges = true
                    }
                ))
                
                Toggle("Show Interim Results", isOn: Binding(
                    get: { config.deepgram?.interimResults ?? true },
                    set: { 
                        ensureDeepgramConfig()
                        config.deepgram?.interimResults = $0
                        hasChanges = true
                    }
                ))
                
                Toggle("Save Audio Backup", isOn: Binding(
                    get: { config.deepgram?.saveAudioBackup ?? true },
                    set: { 
                        ensureDeepgramConfig()
                        config.deepgram?.saveAudioBackup = $0
                        hasChanges = true
                    }
                ))
            } header: {
                Label("Deepgram Transcription", systemImage: "waveform.path")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Streaming provides real-time transcription as you speak.")
                    Text("Interim results show partial transcriptions before finalization.")
                    Text("Audio backup saves recordings for troubleshooting.")
                    Text("API key is configured in config.json.")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
    
    private func ensureDeepgramConfig() {
        if config.deepgram == nil {
            config.deepgram = .default
        }
    }
}

// MARK: - Timing Settings Tab

struct TimingSettingsTab: View {
    @Binding var config: AppConfig
    @Binding var hasChanges: Bool
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Transcription Interval")
                    Spacer()
                    TextField("", value: Binding(
                        get: { config.timing.transcriptionIntervalSeconds },
                        set: { config.timing.transcriptionIntervalSeconds = $0; hasChanges = true }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    Text("seconds")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Helper Update Interval")
                    Spacer()
                    TextField("", value: Binding(
                        get: { config.timing.helperUpdateIntervalSeconds },
                        set: { config.timing.helperUpdateIntervalSeconds = $0; hasChanges = true }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    Text("seconds")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("SOAP Update Interval")
                    Spacer()
                    TextField("", value: Binding(
                        get: { config.timing.soapUpdateIntervalSeconds },
                        set: { config.timing.soapUpdateIntervalSeconds = $0; hasChanges = true }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    Text("seconds")
                        .foregroundColor(.secondary)
                }
            } header: {
                Label("Update Intervals", systemImage: "timer")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Controls how often each component updates during an encounter.")
                    Text("Lower values = more responsive but more API calls.")
                    Text("Higher values = fewer API calls but less real-time updates.")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Auto-Detection Settings Tab

struct AutoDetectionSettingsTab: View {
    @Binding var config: AppConfig
    @Binding var hasChanges: Bool
    
    var body: some View {
        Form {
            Section {
                Toggle("Auto-Start Encounters", isOn: Binding(
                    get: { config.autoDetection?.enabled ?? false },
                    set: { 
                        ensureAutoDetectionConfig()
                        config.autoDetection?.enabled = $0
                        hasChanges = true
                    }
                ))
                
                Toggle("Auto-End Encounters", isOn: Binding(
                    get: { config.autoDetection?.detectEndOfEncounter ?? false },
                    set: { 
                        ensureAutoDetectionConfig()
                        config.autoDetection?.detectEndOfEncounter = $0
                        hasChanges = true
                    }
                ))
            } header: {
                Label("Auto-Detection", systemImage: "ear.badge.waveform")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-start detects when a clinical encounter begins.")
                    Text("Auto-end detects when an encounter is finished.")
                    Text("Both require a local model for Session Detection.")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            if config.autoDetection?.enabled == true {
                // Thresholds
                Section {
                    HStack {
                        Text("Silence Threshold")
                        Spacer()
                        TextField("", value: Binding(
                            get: { config.autoDetection?.silenceThresholdSeconds ?? 45 },
                            set: { config.autoDetection?.silenceThresholdSeconds = $0; hasChanges = true }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("seconds")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Min Encounter Duration")
                        Spacer()
                        TextField("", value: Binding(
                            get: { config.autoDetection?.minEncounterDurationSeconds ?? 60 },
                            set: { config.autoDetection?.minEncounterDurationSeconds = $0; hasChanges = true }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("seconds")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Speech Activity Threshold")
                        Spacer()
                        TextField("", value: Binding(
                            get: { config.autoDetection?.speechActivityThreshold ?? 0.02 },
                            set: { config.autoDetection?.speechActivityThreshold = $0; hasChanges = true }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    }
                    
                    HStack {
                        Text("Buffer Duration")
                        Spacer()
                        TextField("", value: Binding(
                            get: { config.autoDetection?.bufferDurationSeconds ?? 45 },
                            set: { config.autoDetection?.bufferDurationSeconds = $0; hasChanges = true }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("seconds")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("Thresholds", systemImage: "slider.horizontal.3")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Silence threshold: Time of silence before suggesting end.")
                        Text("Min duration: Minimum encounter length before auto-end.")
                        Text("Speech threshold: Audio level to detect speech (0.0-1.0).")
                        Text("Buffer duration: Time to collect audio before LLM analysis.")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
    
    private func ensureAutoDetectionConfig() {
        if config.autoDetection == nil {
            config.autoDetection = .default
        }
    }
}

#Preview {
    SettingsView(configManager: ConfigManager.shared)
        .frame(width: 650, height: 600)
}
