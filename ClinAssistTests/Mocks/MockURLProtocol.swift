import Foundation

/// Mock URL Protocol for intercepting network requests in tests
class MockURLProtocol: URLProtocol {
    
    // MARK: - Request Handler
    
    /// Handler to process incoming requests and return mock responses
    /// Set this before making network requests in tests
    static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?
    
    /// Tracks all requests made (for verification in tests)
    static var capturedRequests: [URLRequest] = []
    
    // MARK: - URLProtocol Overrides
    
    override class func canInit(with request: URLRequest) -> Bool {
        // Handle all requests when this protocol is registered
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        MockURLProtocol.capturedRequests.append(request)
        
        guard let handler = MockURLProtocol.requestHandler else {
            let error = NSError(
                domain: "MockURLProtocol",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No request handler set"]
            )
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    override func stopLoading() {
        // Nothing to clean up
    }
    
    // MARK: - Test Helpers
    
    /// Resets the protocol state for a new test
    static func reset() {
        requestHandler = nil
        capturedRequests = []
    }
    
    /// Creates a URLSession configured to use this mock protocol
    static func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
    
    /// Sets up a successful JSON response
    static func setupSuccessResponse(json: String, statusCode: Int = 200) {
        requestHandler = { request in
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response)
        }
    }
    
    /// Sets up an error response
    static func setupErrorResponse(statusCode: Int, message: String = "Error") {
        requestHandler = { request in
            let errorJSON = """
            {"error": {"message": "\(message)"}}
            """
            let data = errorJSON.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response)
        }
    }
    
    /// Sets up a network failure
    static func setupNetworkError(_ error: Error? = nil) {
        requestHandler = { _ in
            throw error ?? NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorNotConnectedToInternet,
                userInfo: [NSLocalizedDescriptionKey: "Network unavailable"]
            )
        }
    }
}

// MARK: - Deepgram Response Helpers

extension MockURLProtocol {
    
    /// Sets up a successful Deepgram REST API response
    static func setupDeepgramSuccess(
        transcript: String,
        speaker: Int = 0,
        confidence: Double = 0.98
    ) {
        let words = transcript.split(separator: " ").enumerated().map { index, word in
            """
            {
                "word": "\(word)",
                "start": \(Double(index) * 0.3),
                "end": \(Double(index + 1) * 0.3),
                "confidence": \(confidence),
                "speaker": \(speaker)
            }
            """
        }.joined(separator: ",")
        
        let json = """
        {
            "metadata": {
                "request_id": "test-request-id",
                "created": "2024-01-01T00:00:00.000Z",
                "duration": \(Double(transcript.split(separator: " ").count) * 0.3),
                "channels": 1
            },
            "results": {
                "channels": [{
                    "alternatives": [{
                        "transcript": "\(transcript)",
                        "confidence": \(confidence),
                        "words": [\(words)]
                    }]
                }]
            }
        }
        """
        
        setupSuccessResponse(json: json)
    }
    
    /// Sets up a Deepgram response with multiple speakers
    static func setupDeepgramDiarized(segments: [(text: String, speaker: Int)]) {
        var allWords: [String] = []
        var wordIndex = 0
        
        for segment in segments {
            let words = segment.text.split(separator: " ").map { word in
                let json = """
                {
                    "word": "\(word)",
                    "start": \(Double(wordIndex) * 0.3),
                    "end": \(Double(wordIndex + 1) * 0.3),
                    "confidence": 0.98,
                    "speaker": \(segment.speaker)
                }
                """
                wordIndex += 1
                return json
            }
            allWords.append(contentsOf: words)
        }
        
        let fullTranscript = segments.map { $0.text }.joined(separator: " ")
        
        let json = """
        {
            "metadata": {
                "request_id": "test-request-id",
                "created": "2024-01-01T00:00:00.000Z",
                "duration": \(Double(wordIndex) * 0.3),
                "channels": 1
            },
            "results": {
                "channels": [{
                    "alternatives": [{
                        "transcript": "\(fullTranscript)",
                        "confidence": 0.98,
                        "words": [\(allWords.joined(separator: ","))]
                    }]
                }]
            }
        }
        """
        
        setupSuccessResponse(json: json)
    }
}
