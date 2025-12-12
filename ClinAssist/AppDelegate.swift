import AppKit
import SwiftUI
import AVFoundation

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem?
    private var hotkeyManager: GlobalHotkeyManager?
    
    // Window coordinator handles all window management
    private var windowCoordinator: WindowCoordinator?
    
    @Published var appState: AppState = .idle
    @Published var isWindowVisible: Bool = false
    @Published var encounterDuration: TimeInterval = 0
    @Published var showEndEncounterSheet: Bool = false
    @Published var capturedSoapNote: String = ""  // Captured at encounter end, not cleared by new provisional recording
    @Published var autoDetectionEnabled: Bool = false
    @Published var silenceDuration: TimeInterval = 0
    @Published var showAutoEndConfirmation: Bool = false
    
    // Managers
    let configManager = ConfigManager.shared
    let audioManager: AudioManager
    lazy var encounterController: EncounterController = {
        let controller: EncounterController
        if UITestingSupport.isUITesting {
            controller = EncounterController(
                audioManager: audioManager,
                configManager: configManager,
                sttClient: UITestingSTTClient(),
                streamingClient: UITestingStreamingClient(),
                llmClient: UITestingLLMClient(apiKey: "uitest", model: "uitest"),
                ollamaClient: nil
            )
        } else {
            controller = EncounterController(audioManager: audioManager, configManager: configManager)
        }
        controller.delegate = self
        return controller
    }()
    
    private var encounterTimer: Timer?
    private var encounterStartTime: Date?
    private var silenceUpdateTimer: Timer?
    
    private var configDidChangeObserver: Any?
    
    override init() {
        if UITestingSupport.isUITesting {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("ClinAssistUITestTemp")
            self.audioManager = AudioManager(
                engineFactory: UITestingAudioEngineFactory(),
                permissionProvider: UITestingPermissionProvider(),
                tempBasePath: temp
            )
        } else {
            self.audioManager = AudioManager()
        }
        super.init()
    }
    
    // MARK: - App Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock
        NSApp.setActivationPolicy(.accessory)
        
        // UI tests: avoid system permission prompts and ensure the app is "configured".
        if UITestingSupport.isUITesting {
            if configManager.config == nil {
                var cfg = AppConfig.default
                cfg.openrouterApiKey = "uitest"
                cfg.deepgramApiKey = "uitest"
                cfg.model = "openai/gpt-4o-mini"
                cfg.autoDetection?.enabled = false
                cfg.deepgram?.useStreaming = true
                configManager.config = cfg
                configManager.configError = nil
            }
            audioManager.permissionGranted = true
            audioManager.permissionError = nil
        } else {
            // Request microphone permission immediately on launch
            requestMicrophonePermission()
            
            // Request camera permission at launch (for chat image capture feature)
            requestCameraPermission()
        }
        
        // Setup menu bar
        setupStatusItem()
        
        // Setup window coordinator
        windowCoordinator = WindowCoordinator(configManager: configManager)
        windowCoordinator?.setAppDelegate(self)
        windowCoordinator?.setupMainWindow()
        
        // Setup global hotkey
        setupGlobalHotkey()
        
        // Listen for config updates (Settings save) so toggles take effect immediately.
        configDidChangeObserver = NotificationCenter.default.addObserver(
            forName: .clinAssistConfigDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigDidChange()
        }
        
        // Check if auto-detection should be enabled
        autoDetectionEnabled = configManager.isAutoDetectionEnabled
        NSLog("[AppDelegate] Auto-detection enabled from config: %@", autoDetectionEnabled ? "YES" : "NO")
        
        // Auto-detection will be started after microphone permission is confirmed
        // See startAutoDetectionIfReady()
        
        // Show the main window on app launch
        showWindow()
    }
    
    private func handleConfigDidChange() {
        // Treat config auto_detection.enabled as the desired runtime state.
        let shouldEnable = configManager.isAutoDetectionEnabled
        
        if shouldEnable && !autoDetectionEnabled {
            // If user enabled auto-detection via Settings, start it (if permissions allow).
            autoDetectionEnabled = true
            startAutoDetectionIfReady()
        } else if !shouldEnable && autoDetectionEnabled {
            // If user disabled auto-detection via Settings, stop monitoring mode.
            autoDetectionEnabled = false
            if appState == .monitoring || appState == .buffering {
                stopAutoDetection()
            } else {
                stopSilenceUpdateTimer()
                silenceDuration = 0
                updateMenu()
                updateStatusIcon()
            }
        } else {
            // No change; just refresh menu labels.
            updateMenu()
        }
    }
    
    /// Start auto-detection only if enabled and microphone permission is granted
    private func startAutoDetectionIfReady() {
        guard autoDetectionEnabled else { return }
        guard audioManager.permissionGranted else {
            NSLog("[AppDelegate] Waiting for microphone permission before starting auto-detection")
            return
        }
        
        NSLog("[AppDelegate] Starting auto-detection (permission granted)...")
        startAutoDetection()
    }
    
    private func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            // Request permission - this will show the system dialog
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async { [weak self] in
                    if granted {
                        debugLog("Microphone permission granted", component: "AppDelegate")
                        self?.audioManager.checkPermissions()
                        // Now that permission is granted, start auto-detection if enabled
                        self?.startAutoDetectionIfReady()
                    } else {
                        debugLog("Microphone permission denied", component: "AppDelegate")
                        self?.showWindow() // Show window to display the permission warning
                    }
                }
            }
        case .denied, .restricted:
            // Permission was denied - show the window with warning
            DispatchQueue.main.async { [weak self] in
                self?.showWindow()
            }
        case .authorized:
            debugLog("Microphone already authorized", component: "AppDelegate")
            audioManager.checkPermissions()
            // Permission already granted, start auto-detection if enabled
            DispatchQueue.main.async { [weak self] in
                self?.startAutoDetectionIfReady()
            }
        @unknown default:
            break
        }
    }
    
    private func requestCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            // Request permission - this will show the system dialog
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        debugLog("Camera permission granted", component: "AppDelegate")
                    } else {
                        debugLog("Camera permission denied", component: "AppDelegate")
                    }
                }
            }
        case .denied, .restricted:
            debugLog("Camera permission denied/restricted", component: "AppDelegate")
        case .authorized:
            debugLog("Camera already authorized", component: "AppDelegate")
        @unknown default:
            break
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let observer = configDidChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        hotkeyManager?.unregister()
        
        // Stop monitoring if active
        if appState == .monitoring {
            encounterController.stopMonitoring()
        }
        
        // Clean up any temp files if encounter was not saved
        if appState.isActive {
            if let encounterId = encounterController.state?.id {
                EncounterStorage.shared.cleanupTempFolder(for: encounterId)
            }
        }
    }
    
    // MARK: - Status Item Setup
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "stethoscope", accessibilityDescription: "ClinAssist")
        }
        
        updateMenu()
    }
    
    private func updateMenu() {
        let menu = NSMenu()
        
        // Start/End Encounter
        let encounterItem: NSMenuItem
        switch appState {
        case .idle:
            encounterItem = NSMenuItem(title: "Start Encounter", action: #selector(toggleEncounter), keyEquivalent: "")
        case .monitoring:
            encounterItem = NSMenuItem(title: "Monitoring (Auto)", action: nil, keyEquivalent: "")
            encounterItem.isEnabled = false
            
            // Add manual start option
            let manualStartItem = NSMenuItem(title: "Start Encounter Manually", action: #selector(toggleEncounter), keyEquivalent: "")
            manualStartItem.target = self
            menu.addItem(manualStartItem)
        case .buffering:
            encounterItem = NSMenuItem(title: "Detecting Speech...", action: nil, keyEquivalent: "")
            encounterItem.isEnabled = false
        case .recording, .paused:
            encounterItem = NSMenuItem(title: "End Encounter", action: #selector(toggleEncounter), keyEquivalent: "")
        case .processing:
            encounterItem = NSMenuItem(title: "Processing...", action: nil, keyEquivalent: "")
            encounterItem.isEnabled = false
        }
        encounterItem.target = self
        menu.addItem(encounterItem)
        
        // Pause/Resume (only visible during active encounter)
        if appState == .recording || appState == .paused {
            let pauseItem: NSMenuItem
            if appState == .recording {
                pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
            } else {
                pauseItem = NSMenuItem(title: "Resume", action: #selector(togglePause), keyEquivalent: "")
            }
            pauseItem.target = self
            menu.addItem(pauseItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Auto-detection toggle
        let autoDetectItem = NSMenuItem(
            title: autoDetectionEnabled ? "Disable Auto-Detection" : "Enable Auto-Detection",
            action: #selector(toggleAutoDetection),
            keyEquivalent: ""
        )
        autoDetectItem.target = self
        // Only allow toggling if not in an active encounter and config supports it
        autoDetectItem.isEnabled = !appState.isActive && configManager.config?.autoDetection != nil
        menu.addItem(autoDetectItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Show/Hide Window
        let windowItem: NSMenuItem
        if isWindowVisible {
            windowItem = NSMenuItem(title: "Hide Window", action: #selector(toggleWindow), keyEquivalent: "")
        } else {
            windowItem = NSMenuItem(title: "Show Window", action: #selector(toggleWindow), keyEquivalent: "")
        }
        windowItem.target = self
        menu.addItem(windowItem)
        
        // Session History
        let historyItem = NSMenuItem(title: "Session History...", action: #selector(showSessionHistory), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)
        
        // Medication Lookup
        let medicationItem = NSMenuItem(title: "Medication Lookup...", action: #selector(showMedicationLookup), keyEquivalent: "m")
        medicationItem.target = self
        menu.addItem(medicationItem)
        
        // Update Drug Database
        let updateDbItem = NSMenuItem(title: "Update Drug Database...", action: #selector(showDatabaseUpdateWindow), keyEquivalent: "")
        updateDbItem.target = self
        menu.addItem(updateDbItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit ClinAssist", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    
    // MARK: - Global Hotkey Setup
    
    private func setupGlobalHotkey() {
        hotkeyManager = GlobalHotkeyManager()
        // Control + Option + S (keycode 1 = 'S')
        hotkeyManager?.register(keyCode: 1, modifiers: [.control, .option]) { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.toggleEncounter()
            }
        }
    }
    
    // MARK: - Actions
    
    @objc func toggleEncounter() {
        switch appState {
        case .idle:
            startEncounter()
        case .monitoring, .buffering:
            // Manual start from monitoring mode
            startEncounter()
        case .recording, .paused:
            endEncounter()
        case .processing:
            break // Do nothing while processing
        }
    }
    
    @objc func togglePause() {
        switch appState {
        case .recording:
            appState = .paused
            encounterController.pauseEncounter()
            stopEncounterTimer()
        case .paused:
            appState = .recording
            encounterController.resumeEncounter()
            startEncounterTimer()
        default:
            break
        }
        updateMenu()
        updateStatusIcon()
    }
    
    @objc func toggleAutoDetection() {
        if autoDetectionEnabled {
            stopAutoDetection()
        } else {
            startAutoDetection()
        }
    }
    
    @objc func toggleWindow() {
        if isWindowVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Auto-Detection
    
    func startAutoDetection() {
        guard !appState.isActive else { return }
        guard configManager.config?.autoDetection?.enabled == true else {
            print("[AppDelegate] Auto-detection not enabled in config")
            return
        }
                
        // Attempt to start monitoring; only enter monitoring state if it actually started.
        let started = encounterController.startMonitoring()
        guard started else {
            autoDetectionEnabled = false
            appState = .idle
            stopSilenceUpdateTimer()
            silenceDuration = 0
            updateMenu()
            updateStatusIcon()
            print("[AppDelegate] Auto-detection failed to start")
            return
        }
        
        autoDetectionEnabled = true
        appState = .monitoring
        
        // Start silence duration tracking
        startSilenceUpdateTimer()
        
        updateMenu()
        updateStatusIcon()
        
        print("[AppDelegate] Started auto-detection mode")
    }
    
    func stopAutoDetection() {
        guard appState == .monitoring || appState == .buffering else { return }
        
        autoDetectionEnabled = false
        encounterController.stopMonitoring()
        appState = .idle
        
        stopSilenceUpdateTimer()
        silenceDuration = 0
        
        updateMenu()
        updateStatusIcon()
        
        print("[AppDelegate] Stopped auto-detection mode")
    }
    
    private func startSilenceUpdateTimer() {
        silenceUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.silenceDuration = self.encounterController.sessionDetector.currentSilenceDuration
        }
    }
    
    private func stopSilenceUpdateTimer() {
        silenceUpdateTimer?.invalidate()
        silenceUpdateTimer = nil
    }
    
    // MARK: - Encounter Management
    
    func startEncounter() {
        guard configManager.isConfigured else {
            showWindow()
            return
        }
        
        appState = .recording
        encounterStartTime = Date()
        encounterDuration = 0
        
        encounterController.startEncounter()
        startEncounterTimer()
        showWindow()
        updateMenu()
        updateStatusIcon()
    }
    
    func endEncounter() {
        appState = .processing
        stopEncounterTimer()
        updateMenu()
        updateStatusIcon()
        
        Task {
            await encounterController.endEncounter()
            
            await MainActor.run {
                // Save the encounter
                if let state = encounterController.state {
                    let soapNote = encounterController.soapNote
                    
                    // IMPORTANT: Capture the SOAP note before showing the sheet
                    // This prevents it from being cleared if auto-detection triggers a new provisional recording
                    capturedSoapNote = soapNote
                    
                    do {
                        _ = try EncounterStorage.shared.saveEncounter(
                            state,
                            soapNote: soapNote,
                            keepAudio: false
                        )
                    } catch {
                        print("Failed to save encounter: \(error)")
                    }
                    
                    // Append to daily record
                    let patientIdentifier = EncounterStorage.shared.extractPatientIdentifier(from: soapNote)
                    EncounterStorage.shared.appendToDailyRecord(
                        state: state,
                        soapNote: soapNote,
                        patientIdentifier: patientIdentifier
                    )
                }
                
                showEndEncounterSheet = true
                
                // Return to monitoring if auto-detection is enabled
                if autoDetectionEnabled {
                    appState = .monitoring
                    // IMPORTANT: Restart monitoring in the controller to reset SessionDetector state
                    _ = encounterController.startMonitoring()
                    // Restart silence tracking
                    startSilenceUpdateTimer()
                } else {
                    appState = .idle
                }
                
                encounterStartTime = nil
                encounterDuration = 0
                updateMenu()
                updateStatusIcon()
            }
        }
    }
    
    func dismissEndEncounterSheet() {
        showEndEncounterSheet = false
    }
    
    private func startEncounterTimer() {
        encounterTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.encounterStartTime else { return }
            if self.appState == .recording {
                self.encounterDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func stopEncounterTimer() {
        encounterTimer?.invalidate()
        encounterTimer = nil
    }
    
    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        
        switch appState {
        case .idle:
            button.image = NSImage(systemSymbolName: "stethoscope", accessibilityDescription: "ClinAssist")
        case .monitoring:
            button.image = NSImage(systemSymbolName: "ear.badge.waveform", accessibilityDescription: "ClinAssist - Monitoring")
        case .buffering:
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "ClinAssist - Detecting")
        case .recording:
            button.image = NSImage(systemSymbolName: "stethoscope.circle.fill", accessibilityDescription: "ClinAssist - Recording")
        case .paused:
            button.image = NSImage(systemSymbolName: "stethoscope.circle", accessibilityDescription: "ClinAssist - Paused")
        case .processing:
            button.image = NSImage(systemSymbolName: "stethoscope", accessibilityDescription: "ClinAssist - Processing")
        }
    }
    
    // MARK: - Window Management
    
    func showWindow() {
        windowCoordinator?.showMainWindow()
        isWindowVisible = true
        updateMenu()
    }
    
    func hideWindow() {
        windowCoordinator?.hideMainWindow()
        isWindowVisible = false
        updateMenu()
    }
    
    // MARK: - Session History Window
    
    @objc func showSessionHistory() {
        windowCoordinator?.showSessionHistoryWindow()
    }
    
    // MARK: - Medication Lookup Window
    
    @objc func showMedicationLookup() {
        windowCoordinator?.showMedicationLookupWindow()
    }
    
    // MARK: - Drug Database Update Window
    
    @objc func showDatabaseUpdateWindow() {
        windowCoordinator?.showDatabaseUpdateWindow()
    }
    
    // MARK: - Settings Window
    
    @objc func showSettings() {
        windowCoordinator?.showSettingsWindow()
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        isWindowVisible = false
        updateMenu()
    }
}

// MARK: - EncounterControllerDelegate

extension AppDelegate: EncounterControllerDelegate {
    func encounterControllerDidAutoStart(_ controller: EncounterController) {
        // Auto-detection triggered start
        print("[AppDelegate] Auto-start triggered!")
        
        appState = .recording
        encounterStartTime = Date()
        encounterDuration = 0
        
        // The controller already started the encounter, just update UI
        startEncounterTimer()
        showWindow()
        updateMenu()
        updateStatusIcon()
        
        // Stop silence tracking during recording
        stopSilenceUpdateTimer()
    }
    
    func encounterControllerDidAutoEnd(_ controller: EncounterController) {
        // Auto-detection triggered end - show confirmation
        // Recording continues in background until confirmed
        print("[AppDelegate] Auto-end detected - showing confirmation...")
        
        showAutoEndConfirmation = true
        showWindow() // Make sure window is visible for the dialog
    }
    
    // MARK: - Auto-End Confirmation Handlers
    
    func confirmAutoEnd() {
        print("[AppDelegate] Auto-end confirmed by user")
        showAutoEndConfirmation = false
        endEncounter()
    }
    
    func cancelAutoEnd() {
        print("[AppDelegate] Auto-end cancelled by user - continuing encounter")
        showAutoEndConfirmation = false
        
        // Reset the session detector so it can detect end again later
        encounterController.sessionDetector.resetEndDetection()
    }
}
