import AppKit
import Carbon.HIToolbox

class GlobalHotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var callback: (() -> Void)?
    private var targetKeyCode: UInt16 = 0
    private var targetModifiers: NSEvent.ModifierFlags = []
    
    struct Modifiers: OptionSet {
        let rawValue: Int
        
        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let command = Modifiers(rawValue: 1 << 2)
        static let shift = Modifiers(rawValue: 1 << 3)
    }
    
    func register(keyCode: UInt16, modifiers: Modifiers, callback: @escaping () -> Void) {
        self.callback = callback
        self.targetKeyCode = keyCode
        
        // Convert our modifiers to NSEvent.ModifierFlags
        var nsModifiers: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { nsModifiers.insert(.control) }
        if modifiers.contains(.option) { nsModifiers.insert(.option) }
        if modifiers.contains(.command) { nsModifiers.insert(.command) }
        if modifiers.contains(.shift) { nsModifiers.insert(.shift) }
        self.targetModifiers = nsModifiers
        
        // Request accessibility permissions
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        
        if !trusted {
            print("ClinAssist needs accessibility permissions to register global hotkeys.")
            print("Please grant access in System Settings > Privacy & Security > Accessibility")
            return
        }
        
        setupEventTap()
    }
    
    private func setupEventTap() {
        // Create event tap for key down events
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                
                if type == .keyDown {
                    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                    let flags = event.flags
                    
                    // Check if this matches our target hotkey
                    // Control + Option + S (keycode 1 is 'S')
                    let hasControl = flags.contains(.maskControl)
                    let hasOption = flags.contains(.maskAlternate)
                    let hasCommand = flags.contains(.maskCommand)
                    let hasShift = flags.contains(.maskShift)
                    
                    let wantsControl = manager.targetModifiers.contains(.control)
                    let wantsOption = manager.targetModifiers.contains(.option)
                    let wantsCommand = manager.targetModifiers.contains(.command)
                    let wantsShift = manager.targetModifiers.contains(.shift)
                    
                    if keyCode == manager.targetKeyCode &&
                       hasControl == wantsControl &&
                       hasOption == wantsOption &&
                       hasCommand == wantsCommand &&
                       hasShift == wantsShift {
                        manager.callback?()
                        return nil // Consume the event
                    }
                }
                
                return Unmanaged.passRetained(event)
            },
            userInfo: refcon
        )
        
        guard let eventTap = eventTap else {
            print("Failed to create event tap. Please check accessibility permissions.")
            return
        }
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        
        if let runLoopSource = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }
    
    func unregister() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        callback = nil
    }
    
    deinit {
        unregister()
    }
}

