import SwiftUI

@main
struct ClinAssistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Empty settings scene - we use menu bar only
        Settings {
            EmptyView()
        }
    }
}

