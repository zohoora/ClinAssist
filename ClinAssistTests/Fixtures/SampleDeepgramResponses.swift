import Foundation

/// Sample Deepgram API responses for testing
enum SampleDeepgramResponses {
    
    // MARK: - Successful Responses
    
    /// Simple single-speaker transcript
    static let simpleTranscript = """
    {
        "metadata": {
            "request_id": "test-request-123",
            "created": "2024-01-01T10:00:00.000Z",
            "duration": 5.0,
            "channels": 1
        },
        "results": {
            "channels": [{
                "alternatives": [{
                    "transcript": "Hello doctor how are you today",
                    "confidence": 0.98,
                    "words": [
                        {"word": "Hello", "start": 0.0, "end": 0.3, "confidence": 0.99, "speaker": 0},
                        {"word": "doctor", "start": 0.3, "end": 0.6, "confidence": 0.98, "speaker": 0},
                        {"word": "how", "start": 0.6, "end": 0.8, "confidence": 0.97, "speaker": 0},
                        {"word": "are", "start": 0.8, "end": 0.9, "confidence": 0.99, "speaker": 0},
                        {"word": "you", "start": 0.9, "end": 1.0, "confidence": 0.99, "speaker": 0},
                        {"word": "today", "start": 1.0, "end": 1.3, "confidence": 0.98, "speaker": 0}
                    ]
                }]
            }]
        }
    }
    """
    
    /// Two-speaker diarized transcript
    static let diarizedTranscript = """
    {
        "metadata": {
            "request_id": "test-request-456",
            "created": "2024-01-01T10:00:00.000Z",
            "duration": 10.0,
            "channels": 1
        },
        "results": {
            "channels": [{
                "alternatives": [{
                    "transcript": "Hello how can I help you I have a headache",
                    "confidence": 0.97,
                    "words": [
                        {"word": "Hello", "start": 0.0, "end": 0.3, "confidence": 0.99, "speaker": 0},
                        {"word": "how", "start": 0.3, "end": 0.5, "confidence": 0.98, "speaker": 0},
                        {"word": "can", "start": 0.5, "end": 0.6, "confidence": 0.97, "speaker": 0},
                        {"word": "I", "start": 0.6, "end": 0.7, "confidence": 0.99, "speaker": 0},
                        {"word": "help", "start": 0.7, "end": 0.9, "confidence": 0.98, "speaker": 0},
                        {"word": "you", "start": 0.9, "end": 1.0, "confidence": 0.99, "speaker": 0},
                        {"word": "I", "start": 1.5, "end": 1.6, "confidence": 0.98, "speaker": 1},
                        {"word": "have", "start": 1.6, "end": 1.8, "confidence": 0.97, "speaker": 1},
                        {"word": "a", "start": 1.8, "end": 1.9, "confidence": 0.99, "speaker": 1},
                        {"word": "headache", "start": 1.9, "end": 2.3, "confidence": 0.96, "speaker": 1}
                    ]
                }]
            }]
        }
    }
    """
    
    /// Medical terminology transcript
    static let medicalTranscript = """
    {
        "metadata": {
            "request_id": "test-request-789",
            "created": "2024-01-01T10:00:00.000Z",
            "duration": 8.0,
            "channels": 1
        },
        "results": {
            "channels": [{
                "alternatives": [{
                    "transcript": "The patient presents with bilateral lower extremity edema and elevated BNP levels",
                    "confidence": 0.95,
                    "words": [
                        {"word": "The", "start": 0.0, "end": 0.1, "confidence": 0.99, "speaker": 0},
                        {"word": "patient", "start": 0.1, "end": 0.4, "confidence": 0.98, "speaker": 0},
                        {"word": "presents", "start": 0.4, "end": 0.7, "confidence": 0.97, "speaker": 0},
                        {"word": "with", "start": 0.7, "end": 0.8, "confidence": 0.99, "speaker": 0},
                        {"word": "bilateral", "start": 0.8, "end": 1.2, "confidence": 0.94, "speaker": 0},
                        {"word": "lower", "start": 1.2, "end": 1.4, "confidence": 0.96, "speaker": 0},
                        {"word": "extremity", "start": 1.4, "end": 1.8, "confidence": 0.93, "speaker": 0},
                        {"word": "edema", "start": 1.8, "end": 2.1, "confidence": 0.95, "speaker": 0},
                        {"word": "and", "start": 2.1, "end": 2.2, "confidence": 0.99, "speaker": 0},
                        {"word": "elevated", "start": 2.2, "end": 2.5, "confidence": 0.97, "speaker": 0},
                        {"word": "BNP", "start": 2.5, "end": 2.8, "confidence": 0.91, "speaker": 0},
                        {"word": "levels", "start": 2.8, "end": 3.1, "confidence": 0.98, "speaker": 0}
                    ]
                }]
            }]
        }
    }
    """
    
    // MARK: - Error Responses
    
    /// 401 Unauthorized response
    static let unauthorizedError = """
    {
        "err_code": "INVALID_AUTH",
        "err_msg": "Invalid credentials",
        "request_id": "test-request-error"
    }
    """
    
    /// 429 Rate Limited response
    static let rateLimitError = """
    {
        "err_code": "RATE_LIMIT_EXCEEDED",
        "err_msg": "Too many requests. Please try again later.",
        "request_id": "test-request-rate-limit"
    }
    """
    
    /// 500 Server Error response
    static let serverError = """
    {
        "err_code": "INTERNAL_ERROR",
        "err_msg": "An internal error occurred",
        "request_id": "test-request-server-error"
    }
    """
    
    // MARK: - Edge Cases
    
    /// Empty transcript response
    static let emptyTranscript = """
    {
        "metadata": {
            "request_id": "test-request-empty",
            "created": "2024-01-01T10:00:00.000Z",
            "duration": 0.0,
            "channels": 1
        },
        "results": {
            "channels": [{
                "alternatives": [{
                    "transcript": "",
                    "confidence": 0.0,
                    "words": []
                }]
            }]
        }
    }
    """
    
    /// Transcript with low confidence
    static let lowConfidenceTranscript = """
    {
        "metadata": {
            "request_id": "test-request-low-conf",
            "created": "2024-01-01T10:00:00.000Z",
            "duration": 2.0,
            "channels": 1
        },
        "results": {
            "channels": [{
                "alternatives": [{
                    "transcript": "something unclear",
                    "confidence": 0.45,
                    "words": [
                        {"word": "something", "start": 0.0, "end": 0.5, "confidence": 0.40, "speaker": 0},
                        {"word": "unclear", "start": 0.5, "end": 1.0, "confidence": 0.50, "speaker": 0}
                    ]
                }]
            }]
        }
    }
    """
    
    /// Transcript with multiple speakers (3+)
    static let multiSpeakerTranscript = """
    {
        "metadata": {
            "request_id": "test-request-multi",
            "created": "2024-01-01T10:00:00.000Z",
            "duration": 15.0,
            "channels": 1
        },
        "results": {
            "channels": [{
                "alternatives": [{
                    "transcript": "Hello I'm the doctor Hi I'm the patient And I'm the family member",
                    "confidence": 0.95,
                    "words": [
                        {"word": "Hello", "start": 0.0, "end": 0.3, "confidence": 0.99, "speaker": 0},
                        {"word": "I'm", "start": 0.3, "end": 0.4, "confidence": 0.98, "speaker": 0},
                        {"word": "the", "start": 0.4, "end": 0.5, "confidence": 0.99, "speaker": 0},
                        {"word": "doctor", "start": 0.5, "end": 0.8, "confidence": 0.97, "speaker": 0},
                        {"word": "Hi", "start": 1.0, "end": 1.1, "confidence": 0.99, "speaker": 1},
                        {"word": "I'm", "start": 1.1, "end": 1.2, "confidence": 0.98, "speaker": 1},
                        {"word": "the", "start": 1.2, "end": 1.3, "confidence": 0.99, "speaker": 1},
                        {"word": "patient", "start": 1.3, "end": 1.6, "confidence": 0.96, "speaker": 1},
                        {"word": "And", "start": 2.0, "end": 2.1, "confidence": 0.99, "speaker": 2},
                        {"word": "I'm", "start": 2.1, "end": 2.2, "confidence": 0.98, "speaker": 2},
                        {"word": "the", "start": 2.2, "end": 2.3, "confidence": 0.99, "speaker": 2},
                        {"word": "family", "start": 2.3, "end": 2.5, "confidence": 0.95, "speaker": 2},
                        {"word": "member", "start": 2.5, "end": 2.8, "confidence": 0.94, "speaker": 2}
                    ]
                }]
            }]
        }
    }
    """
    
    // MARK: - Streaming WebSocket Responses
    
    /// WebSocket interim result
    static let streamingInterimResult = """
    {
        "type": "Results",
        "channel_index": [0, 1],
        "duration": 0.5,
        "start": 0.0,
        "is_final": false,
        "channel": {
            "alternatives": [{
                "transcript": "Hello doc",
                "confidence": 0.85,
                "words": [
                    {"word": "Hello", "start": 0.0, "end": 0.3, "confidence": 0.90, "speaker": 0},
                    {"word": "doc", "start": 0.3, "end": 0.5, "confidence": 0.80, "speaker": 0}
                ]
            }]
        }
    }
    """
    
    /// WebSocket final result
    static let streamingFinalResult = """
    {
        "type": "Results",
        "channel_index": [0, 1],
        "duration": 1.0,
        "start": 0.0,
        "is_final": true,
        "channel": {
            "alternatives": [{
                "transcript": "Hello doctor how can I help",
                "confidence": 0.95,
                "words": [
                    {"word": "Hello", "start": 0.0, "end": 0.3, "confidence": 0.99, "speaker": 0},
                    {"word": "doctor", "start": 0.3, "end": 0.6, "confidence": 0.98, "speaker": 0},
                    {"word": "how", "start": 0.6, "end": 0.7, "confidence": 0.97, "speaker": 0},
                    {"word": "can", "start": 0.7, "end": 0.8, "confidence": 0.98, "speaker": 0},
                    {"word": "I", "start": 0.8, "end": 0.85, "confidence": 0.99, "speaker": 0},
                    {"word": "help", "start": 0.85, "end": 1.0, "confidence": 0.96, "speaker": 0}
                ]
            }]
        }
    }
    """
    
    /// WebSocket metadata message
    static let streamingMetadata = """
    {
        "type": "Metadata",
        "transaction_key": "test-transaction",
        "request_id": "test-request-streaming",
        "sha256": "abc123",
        "created": "2024-01-01T10:00:00.000Z",
        "duration": 0.0,
        "channels": 1,
        "models": ["nova-3-medical"]
    }
    """
}
