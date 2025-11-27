import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private var hotkeyManager: GlobalHotkeyManager?
    
    @Published var appState: AppState = .idle
    @Published var isWindowVisible: Bool = false
    @Published var encounterDuration: TimeInterval = 0
    @Published var showEndEncounterSheet: Bool = false
    
    // Managers
    let configManager = ConfigManager.shared
    let audioManager = AudioManager()
    lazy var encounterController: EncounterController = {
        EncounterController(audioManager: audioManager, configManager: configManager)
    }()
    
    private var encounterTimer: Timer?
    private var encounterStartTime: Date?
    
    // MARK: - App Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock
        NSApp.setActivationPolicy(.accessory)
        
        // Setup menu bar
        setupStatusItem()
        
        // Setup main window
        setupMainWindow()
        
        // Setup global hotkey
        setupGlobalHotkey()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.unregister()
        
        // Clean up any temp files if encounter was not saved
        if appState != .idle {
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
        
        // Show/Hide Window
        let windowItem: NSMenuItem
        if isWindowVisible {
            windowItem = NSMenuItem(title: "Hide Window", action: #selector(toggleWindow), keyEquivalent: "")
        } else {
            windowItem = NSMenuItem(title: "Show Window", action: #selector(toggleWindow), keyEquivalent: "")
        }
        windowItem.target = self
        menu.addItem(windowItem)
        
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
        mainWindow?.minSize = NSSize(width: 380, height: 500)
        mainWindow?.maxSize = NSSize(width: 380, height: screen.frame.height)
        
        // Position on right edge
        mainWindow?.setFrameOrigin(NSPoint(x: windowX, y: windowY))
    }
    
    // MARK: - Global Hotkey Setup
    
    private func setupGlobalHotkey() {
        hotkeyManager = GlobalHotkeyManager()
        // Control + Option + S (keycode 1 = 'S')
        hotkeyManager?.register(keyCode: 1, modifiers: [.control, .option]) { [weak self] in
            DispatchQueue.main.async {
                self?.toggleEncounter()
            }
        }
    }
    
    // MARK: - Actions
    
    @objc func toggleEncounter() {
        switch appState {
        case .idle:
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
                    do {
                        _ = try EncounterStorage.shared.saveEncounter(
                            state,
                            soapNote: encounterController.soapNote,
                            keepAudio: false
                        )
                    } catch {
                        print("Failed to save encounter: \(error)")
                    }
                }
                
                showEndEncounterSheet = true
                appState = .idle
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
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        isWindowVisible = false
        updateMenu()
    }
}
