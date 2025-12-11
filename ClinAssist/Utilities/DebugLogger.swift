import Foundation

/// Log level for categorizing messages
enum LogLevel: Int, Comparable {
    case debug = 0    // Most verbose - development only
    case info = 1     // General information
    case warning = 2  // Potential issues
    case error = 3    // Errors that need attention
    case none = 4     // Disable all logging
    
    var prefix: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        case .none: return ""
        }
    }
    
    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .none: return ""
        }
    }
    
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Configuration for the debug logger
struct LoggerConfiguration {
    /// Minimum log level to output (messages below this level are ignored)
    var minimumLevel: LogLevel
    
    /// Whether to include emojis in log output
    var includeEmojis: Bool
    
    /// Whether to write logs to file
    var writeToFile: Bool
    
    /// Whether to print to console (Xcode debug area)
    var printToConsole: Bool
    
    /// Maximum file size in bytes before rotation (default 5MB)
    var maxFileSize: Int
    
    /// Components to filter (empty means log all components)
    var allowedComponents: Set<String>
    
    /// Components to exclude from logging
    var excludedComponents: Set<String>
    
    /// Default configuration for debug builds
    static var debug: LoggerConfiguration {
        LoggerConfiguration(
            minimumLevel: .debug,
            includeEmojis: true,
            writeToFile: true,
            printToConsole: true,
            maxFileSize: 5 * 1024 * 1024,  // 5MB
            allowedComponents: [],
            excludedComponents: []
        )
    }
    
    /// Default configuration for release builds
    static var release: LoggerConfiguration {
        LoggerConfiguration(
            minimumLevel: .warning,
            includeEmojis: false,
            writeToFile: true,
            printToConsole: false,
            maxFileSize: 2 * 1024 * 1024,  // 2MB
            allowedComponents: [],
            excludedComponents: []
        )
    }
    
    /// Minimal logging - errors only
    static var minimal: LoggerConfiguration {
        LoggerConfiguration(
            minimumLevel: .error,
            includeEmojis: false,
            writeToFile: true,
            printToConsole: false,
            maxFileSize: 1024 * 1024,  // 1MB
            allowedComponents: [],
            excludedComponents: []
        )
    }
}

/// Centralized debug logger that writes to a file for easy inspection
/// Logs are written to ~/Dropbox/livecode_records/debug.log
class DebugLogger {
    static let shared = DebugLogger()
    
    private let logFile: URL
    private let queue = DispatchQueue(label: "com.clinassist.debuglogger", qos: .utility)
    private let dateFormatter: DateFormatter
    
    /// Current logger configuration
    var configuration: LoggerConfiguration {
        didSet {
            log("Logger configuration updated: level=\(configuration.minimumLevel), emojis=\(configuration.includeEmojis)", level: .info)
        }
    }
    
    private init() {
        let dropboxPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Dropbox")
            .appendingPathComponent("livecode_records")
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: dropboxPath, withIntermediateDirectories: true)
        
        logFile = dropboxPath.appendingPathComponent("debug.log")
        
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        
        // Set configuration based on build type
        #if DEBUG
        configuration = .debug
        #else
        configuration = .release
        #endif
        
        // Clear old log on app start
        clearLog()
        
        // Write startup header
        log("═══════════════════════════════════════════════════════════════", level: .info)
        log("ClinAssist Debug Log - Started at \(ISO8601DateFormatter().string(from: Date()))", level: .info)
        #if DEBUG
        log("Build: DEBUG", level: .info)
        #else
        log("Build: RELEASE", level: .info)
        #endif
        log("═══════════════════════════════════════════════════════════════", level: .info)
    }
    
    /// Log a message with optional component tag and level
    func log(_ message: String, component: String? = nil, level: LogLevel = .info) {
        // Check if level meets minimum threshold
        guard level >= configuration.minimumLevel else { return }
        
        // Check component filters
        if let component = component {
            // If allowedComponents is set, only log those components
            if !configuration.allowedComponents.isEmpty && !configuration.allowedComponents.contains(component) {
                return
            }
            // If component is excluded, skip
            if configuration.excludedComponents.contains(component) {
                return
            }
        }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let timestamp = self.dateFormatter.string(from: Date())
            let componentPrefix = component.map { "[\($0)] " } ?? ""
            let levelPrefix = configuration.includeEmojis ? level.emoji + " " : "[\(level.prefix)] "
            
            // Strip emojis from message if configured
            let cleanMessage = configuration.includeEmojis ? message : self.stripEmojis(from: message)
            
            let line = "[\(timestamp)] \(levelPrefix)\(componentPrefix)\(cleanMessage)\n"
            
            // Write to file if enabled
            if configuration.writeToFile {
                self.writeToFile(line)
            }
            
            // Print to console if enabled
            if configuration.printToConsole {
                print(line.trimmingCharacters(in: .newlines))
            }
        }
    }
    
    private func writeToFile(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        
        // Check file size and rotate if needed
        if let attributes = try? FileManager.default.attributesOfItem(atPath: logFile.path),
           let fileSize = attributes[.size] as? Int,
           fileSize > configuration.maxFileSize {
            rotateLogFile()
        }
        
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: logFile)
        }
    }
    
    /// Strip emojis from a string for cleaner release logs
    private func stripEmojis(from string: String) -> String {
        return string.unicodeScalars
            .filter { scalar in
                // Keep basic Latin, Latin-1 Supplement, and common punctuation
                // Filter out emoji ranges
                let value = scalar.value
                return value < 0x1F300 ||  // Below emoji range
                       (value >= 0x20 && value <= 0x7E) ||  // Basic ASCII
                       (value >= 0xA0 && value <= 0xFF) ||  // Latin-1 Supplement
                       (value >= 0x100 && value <= 0x24FF)  // Extended Latin and symbols
            }
            .map { String($0) }
            .joined()
            .trimmingCharacters(in: .whitespaces)
    }
    
    /// Rotate log file when it gets too large
    private func rotateLogFile() {
        let backupPath = logFile.deletingLastPathComponent()
            .appendingPathComponent("debug.log.old")
        
        try? FileManager.default.removeItem(at: backupPath)
        try? FileManager.default.moveItem(at: logFile, to: backupPath)
    }
    
    /// Clear the log file
    func clearLog() {
        try? FileManager.default.removeItem(at: logFile)
    }
    
    /// Get the log file path for display
    var logFilePath: String {
        logFile.path
    }
    
    /// Get recent log entries (for debugging UI)
    func getRecentLogs(count: Int = 100) -> [String] {
        guard let content = try? String(contentsOf: logFile, encoding: .utf8) else {
            return []
        }
        
        let lines = content.components(separatedBy: .newlines)
        return Array(lines.suffix(count))
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
    DebugLogger.shared.log(message, component: component, level: .warning)
}

/// Log an error message
func logError(_ message: String, component: String? = nil) {
    DebugLogger.shared.log(message, component: component, level: .error)
}

/// Log a debug message (verbose, development only)
func logDebug(_ message: String, component: String? = nil) {
    DebugLogger.shared.log(message, component: component, level: .debug)
}

// MARK: - Configuration Helpers

extension DebugLogger {
    /// Enable verbose logging for a specific component
    func enableVerbose(for component: String) {
        configuration.allowedComponents.insert(component)
    }
    
    /// Disable logging for a specific component
    func disable(for component: String) {
        configuration.excludedComponents.insert(component)
    }
    
    /// Reset filters to log all components
    func resetFilters() {
        configuration.allowedComponents.removeAll()
        configuration.excludedComponents.removeAll()
    }
    
    /// Set minimum log level
    func setMinimumLevel(_ level: LogLevel) {
        configuration.minimumLevel = level
    }
}
