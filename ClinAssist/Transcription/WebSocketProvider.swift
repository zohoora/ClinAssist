import Foundation

/// Message types received from WebSocket
enum WebSocketMessage {
    case data(Data)
    case string(String)
}

/// Protocol for WebSocket connections, enabling testability through mocking
protocol WebSocketProvider: AnyObject {
    var onMessage: ((Result<WebSocketMessage, Error>) -> Void)? { get set }
    var onConnected: (() -> Void)? { get set }
    var onDisconnected: ((Error?) -> Void)? { get set }
    
    func connect(to url: URL, headers: [String: String])
    func send(_ data: Data)
    func send(_ string: String)
    func disconnect()
}

/// WebSocket provider using URLSession
class URLSessionWebSocketProvider: NSObject, WebSocketProvider, URLSessionWebSocketDelegate {
    var onMessage: ((Result<WebSocketMessage, Error>) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: ((Error?) -> Void)?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var isConnected = false
    private var isIntentionalDisconnect = false  // Suppress errors during intentional disconnect
    
    override init() {
        super.init()
    }
    
    func connect(to url: URL, headers: [String: String]) {
        debugLog("🔌 Connecting to: \(url.host ?? "unknown")...", component: "WebSocket")
        
        isIntentionalDisconnect = false  // Reset flag for new connection
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        webSocketTask = session?.webSocketTask(with: request)
        webSocketTask?.resume()
        
        debugLog("🚀 WebSocket task started", component: "WebSocket")
        // Note: receiveMessage() is now called in didOpenWithProtocol delegate callback
        // to avoid "Socket is not connected" errors
    }
    
    func send(_ data: Data) {
        guard isConnected else {
            debugLog("⚠️ Cannot send data - not connected", component: "WebSocket")
            return
        }
        
        webSocketTask?.send(.data(data)) { error in
            if let error = error {
                debugLog("❌ Send data error: \(error.localizedDescription)", component: "WebSocket")
            }
        }
    }
    
    func send(_ string: String) {
        guard isConnected else {
            debugLog("⚠️ Cannot send string - not connected", component: "WebSocket")
            return
        }
        
        webSocketTask?.send(.string(string)) { error in
            if let error = error {
                debugLog("❌ Send string error: \(error.localizedDescription)", component: "WebSocket")
            }
        }
    }
    
    func disconnect() {
        isIntentionalDisconnect = true
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        isConnected = false
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self.onMessage?(.success(.data(data)))
                case .string(let string):
                    self.onMessage?(.success(.string(string)))
                @unknown default:
                    break
                }
                
                // Continue receiving messages
                self.receiveMessage()
                
            case .failure(let error):
                // Only propagate errors if not intentionally disconnecting
                if !self.isIntentionalDisconnect {
                    self.onMessage?(.failure(error))
                    self.isConnected = false
                    self.onDisconnected?(error)
                } else {
                    self.isConnected = false
                    self.onDisconnected?(nil)  // Clean disconnect, no error
                }
            }
        }
    }
    
    // MARK: - URLSessionWebSocketDelegate
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        debugLog("✅ WebSocket connected (protocol: \(`protocol` ?? "none"))", component: "WebSocket")
        isConnected = true
        
        // Start receiving messages now that connection is established
        receiveMessage()
        
        onConnected?()
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        debugLog("🔴 WebSocket closed with code: \(closeCode.rawValue)", component: "WebSocket")
        isConnected = false
        onDisconnected?(nil)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            // Only propagate errors if not intentionally disconnecting
            if !isIntentionalDisconnect {
                debugLog("❌ WebSocket task error: \(error.localizedDescription)", component: "WebSocket")
                isConnected = false
                onDisconnected?(error)
            } else {
                debugLog("ℹ️ WebSocket task completed during intentional disconnect", component: "WebSocket")
                isConnected = false
                // Don't call onDisconnected here - didCloseWith will handle it
            }
        }
    }
}

