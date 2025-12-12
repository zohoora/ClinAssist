import XCTest
@testable import ClinAssist

@MainActor
final class ChatControllerRequestBodyTests: XCTestCase {
    
    func testBuildOpenRouterRequestBody_NoAttachments_UsesTextContent() throws {
        let body = ChatController.buildOpenRouterRequestBody(
            selectedModel: "test-model",
            systemPrompt: "sys",
            recentMessages: [],
            userContent: "hello",
            attachments: []
        )
        
        XCTAssertEqual(body["model"] as? String, "test-model")
        let messages = body["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 2)
        XCTAssertEqual(messages?.first?["role"] as? String, "system")
        XCTAssertEqual(messages?.last?["role"] as? String, "user")
        
        let content = messages?.last?["content"]
        XCTAssertEqual(content as? String, "hello")
    }
    
    func testBuildOpenRouterRequestBody_WithImageAndPDF_UsesMultimodalParts() throws {
        let image = ChatAttachment(
            name: "image.png",
            type: .image,
            data: Data(),
            base64Data: "imgbase64",
            mimeType: "image/png",
            thumbnail: nil,
            icon: "photo"
        )
        
        let pdf = ChatAttachment(
            name: "report.pdf",
            type: .file,
            data: Data(),
            base64Data: "pdfbase64",
            mimeType: "application/pdf",
            thumbnail: nil,
            icon: "doc"
        )
        
        let body = ChatController.buildOpenRouterRequestBody(
            selectedModel: "test-model",
            systemPrompt: "sys",
            recentMessages: [],
            userContent: "question",
            attachments: [image, pdf]
        )
        
        let messages = body["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 2)
        
        let userContent = messages?.last?["content"]
        guard let parts = userContent as? [[String: Any]] else {
            XCTFail("Expected multimodal content parts")
            return
        }
        
        // First part is text, then 2 image_url parts
        XCTAssertEqual(parts.first?["type"] as? String, "text")
        XCTAssertEqual(parts.first?["text"] as? String, "question")
        
        let imageParts = parts.filter { ($0["type"] as? String) == "image_url" }
        XCTAssertEqual(imageParts.count, 2)
        
        let urls = imageParts.compactMap { part -> String? in
            let imageURL = part["image_url"] as? [String: Any]
            return imageURL?["url"] as? String
        }
        
        XCTAssertTrue(urls.contains("data:image/png;base64,imgbase64"))
        XCTAssertTrue(urls.contains("data:application/pdf;base64,pdfbase64"))
    }
}

