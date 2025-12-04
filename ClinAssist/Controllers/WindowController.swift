import AppKit
import SwiftUI

/// Manages the main application window
@MainActor
class WindowController: NSObject, NSWindowDelegate {
    
    // MARK: - Properties
    
    private var mainWindow: NSWindow?
    private weak var appDelegate: AppDelegate?
    
    // MARK: - Initialization
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init()
        setupMainWindow()
    }
    
    // MARK: - Setup
    
    private func setupMainWindow() {
        guard let appDelegate = appDelegate, let screen = NSScreen.main else { return }
        
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
        mainWindow?.delegate = self
        mainWindow?.minSize = NSSize(width: 320, height: 500)
        mainWindow?.maxSize = NSSize(width: 600, height: screen.frame.height)
        
        // Position on right edge
        mainWindow?.setFrameOrigin(NSPoint(x: windowX, y: windowY))
    }
    
    // MARK: - Window Management
    
    func showWindow() {
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        appDelegate?.isWindowVisible = true
    }
    
    func hideWindow() {
        mainWindow?.orderOut(nil)
        appDelegate?.isWindowVisible = false
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        appDelegate?.isWindowVisible = false
    }
}

