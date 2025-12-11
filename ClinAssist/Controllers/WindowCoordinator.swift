import AppKit
import SwiftUI

/// Coordinates all window creation and management for the application
/// Extracted from AppDelegate to improve separation of concerns
@MainActor
class WindowCoordinator {
    
    // MARK: - Windows
    
    private var mainWindow: NSWindow?
    private var sessionHistoryWindow: NSWindow?
    private var medicationLookupWindow: NSWindow?
    private var databaseUpdateWindow: NSWindow?
    private var settingsWindow: NSWindow?
    
    // MARK: - Dependencies
    
    private weak var appDelegate: AppDelegate?
    private let configManager: ConfigManager
    private var databaseBuilder: DrugDatabaseBuilder?
    
    // MARK: - Initialization
    
    init(configManager: ConfigManager) {
        self.configManager = configManager
    }
    
    /// Set the app delegate reference (called after AppDelegate is fully initialized)
    func setAppDelegate(_ appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }
    
    // MARK: - Main Window
    
    func setupMainWindow() {
        guard let appDelegate = appDelegate else {
            debugLog("❌ Cannot setup main window - appDelegate not set", component: "WindowCoordinator")
            return
        }
        
        guard let screen = NSScreen.main else { return }
        
        let windowWidth: CGFloat = 380
        let windowHeight = screen.visibleFrame.height
        let windowX = screen.visibleFrame.maxX - windowWidth
        let windowY = screen.visibleFrame.minY
        
        let contentView = MainWindowView(appDelegate: appDelegate)
        
        mainWindow = NSWindow(
            contentRect: NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        mainWindow?.title = "ClinAssist"
        mainWindow?.contentView = NSHostingView(rootView: contentView)
        mainWindow?.isReleasedWhenClosed = false
        mainWindow?.delegate = appDelegate
        mainWindow?.minSize = NSSize(width: 320, height: 500)
        mainWindow?.maxSize = NSSize(width: 600, height: screen.frame.height)
        
        // Position on right edge
        mainWindow?.setFrameOrigin(NSPoint(x: windowX, y: windowY))
    }
    
    func showMainWindow() {
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func hideMainWindow() {
        mainWindow?.orderOut(nil)
    }
    
    var isMainWindowVisible: Bool {
        mainWindow?.isVisible ?? false
    }
    
    // MARK: - Session History Window
    
    func showSessionHistoryWindow() {
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
        
        // SessionHistoryView uses LLMOrchestrator internally for SOAP regeneration
        let contentView = SessionHistoryView(configManager: configManager)
        
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
    
    func showMedicationLookupWindow() {
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
    
    // MARK: - Database Update Window
    
    func showDatabaseUpdateWindow() {
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
    
    // MARK: - Settings Window
    
    func showSettingsWindow() {
        // Always recreate the window to ensure fresh config state
        setupSettingsWindow()
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func setupSettingsWindow() {
        guard let screen = NSScreen.main else { return }
        
        let windowWidth: CGFloat = 650
        let windowHeight: CGFloat = 550
        let windowX = (screen.visibleFrame.width - windowWidth) / 2 + screen.visibleFrame.minX
        let windowY = (screen.visibleFrame.height - windowHeight) / 2 + screen.visibleFrame.minY
        
        let contentView = SettingsView(configManager: configManager)
        
        settingsWindow = NSWindow(
            contentRect: NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        settingsWindow?.title = "Settings"
        settingsWindow?.contentView = NSHostingView(rootView: contentView)
        settingsWindow?.isReleasedWhenClosed = false
        settingsWindow?.minSize = NSSize(width: 600, height: 500)
        settingsWindow?.center()
    }
}
