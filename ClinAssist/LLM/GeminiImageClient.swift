import Foundation
import AppKit

/// Client for image generation via OpenRouter (using Gemini's image generation)
class GeminiImageClient {
    private let apiKey: String
    private let useOpenRouter: Bool
    
    // OpenRouter endpoint
    private let openRouterURL = "https://openrouter.ai/api/v1/chat/completions"
    
    // Direct Gemini Imagen endpoint (if using direct API)
    private let imagenURL = "https://generativelanguage.googleapis.com/v1beta/models/imagen-3.0-generate-002:predict"
    
    /// Get the configured image generation model from settings
    @MainActor
    private func getConfiguredImageModel() -> String {
        let model = ConfigManager.shared.getModel(for: .imageGeneration, scenario: .standard)
        debugLog("🎨 Using configured image model: \(model.displayName)", component: "GeminiImage")
        return model.modelId
    }
    
    init(apiKey: String, useOpenRouter: Bool = true) {
        self.apiKey = apiKey
        self.useOpenRouter = useOpenRouter
    }
    
    /// Generate an image from a text prompt
    func generateImage(prompt: String) async throws -> NSImage {
        if useOpenRouter {
            return try await generateViaOpenRouter(prompt: prompt)
        } else {
            return try await generateViaImagen(prompt: prompt)
        }
    }
    
    // MARK: - OpenRouter Image Generation
    
    private func generateViaOpenRouter(prompt: String) async throws -> NSImage {
        guard let url = URL(string: openRouterURL) else {
            throw GeminiImageError.invalidURL
        }
        
        let imageModel = await getConfiguredImageModel()
        debugLog("🎨 Generating image with \(imageModel): \(prompt.prefix(50))...", component: "GeminiImage")
        let startTime = Date()
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ClinAssist", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 120
        
        let requestBody: [String: Any] = [
            "model": imageModel,
            "messages": [
                [
                    "role": "user",
                    "content": "Generate an image of: \(prompt)"
                ]
            ],
            "max_tokens": 8192
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiImageError.invalidResponse
        }
        
        debugLog("📡 OpenRouter response: \(httpResponse.statusCode) in \(String(format: "%.2f", elapsed))s", component: "GeminiImage")
        
        if httpResponse.statusCode == 401 {
            throw GeminiImageError.unauthorized
        }
        
        // Check if model is not available
        if httpResponse.statusCode == 404 || httpResponse.statusCode == 400 {
            throw GeminiImageError.modelNotAvailable
        }
        
        if httpResponse.statusCode != 200 {
            if let errorString = String(data: data, encoding: .utf8) {
                debugLog("❌ OpenRouter error: \(errorString.prefix(200))", component: "GeminiImage")
            }
            throw GeminiImageError.apiError(statusCode: httpResponse.statusCode)
        }
        
        // Log the full response for debugging
        if let responseStr = String(data: data, encoding: .utf8) {
            debugLog("📦 Full API response: \(responseStr)", component: "GeminiImage")
        }
        
        // Parse the response - OpenRouter returns image in base64 within the message content
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            debugLog("❌ Failed to parse JSON response", component: "GeminiImage")
            throw GeminiImageError.parseError
        }
        
        debugLog("📋 Parsed JSON keys: \(json.keys.joined(separator: ", "))", component: "GeminiImage")
        
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first else {
            debugLog("❌ No choices in response. JSON: \(json)", component: "GeminiImage")
            throw GeminiImageError.parseError
        }
        
        debugLog("📋 First choice keys: \(firstChoice.keys.joined(separator: ", "))", component: "GeminiImage")
        
        guard let message = firstChoice["message"] as? [String: Any] else {
            debugLog("❌ No message in first choice: \(firstChoice)", component: "GeminiImage")
            throw GeminiImageError.parseError
        }
        
        debugLog("📋 Message keys: \(message.keys.joined(separator: ", "))", component: "GeminiImage")
        
        // FIRST: Check for 'images' field (Gemini 3 Pro format)
        if let images = message["images"] as? [[String: Any]], !images.isEmpty {
            debugLog("📋 Found 'images' array with \(images.count) items", component: "GeminiImage")
            for (index, imageObj) in images.enumerated() {
                debugLog("📋 Image \(index) keys: \(imageObj.keys.joined(separator: ", "))", component: "GeminiImage")
                
                // Check for image_url (OpenRouter/Gemini format)
                if let imageUrl = imageObj["image_url"] {
                    debugLog("📋 Found image_url field, type: \(type(of: imageUrl))", component: "GeminiImage")
                    
                    // image_url can be a string directly
                    if let urlString = imageUrl as? String {
                        debugLog("📋 image_url is string with \(urlString.count) chars", component: "GeminiImage")
                        if let image = decodeBase64Image(urlString) {
                            debugLog("✅ Image generated successfully from image_url string: \(image.size)", component: "GeminiImage")
                            return image
                        }
                    }
                    
                    // image_url can be an object with 'url' key
                    if let urlObj = imageUrl as? [String: Any], let urlString = urlObj["url"] as? String {
                        debugLog("📋 image_url.url is string with \(urlString.count) chars", component: "GeminiImage")
                        if let image = decodeBase64Image(urlString) {
                            debugLog("✅ Image generated successfully from image_url.url: \(image.size)", component: "GeminiImage")
                            return image
                        }
                    }
                }
                
                // Check for base64 data directly
                if let base64Data = imageObj["data"] as? String {
                    debugLog("📋 Found image data with \(base64Data.count) chars", component: "GeminiImage")
                    if let image = decodeBase64Image(base64Data) {
                        debugLog("✅ Image generated successfully from images array: \(image.size)", component: "GeminiImage")
                        return image
                    }
                }
                
                // Check for b64_json format
                if let base64Data = imageObj["b64_json"] as? String {
                    debugLog("📋 Found b64_json with \(base64Data.count) chars", component: "GeminiImage")
                    if let image = decodeBase64Image(base64Data) {
                        debugLog("✅ Image generated successfully from b64_json: \(image.size)", component: "GeminiImage")
                        return image
                    }
                }
                
                // Check for url format  
                if let urlString = imageObj["url"] as? String {
                    debugLog("📋 Found image url: \(urlString.prefix(100))...", component: "GeminiImage")
                    if let image = decodeBase64Image(urlString) {
                        debugLog("✅ Image generated successfully from image url: \(image.size)", component: "GeminiImage")
                        return image
                    }
                }
            }
        }
        
        // Also check for images as an array of strings (raw base64 array)
        if let images = message["images"] as? [String], !images.isEmpty {
            debugLog("📋 Found 'images' string array with \(images.count) items", component: "GeminiImage")
            for (index, base64Data) in images.enumerated() {
                debugLog("📋 Image \(index) has \(base64Data.count) chars", component: "GeminiImage")
                if let image = decodeBase64Image(base64Data) {
                    debugLog("✅ Image generated successfully from images string array: \(image.size)", component: "GeminiImage")
                    return image
                }
            }
        }
        
        // Check for single image string
        if let imageData = message["images"] as? String, !imageData.isEmpty {
            debugLog("📋 Found 'images' as single string with \(imageData.count) chars", component: "GeminiImage")
            if let image = decodeBase64Image(imageData) {
                debugLog("✅ Image generated successfully from images string: \(image.size)", component: "GeminiImage")
                return image
            }
        }
        
        // THEN: Check content field
        guard let content = message["content"] else {
            debugLog("❌ No content in message and no images found", component: "GeminiImage")
            throw GeminiImageError.parseError
        }
        
        debugLog("📋 Content type: \(type(of: content))", component: "GeminiImage")
        
        // Content might be a string or an array of content parts
        if let contentArray = content as? [[String: Any]] {
            debugLog("📋 Content is array with \(contentArray.count) items", component: "GeminiImage")
            // Look for inline_data (image) in content parts
            for (index, part) in contentArray.enumerated() {
                debugLog("📋 Part \(index) keys: \(part.keys.joined(separator: ", "))", component: "GeminiImage")
                
                // Check for inline_data format (Gemini style)
                if let inlineData = part["inline_data"] as? [String: Any],
                   let base64Data = inlineData["data"] as? String {
                    debugLog("📋 Found inline_data with \(base64Data.count) chars", component: "GeminiImage")
                    if let image = decodeBase64Image(base64Data) {
                        debugLog("✅ Image generated successfully from inline_data: \(image.size)", component: "GeminiImage")
                        return image
                    }
                }
                
                // Check for image_url format
                if let imageUrl = part["image_url"] as? [String: Any],
                   let urlString = imageUrl["url"] as? String {
                    debugLog("📋 Found image_url: \(urlString.prefix(100))...", component: "GeminiImage")
                    if let image = decodeBase64Image(urlString) {
                        debugLog("✅ Image generated successfully from image_url: \(image.size)", component: "GeminiImage")
                        return image
                    }
                }
                
                // Check for direct "data" field in the part
                if let base64Data = part["data"] as? String {
                    debugLog("📋 Found direct data field with \(base64Data.count) chars", component: "GeminiImage")
                    if let image = decodeBase64Image(base64Data) {
                        debugLog("✅ Image generated successfully from data field: \(image.size)", component: "GeminiImage")
                        return image
                    }
                }
                
                // Check for "type" = "image" parts
                if let type = part["type"] as? String, type == "image",
                   let source = part["source"] as? [String: Any],
                   let base64Data = source["data"] as? String {
                    debugLog("📋 Found image source with \(base64Data.count) chars", component: "GeminiImage")
                    if let image = decodeBase64Image(base64Data) {
                        debugLog("✅ Image generated successfully from image source: \(image.size)", component: "GeminiImage")
                        return image
                    }
                }
            }
        } else if let contentString = content as? String {
            debugLog("📋 Content is string with \(contentString.count) chars", component: "GeminiImage")
            debugLog("📋 Content preview: \(contentString.prefix(200))...", component: "GeminiImage")
            
            // Try to decode as base64 image
            if let image = decodeBase64Image(contentString) {
                debugLog("✅ Image generated successfully from string content: \(image.size)", component: "GeminiImage")
                return image
            }
        }
        
        debugLog("❌ No image found in response", component: "GeminiImage")
        throw GeminiImageError.noImageInResponse
    }
    
    // Helper to decode base64 image from various formats
    private func decodeBase64Image(_ input: String) -> NSImage? {
        var base64String = input
        
        // Handle data URL format (data:image/jpeg;base64,...)
        if input.contains("data:image") && input.contains(",") {
            let components = input.components(separatedBy: ",")
            if components.count > 1 {
                base64String = components[1]
            }
        }
        
        // Clean up the base64 string - remove whitespace and newlines
        base64String = base64String.trimmingCharacters(in: .whitespacesAndNewlines)
        base64String = base64String.replacingOccurrences(of: "\n", with: "")
        base64String = base64String.replacingOccurrences(of: "\r", with: "")
        base64String = base64String.replacingOccurrences(of: " ", with: "")
        
        // Try standard base64 decoding
        if let imageData = Data(base64Encoded: base64String),
           let image = NSImage(data: imageData) {
            return image
        }
        
        // Try with options for ignoring unknown characters
        if let imageData = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters),
           let image = NSImage(data: imageData) {
            return image
        }
        
        debugLog("❌ Failed to decode base64 image, length: \(base64String.count)", component: "GeminiImage")
        return nil
    }
    
    // MARK: - Direct Imagen API
    
    private func generateViaImagen(prompt: String) async throws -> NSImage {
        guard let url = URL(string: "\(imagenURL)?key=\(apiKey)") else {
            throw GeminiImageError.invalidURL
        }
        
        debugLog("🎨 Generating image with Imagen 3: \(prompt.prefix(50))...", component: "GeminiImage")
        let startTime = Date()
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        
        let requestBody: [String: Any] = [
            "instances": [
                ["prompt": prompt]
            ],
            "parameters": [
                "sampleCount": 1,
                "aspectRatio": "1:1",
                "safetyFilterLevel": "block_only_high",
                "personGeneration": "allow_adult"
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiImageError.invalidResponse
        }
        
        debugLog("📡 Imagen response status: \(httpResponse.statusCode) in \(String(format: "%.2f", elapsed))s", component: "GeminiImage")
        
        if httpResponse.statusCode == 401 {
            throw GeminiImageError.unauthorized
        }
        
        if httpResponse.statusCode != 200 {
            if let errorString = String(data: data, encoding: .utf8) {
                debugLog("❌ Imagen error: \(errorString)", component: "GeminiImage")
            }
            throw GeminiImageError.apiError(statusCode: httpResponse.statusCode)
        }
        
        // Parse the response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let predictions = json["predictions"] as? [[String: Any]],
              let firstPrediction = predictions.first,
              let bytesB64 = firstPrediction["bytesBase64Encoded"] as? String,
              let imageData = Data(base64Encoded: bytesB64),
              let image = NSImage(data: imageData) else {
            debugLog("❌ Failed to parse image from Imagen response", component: "GeminiImage")
            throw GeminiImageError.parseError
        }
        
        debugLog("✅ Image generated successfully: \(image.size)", component: "GeminiImage")
        return image
    }
}

enum GeminiImageError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case apiError(statusCode: Int)
    case parseError
    case noApiKey
    case noImageInResponse
    case modelNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Invalid API key"
        case .apiError(let statusCode):
            return "API error (status: \(statusCode))"
        case .parseError:
            return "Failed to parse response"
        case .noApiKey:
            return "API key not configured"
        case .noImageInResponse:
            return "No image was generated. The model may not support image generation for this prompt."
        case .modelNotAvailable:
            return "Gemini 3 Pro Image Preview is not currently available on OpenRouter. Please try again later."
        }
    }
}
