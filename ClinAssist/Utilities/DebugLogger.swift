import Foundation

/// Log level for categorizing messages
enum LogLevel: String {
    case info = "ℹ️"
    case warning = "⚠️"
    case error = "❌"
    case debug = "🔍"
    
    var prefix: String { rawValue }
}

/// Centralized debug logger that writes to a file for easy inspection
/// Logs are written to ~/Dropbox/livecode_records/debug.log
class DebugLogger {
    static let shared = DebugLogger()
    
    private let logFile: URL
    private let queue = DispatchQueue(label: "com.clinassist.debuglogger", qos: .utility)
    private let dateFormatter: DateFormatter
    
    private init() {
        let dropboxPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Dropbox")
            .appendingPathComponent("livecode_records")
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: dropboxPath, withIntermediateDirectories: true)
        
        logFile = dropboxPath.appendingPathComponent("debug.log")
        
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        
        // Clear old log on app start
        clearLog()
        
        // Write startup header
        log("═══════════════════════════════════════════════════════════════", level: .info)
        log("ClinAssist Debug Log - Started at \(ISO8601DateFormatter().string(from: Date()))", level: .info)
        log("═══════════════════════════════════════════════════════════════", level: .info)
    }
    
    /// Log a message with optional component tag and level
    func log(_ message: String, component: String? = nil, level: LogLevel = .info) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let timestamp = self.dateFormatter.string(from: Date())
            let componentPrefix = component.map { "[\($0)] " } ?? ""
            let line = "[\(timestamp)] \(componentPrefix)\(message)\n"
            
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logFile.path) {
                    if let handle = try? FileHandle(forWritingTo: self.logFile) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: self.logFile)
                }
            }
            
            // Also print to console for Xcode debugging
            print(line.trimmingCharacters(in: .newlines))
        }
    }
    
    /// Clear the log file
    func clearLog() {
        try? FileManager.default.removeItem(at: logFile)
    }
    
    /// Get the log file path for display
    var logFilePath: String {
        logFile.path
    }
}

// MARK: - Convenience Global Functions

/// Global logging function - use this throughout the app
/// Example: debugLog("Starting encounter", component: "EncounterController")
func debugLog(_ message: String, component: String? = nil, type: LogLevel = .info) {
    DebugLogger.shared.log(message, component: component, level: type)
}

/// Log an info message
func logInfo(_ message: String, component: String? = nil) {
    DebugLogger.shared.log(message, component: component, level: .info)
}

/// Log a warning message
func logWarning(_ message: String, component: String? = nil) {
    DebugLogger.shared.log("⚠️ \(message)", component: component, level: .warning)
}

/// Log an error message
func logError(_ message: String, component: String? = nil) {
    DebugLogger.shared.log("❌ \(message)", component: component, level: .error)
}

