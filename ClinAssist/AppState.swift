import Foundation

enum AppState: Equatable {
    case idle
    case recording
    case paused
    case processing // Brief state while generating final SOAP
    
    var displayName: String {
        switch self {
        case .idle:
            return "Ready"
        case .recording:
            return "Recording"
        case .paused:
            return "Paused"
        case .processing:
            return "Processing"
        }
    }
    
    var statusColor: String {
        switch self {
        case .idle:
            return "gray"
        case .recording:
            return "red"
        case .paused:
            return "yellow"
        case .processing:
            return "blue"
        }
    }
}

