import Foundation
import SwiftUI

enum AppState: Equatable {
    case idle           // Not doing anything, manual mode
    case monitoring     // Auto-detection: listening for encounter start
    case buffering      // Auto-detection: speech detected, confirming encounter
    case recording      // Actively recording an encounter
    case paused         // Encounter paused
    case processing     // Brief state while generating final SOAP
    
    var displayName: String {
        switch self {
        case .idle:
            return "Ready"
        case .monitoring:
            return "Monitoring"
        case .buffering:
            return "Detecting..."
        case .recording:
            return "Processing"
        case .paused:
            return "Paused"
        case .processing:
            return "Finalizing"
        }
    }
    
    var statusColor: Color {
        switch self {
        case .idle:
            return .gray
        case .monitoring:
            return .green
        case .buffering:
            return .orange
        case .recording:
            return .blue
        case .paused:
            return .yellow
        case .processing:
            return .blue
        }
    }
    
    var isActive: Bool {
        switch self {
        case .recording, .paused:
            return true
        default:
            return false
        }
    }
    
    var isListening: Bool {
        switch self {
        case .monitoring, .buffering, .recording:
            return true
        default:
            return false
        }
    }
}
