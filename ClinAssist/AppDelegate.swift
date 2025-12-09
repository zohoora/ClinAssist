import AppKit
import SwiftUI
import AVFoundation

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private var sessionHistoryWindow: NSWindow?
    private var medicationLookupWindow: NSWindow?
    private var databaseUpdateWindow: NSWindow?
    private var hotkeyManager: GlobalHotkeyManager?
    
    // Database builder for updating drug database
    private var databaseBuilder: DrugDatabaseBuilder?
    
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
    let audioManager = AudioManager()
    lazy var encounterController: EncounterController = {
        let controller = EncounterController(audioManager: audioManager, configManager: configManager)
        controller.delegate = self
        return controller
    }()
    
    private var encounterTimer: Timer?
    private var encounterStartTime: Date?
    private var silenceUpdateTimer: Timer?
    
    // MARK: - App Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock
        NSApp.setActivationPolicy(.accessory)
        
        // Request microphone permission immediately on launch
        requestMicrophonePermission()
        
        // Request camera permission at launch (for chat image capture feature)
        requestCameraPermission()
        
        // Setup menu bar
        setupStatusItem()
        
        // Setup main window
        setupMainWindow()
        
        // Setup global hotkey
        setupGlobalHotkey()
        
        // Check if auto-detection should be enabled
        autoDetectionEnabled = configManager.isAutoDetectionEnabled
        NSLog("[AppDelegate] Auto-detection enabled from config: %@", autoDetectionEnabled ? "YES" : "NO")
        
        // Auto-detection will be started after microphone permission is confirmed
        // See startAutoDetectionIfReady()
        
        // Show the main window on app launch
        showWindow()
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
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit ClinAssist", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    // MARK: - Main Window Setup
    
    private func setupMainWindow() {
        guard let screen = NSScreen.main else { return }
        
        let windowWidth: CGFloat = 380
        let windowHeight = screen.visibleFrame.height
        let windowX = screen.visibleFrame.maxX - windowWidth
        let windowY = screen.visibleFrame.minY
        
        let contentView = MainWindowView(appDelegate: self)
        
        mainWindow = NSWindow(
            contentRect: NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        mainWindow?.title = "ClinAssist"
        mainWindow?.contentView = NSHostingView(rootView: contentView)
        mainWindow?.isReleasedWhenClosed = false
        mainWindow?.delegate = self
        mainWindow?.minSize = NSSize(width: 320, height: 500)
        mainWindow?.maxSize = NSSize(width: 600, height: screen.frame.height)
        
        // Position on right edge
        mainWindow?.setFrameOrigin(NSPoint(x: windowX, y: windowY))
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
        
        autoDetectionEnabled = true
        appState = .monitoring
        encounterController.startMonitoring()
        
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
                    encounterController.startMonitoring()
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
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isWindowVisible = true
        updateMenu()
    }
    
    func hideWindow() {
        mainWindow?.orderOut(nil)
        isWindowVisible = false
        updateMenu()
    }
    
    // MARK: - Session History Window
    
    @objc func showSessionHistory() {
        if sessionHistoryWindow == nil {
            setupSessionHistoryWindow()
        }
        
        sessionHistoryWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func setupSessionHistoryWindow() {
        guard let screen = NSScreen.main else { return }
        
        let windowWidth: CGFloat = 950
        let windowHeight: CGFloat = 650
        let windowX = (screen.visibleFrame.width - windowWidth) / 2 + screen.visibleFrame.minX
        let windowY = (screen.visibleFrame.height - windowHeight) / 2 + screen.visibleFrame.minY
        
        // Create LLM provider for SOAP regeneration and billing code generation
        let llmProvider: LLMProvider
        if configManager.isGroqEnabled {
            llmProvider = GroqClient(apiKey: configManager.groqApiKey, model: configManager.groqModel)
        } else if let config = configManager.config, !config.openrouterApiKey.isEmpty {
            llmProvider = LLMClient(apiKey: config.openrouterApiKey)
        } else {
            // Fallback - SOAP regeneration and billing codes won't work without API key
            llmProvider = GroqClient(apiKey: "")
        }
        
        let contentView = SessionHistoryView(llmProvider: llmProvider, configManager: configManager)
        
        sessionHistoryWindow = NSWindow(
            contentRect: NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        sessionHistoryWindow?.title = "Session History"
        sessionHistoryWindow?.contentView = NSHostingView(rootView: contentView)
        sessionHistoryWindow?.isReleasedWhenClosed = false
        sessionHistoryWindow?.minSize = NSSize(width: 800, height: 550)
        sessionHistoryWindow?.center()
    }
    
    // MARK: - Medication Lookup Window
    
    @objc func showMedicationLookup() {
        if medicationLookupWindow == nil {
            setupMedicationLookupWindow()
        }
        
        medicationLookupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func setupMedicationLookupWindow() {
        guard let screen = NSScreen.main else { return }
        
        let windowWidth: CGFloat = 900
        let windowHeight: CGFloat = 600
        let windowX = (screen.visibleFrame.width - windowWidth) / 2 + screen.visibleFrame.minX
        let windowY = (screen.visibleFrame.height - windowHeight) / 2 + screen.visibleFrame.minY
        
        let contentView = MedicationLookupView()
        
        medicationLookupWindow = NSWindow(
            contentRect: NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        medicationLookupWindow?.title = "Medication Lookup"
        medicationLookupWindow?.contentView = NSHostingView(rootView: contentView)
        medicationLookupWindow?.isReleasedWhenClosed = false
        medicationLookupWindow?.minSize = NSSize(width: 700, height: 500)
        medicationLookupWindow?.center()
    }
    
    // MARK: - Drug Database Update Window
    
    @objc func showDatabaseUpdateWindow() {
        if databaseUpdateWindow == nil {
            setupDatabaseUpdateWindow()
        }
        
        databaseUpdateWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func setupDatabaseUpdateWindow() {
        guard let screen = NSScreen.main else { return }
        
        let windowWidth: CGFloat = 500
        let windowHeight: CGFloat = 300
        let windowX = (screen.visibleFrame.width - windowWidth) / 2 + screen.visibleFrame.minX
        let windowY = (screen.visibleFrame.height - windowHeight) / 2 + screen.visibleFrame.minY
        
        // Create builder if needed
        if databaseBuilder == nil {
            databaseBuilder = DrugDatabaseBuilder()
        }
        
        let contentView = DatabaseUpdateView(builder: databaseBuilder!)
        
        databaseUpdateWindow = NSWindow(
            contentRect: NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        databaseUpdateWindow?.title = "Update Drug Database"
        databaseUpdateWindow?.contentView = NSHostingView(rootView: contentView)
        databaseUpdateWindow?.isReleasedWhenClosed = false
        databaseUpdateWindow?.center()
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
