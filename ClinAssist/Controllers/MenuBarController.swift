import AppKit

/// Manages the menu bar status item and its menu
@MainActor
class MenuBarController {
    
    // MARK: - Properties
    
    private var statusItem: NSStatusItem?
    private weak var appDelegate: AppDelegate?
    
    // MARK: - Initialization
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        setupStatusItem()
    }
    
    // MARK: - Setup
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "stethoscope", accessibilityDescription: "ClinAssist")
        }
        
        updateMenu()
    }
    
    // MARK: - Menu Updates
    
    func updateMenu() {
        guard let appDelegate = appDelegate else { return }
        
        let menu = NSMenu()
        
        // Start/End Encounter
        let encounterItem: NSMenuItem
        switch appDelegate.appState {
        case .idle:
            encounterItem = NSMenuItem(title: "Start Encounter", action: #selector(AppDelegate.toggleEncounter), keyEquivalent: "")
        case .monitoring:
            encounterItem = NSMenuItem(title: "Monitoring (Auto)", action: nil, keyEquivalent: "")
            encounterItem.isEnabled = false
            
            // Add manual start option
            let manualStartItem = NSMenuItem(title: "Start Encounter Manually", action: #selector(AppDelegate.toggleEncounter), keyEquivalent: "")
            manualStartItem.target = appDelegate
            menu.addItem(manualStartItem)
        case .buffering:
            encounterItem = NSMenuItem(title: "Detecting Speech...", action: nil, keyEquivalent: "")
            encounterItem.isEnabled = false
        case .recording, .paused:
            encounterItem = NSMenuItem(title: "End Encounter", action: #selector(AppDelegate.toggleEncounter), keyEquivalent: "")
        case .processing:
            encounterItem = NSMenuItem(title: "Processing...", action: nil, keyEquivalent: "")
            encounterItem.isEnabled = false
        }
        encounterItem.target = appDelegate
        menu.addItem(encounterItem)
        
        // Pause/Resume (only visible during active encounter)
        if appDelegate.appState == .recording || appDelegate.appState == .paused {
            let pauseItem: NSMenuItem
            if appDelegate.appState == .recording {
                pauseItem = NSMenuItem(title: "Pause", action: #selector(AppDelegate.togglePause), keyEquivalent: "")
            } else {
                pauseItem = NSMenuItem(title: "Resume", action: #selector(AppDelegate.togglePause), keyEquivalent: "")
            }
            pauseItem.target = appDelegate
            menu.addItem(pauseItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Auto-detection toggle
        let autoDetectItem = NSMenuItem(
            title: appDelegate.autoDetectionEnabled ? "Disable Auto-Detection" : "Enable Auto-Detection",
            action: #selector(AppDelegate.toggleAutoDetection),
            keyEquivalent: ""
        )
        autoDetectItem.target = appDelegate
        // Only allow toggling if not in an active encounter and config supports it
        autoDetectItem.isEnabled = !appDelegate.appState.isActive && appDelegate.configManager.config?.autoDetection != nil
        menu.addItem(autoDetectItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Show/Hide Window
        let windowItem: NSMenuItem
        if appDelegate.isWindowVisible {
            windowItem = NSMenuItem(title: "Hide Window", action: #selector(AppDelegate.toggleWindow), keyEquivalent: "")
        } else {
            windowItem = NSMenuItem(title: "Show Window", action: #selector(AppDelegate.toggleWindow), keyEquivalent: "")
        }
        windowItem.target = appDelegate
        menu.addItem(windowItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit ClinAssist", action: #selector(AppDelegate.quitApp), keyEquivalent: "q")
        quitItem.target = appDelegate
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    // MARK: - Status Icon Updates
    
    func updateStatusIcon() {
        guard let button = statusItem?.button, let appDelegate = appDelegate else { return }
        
        switch appDelegate.appState {
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
}

