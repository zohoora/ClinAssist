import XCTest
@testable import ClinAssist

@MainActor
final class LLMOrchestratorTests: XCTestCase {
    
    // MARK: - EncounterAttachment Model Tests
    // These tests verify the attachment model correctly identifies multimodal content
    
    func testEncounterAttachmentIsMultimodalForImage() {
        let imageAttachment = EncounterAttachment(
            name: "photo.jpg",
            type: .image,
            base64Data: "data",
            mimeType: "image/jpeg"
        )
        
        XCTAssertTrue(imageAttachment.isMultimodal)
    }
    
    func testEncounterAttachmentIsMultimodalForPDF() {
        let pdfAttachment = EncounterAttachment(
            name: "report.pdf",
            type: .pdf,
            base64Data: "data",
            mimeType: "application/pdf"
        )
        
        XCTAssertTrue(pdfAttachment.isMultimodal)
    }
    
    func testEncounterAttachmentIsNotMultimodalForText() {
        let textAttachment = EncounterAttachment(
            name: "notes.txt",
            type: .textFile,
            textContent: "Some text"
        )
        
        XCTAssertFalse(textAttachment.isMultimodal)
    }
    
    func testMixedAttachmentsDetectMultimodal() {
        let textAttachment = EncounterAttachment(
            name: "notes.txt",
            type: .textFile,
            textContent: "Some text"
        )
        
        let imageAttachment = EncounterAttachment(
            name: "photo.jpg",
            type: .image,
            base64Data: "data",
            mimeType: "image/jpeg"
        )
        
        let attachments = [textAttachment, imageAttachment]
        
        // Check that at least one is multimodal
        let hasMultimodal = attachments.contains { $0.isMultimodal }
        XCTAssertTrue(hasMultimodal)
    }
    
    func testAllTextAttachmentsNoMultimodal() {
        let textAttachment1 = EncounterAttachment(
            name: "notes1.txt",
            type: .textFile,
            textContent: "Some text"
        )
        
        let textAttachment2 = EncounterAttachment(
            name: "notes2.txt",
            type: .textFile,
            textContent: "More text"
        )
        
        let attachments = [textAttachment1, textAttachment2]
        
        // Check that none are multimodal
        let hasMultimodal = attachments.contains { $0.isMultimodal }
        XCTAssertFalse(hasMultimodal)
    }
    
    // MARK: - Attachment Type Tests
    
    func testImageAttachmentType() {
        let attachment = EncounterAttachment(
            name: "screenshot.png",
            type: .image,
            base64Data: "base64data",
            mimeType: "image/png"
        )
        
        XCTAssertEqual(attachment.type, .image)
        XCTAssertEqual(attachment.mimeType, "image/png")
        XCTAssertNotNil(attachment.base64Data)
    }
    
    func testPDFAttachmentType() {
        let attachment = EncounterAttachment(
            name: "report.pdf",
            type: .pdf,
            base64Data: "pdfdata",
            mimeType: "application/pdf"
        )
        
        XCTAssertEqual(attachment.type, .pdf)
        XCTAssertEqual(attachment.mimeType, "application/pdf")
        XCTAssertTrue(attachment.isMultimodal)
    }
    
    func testTextFileAttachmentType() {
        let attachment = EncounterAttachment(
            name: "notes.txt",
            type: .textFile,
            textContent: "Clinical notes content"
        )
        
        XCTAssertEqual(attachment.type, .textFile)
        XCTAssertNil(attachment.base64Data)
        XCTAssertNotNil(attachment.textContent)
        XCTAssertFalse(attachment.isMultimodal)
    }
    
    func testAttachmentHasCorrectTimestamp() {
        let beforeCreation = Date()
        let attachment = EncounterAttachment(
            name: "test.png",
            type: .image,
            base64Data: "data",
            mimeType: "image/png"
        )
        let afterCreation = Date()
        
        XCTAssertGreaterThanOrEqual(attachment.timestamp, beforeCreation)
        XCTAssertLessThanOrEqual(attachment.timestamp, afterCreation)
    }
    
    func testAttachmentHasUniqueId() {
        let attachment1 = EncounterAttachment(
            name: "test1.png",
            type: .image,
            base64Data: "data1",
            mimeType: "image/png"
        )
        
        let attachment2 = EncounterAttachment(
            name: "test2.png",
            type: .image,
            base64Data: "data2",
            mimeType: "image/png"
        )
        
        XCTAssertNotEqual(attachment1.id, attachment2.id)
    }
}

