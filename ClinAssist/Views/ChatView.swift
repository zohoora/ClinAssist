import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation

struct ChatView: View {
    @ObservedObject var encounterController: EncounterController
    @StateObject private var chatController = ChatController()
    
    @State private var inputText: String = ""
    @State private var isExpanded: Bool = false
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("CHAT")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text("(Gemini 3 Pro)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if chatController.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                }
                
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
            
            if isExpanded {
                VStack(spacing: 8) {
                    // Chat messages
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(chatController.messages) { message in
                                    ChatMessageView(message: message)
                                        .id(message.id)
                                }
                            }
                            .padding(8)
                        }
                        .frame(height: 200)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .onChange(of: chatController.messages.count) { _, _ in
                            if let lastMessage = chatController.messages.last {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    
                    // Attachment preview
                    if !chatController.pendingAttachments.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(chatController.pendingAttachments) { attachment in
                                    AttachmentPreview(attachment: attachment) {
                                        chatController.removeAttachment(attachment)
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        .frame(height: 60)
                    }
                    
                    // Input area
                    HStack(spacing: 8) {
                        // Attachment buttons
                        Menu {
                            Button(action: { selectFile() }) {
                                Label("Upload File", systemImage: "doc")
                            }
                            Button(action: { selectImage() }) {
                                Label("Upload Image", systemImage: "photo")
                            }
                            Button(action: { captureScreenshot() }) {
                                Label("Screenshot", systemImage: "camera.viewfinder")
                            }
                            Button(action: { showCameraSelector() }) {
                                Label("Camera", systemImage: "camera")
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.blue)
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 24)
                        
                        // Text input
                        TextField("Ask about this case...", text: $inputText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                            .focused($isInputFocused)
                            .onSubmit {
                                sendMessage()
                            }
                        
                        // Send button
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(canSend ? .blue : .gray)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                    }
                    
                    // Helper text
                    Text("Chat is not stored. Has access to current transcript.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            }
        }
        .onAppear {
            chatController.transcriptProvider = { [weak encounterController] in
                encounterController?.state?.transcript ?? []
            }
            chatController.clinicalNotesProvider = { [weak encounterController] in
                encounterController?.state?.clinicalNotes ?? []
            }
        }
    }
    
    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !chatController.pendingAttachments.isEmpty
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !chatController.pendingAttachments.isEmpty else { return }
        
        inputText = ""
        
        Task {
            await chatController.sendMessage(text)
        }
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .plainText, .rtf, .data]
        
        if panel.runModal() == .OK, let url = panel.url {
            chatController.addFileAttachment(url: url)
        }
    }
    
    private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .png, .jpeg, .gif, .webP]
        
        if panel.runModal() == .OK, let url = panel.url {
            chatController.addImageAttachment(url: url)
        }
    }
    
    private func captureScreenshot() {
        // Capture screenshot directly - macOS will prompt for permission if needed
        DispatchQueue.main.async {
            if let screenshot = self.captureScreen() {
                self.chatController.addScreenshotAttachment(image: screenshot)
                debugLog("✅ Screenshot attached", component: "Screenshot")
            } else {
                debugLog("❌ Screenshot failed", component: "Screenshot")
            }
        }
    }
    
    private func captureScreen() -> NSImage? {
        // Get the main screen bounds
        guard let mainScreen = NSScreen.main else {
            debugLog("❌ No main screen found", component: "Screenshot")
            return nil
        }
        
        let screenRect = mainScreen.frame
        
        // Use CGWindowListCreateImage to capture all windows on screen
        // CGRect uses lower-left origin, convert from NSScreen coordinates
        let captureRect = CGRect(
            x: screenRect.origin.x,
            y: screenRect.origin.y,
            width: screenRect.width,
            height: screenRect.height
        )
        
        guard let screenshot = CGWindowListCreateImage(
            captureRect,
            .optionAll,  // Include all windows (on-screen and off-screen owned by user)
            kCGNullWindowID,
            [.bestResolution]
        ) else { 
            debugLog("❌ CGWindowListCreateImage returned nil", component: "Screenshot")
            return nil 
        }
        
        debugLog("✅ Captured screen: \(screenshot.width)x\(screenshot.height)", component: "Screenshot")
        return NSImage(cgImage: screenshot, size: NSSize(width: screenshot.width, height: screenshot.height))
    }
    
    private func showCameraSelector() {
        // Show camera selection dialog
        let cameras = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        ).devices
        
        if cameras.isEmpty {
            chatController.addSystemMessage("No cameras found.")
            return
        }
        
        // For simplicity, capture from first available camera
        captureFromCamera(cameras.first)
    }
    
    private func captureFromCamera(_ device: AVCaptureDevice?) {
        guard let device = device else { return }
        
        // Simple camera capture - in production, you'd want a proper camera preview
        let session = AVCaptureSession()
        session.sessionPreset = .photo
        
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.addInput(input)
        
        let output = AVCapturePhotoOutput()
        session.addOutput(output)
        
        session.startRunning()
        
        // Capture after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let settings = AVCapturePhotoSettings()
            output.capturePhoto(with: settings, delegate: chatController)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                session.stopRunning()
            }
        }
    }
}

// MARK: - Chat Message View

struct ChatMessageView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundColor(.purple)
                    .frame(width: 16)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Attachments
                if !message.attachments.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(message.attachments) { attachment in
                            AttachmentBadge(attachment: attachment)
                        }
                    }
                }
                
                // Text
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .padding(8)
                        .background(message.role == .user ? Color.blue.opacity(0.2) : Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .user {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.blue)
                    .frame(width: 16)
            }
        }
    }
}

// MARK: - Attachment Preview

struct AttachmentPreview: View {
    let attachment: ChatAttachment
    let onRemove: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 2) {
                if let image = attachment.thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 40)
                        .clipped()
                        .cornerRadius(4)
                } else {
                    Image(systemName: attachment.icon)
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                        .frame(width: 50, height: 40)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                }
                
                Text(attachment.name)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: 50)
            }
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
    }
}

// MARK: - Attachment Badge

struct AttachmentBadge: View {
    let attachment: ChatAttachment
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: attachment.icon)
                .font(.system(size: 8))
            Text(attachment.name)
                .font(.system(size: 8))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.2))
        .cornerRadius(4)
    }
}

// MARK: - Chat Controller

@MainActor
class ChatController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var messages: [ChatMessage] = []
    @Published var pendingAttachments: [ChatAttachment] = []
    @Published var isLoading: Bool = false
    
    var transcriptProvider: (() -> [TranscriptEntry])?
    var clinicalNotesProvider: (() -> [ClinicalNote])?
    
    private let model = "google/gemini-3-pro-preview"
    
    func sendMessage(_ text: String) async {
        let attachments = pendingAttachments
        
        await MainActor.run {
            // Add user message
            let userMessage = ChatMessage(role: .user, text: text, attachments: attachments)
            messages.append(userMessage)
            pendingAttachments = []
            isLoading = true
        }
        
        // Build context with transcript
        let transcript = transcriptProvider?() ?? []
        let clinicalNotes = clinicalNotesProvider?() ?? []
        
        let transcriptText = transcript.map { "[\($0.speaker)]: \($0.text)" }.joined(separator: "\n")
        let notesText = clinicalNotes.map { "• \($0.text)" }.joined(separator: "\n")
        
        let systemPrompt = """
        You are a helpful clinical assistant chatbot. You have access to the current patient encounter transcript and clinical notes.
        
        Current Transcript:
        \(transcriptText.isEmpty ? "(No transcript yet)" : transcriptText)
        
        Clinical Notes:
        \(notesText.isEmpty ? "(No clinical notes yet)" : notesText)
        
        Help the physician with questions about this case. Be concise and clinically relevant.
        """
        
        // Build user content with attachments
        var userContent = text
        for attachment in attachments {
            if attachment.type == .image, let base64 = attachment.base64Data {
                userContent += "\n[Image attached: \(attachment.name)]"
                // Note: For actual image support, you'd include the base64 in the API call
            } else if let textContent = attachment.textContent {
                userContent += "\n\n--- Attached File: \(attachment.name) ---\n\(textContent)"
            }
        }
        
        do {
            let response = try await callGemini(systemPrompt: systemPrompt, userContent: userContent, attachments: attachments)
            
            await MainActor.run {
                let assistantMessage = ChatMessage(role: .assistant, text: response, attachments: [])
                messages.append(assistantMessage)
                isLoading = false
            }
        } catch {
            await MainActor.run {
                let errorMessage = ChatMessage(role: .assistant, text: "Error: \(error.localizedDescription)", attachments: [])
                messages.append(errorMessage)
                isLoading = false
            }
        }
    }
    
    private func callGemini(systemPrompt: String, userContent: String, attachments: [ChatAttachment]) async throws -> String {
        guard let config = ConfigManager.shared.config else {
            throw ChatError.noConfig
        }
        
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.openrouterApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://clinassist.local", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("ClinAssist", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 60
        
        // Build messages array
        var messagesArray: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        
        // Add conversation history (last 10 messages for context)
        let recentMessages = messages.suffix(10)
        for msg in recentMessages {
            let role = msg.role == .user ? "user" : "assistant"
            messagesArray.append(["role": role, "content": msg.text])
        }
        
        // Add current message with potential image
        var currentContent: Any = userContent
        
        // Check for image attachments - use multimodal format
        let imageAttachments = attachments.filter { $0.type == .image && $0.base64Data != nil }
        if !imageAttachments.isEmpty {
            var contentParts: [[String: Any]] = []
            contentParts.append(["type": "text", "text": userContent])
            
            for attachment in imageAttachments {
                if let base64 = attachment.base64Data {
                    contentParts.append([
                        "type": "image_url",
                        "image_url": [
                            "url": "data:\(attachment.mimeType ?? "image/png");base64,\(base64)"
                        ]
                    ])
                }
            }
            currentContent = contentParts
        }
        
        messagesArray.append(["role": "user", "content": currentContent])
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": messagesArray,
            "temperature": 0.3,
            "max_tokens": 8192  // Gemini 3 Pro needs more tokens for reasoning + response
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ChatError.apiError("HTTP \(httpResponse.statusCode): \(errorText)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ChatError.invalidResponse
        }
        
        return content
    }
    
    func addSystemMessage(_ text: String) {
        let message = ChatMessage(role: .assistant, text: text, attachments: [])
        messages.append(message)
    }
    
    func addFileAttachment(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let textContent = String(data: data, encoding: .utf8)
        
        let attachment = ChatAttachment(
            name: url.lastPathComponent,
            type: .file,
            data: data,
            textContent: textContent,
            thumbnail: nil,
            icon: "doc.fill"
        )
        pendingAttachments.append(attachment)
    }
    
    func addImageAttachment(url: URL) {
        guard let data = try? Data(contentsOf: url),
              let image = NSImage(contentsOf: url) else { return }
        
        let base64 = data.base64EncodedString()
        let mimeType = url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
        
        let attachment = ChatAttachment(
            name: url.lastPathComponent,
            type: .image,
            data: data,
            base64Data: base64,
            mimeType: mimeType,
            thumbnail: image.resized(to: NSSize(width: 100, height: 100)),
            icon: "photo.fill"
        )
        pendingAttachments.append(attachment)
    }
    
    func addScreenshotAttachment(image: NSImage) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        
        let base64 = pngData.base64EncodedString()
        
        let attachment = ChatAttachment(
            name: "Screenshot",
            type: .image,
            data: pngData,
            base64Data: base64,
            mimeType: "image/png",
            thumbnail: image.resized(to: NSSize(width: 100, height: 100)),
            icon: "camera.viewfinder"
        )
        pendingAttachments.append(attachment)
    }
    
    func removeAttachment(_ attachment: ChatAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }
    
    // MARK: - AVCapturePhotoCaptureDelegate
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = NSImage(data: imageData) else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.addCameraAttachment(image: image, data: imageData)
        }
    }
    
    private func addCameraAttachment(image: NSImage, data: Data) {
        let base64 = data.base64EncodedString()
        
        let attachment = ChatAttachment(
            name: "Camera Photo",
            type: .image,
            data: data,
            base64Data: base64,
            mimeType: "image/jpeg",
            thumbnail: image.resized(to: NSSize(width: 100, height: 100)),
            icon: "camera.fill"
        )
        pendingAttachments.append(attachment)
    }
}

// MARK: - Chat Models

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let text: String
    let attachments: [ChatAttachment]
    let timestamp = Date()
}

enum ChatRole {
    case user
    case assistant
}

struct ChatAttachment: Identifiable {
    let id = UUID()
    let name: String
    let type: AttachmentType
    let data: Data?
    var textContent: String?
    var base64Data: String?
    var mimeType: String?
    var thumbnail: NSImage?
    let icon: String
    
    init(name: String, type: AttachmentType, data: Data?, textContent: String? = nil, base64Data: String? = nil, mimeType: String? = nil, thumbnail: NSImage? = nil, icon: String) {
        self.name = name
        self.type = type
        self.data = data
        self.textContent = textContent
        self.base64Data = base64Data
        self.mimeType = mimeType
        self.thumbnail = thumbnail
        self.icon = icon
    }
}

enum AttachmentType {
    case file
    case image
}

enum ChatError: LocalizedError {
    case noConfig
    case invalidResponse
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .noConfig:
            return "No configuration found"
        case .invalidResponse:
            return "Invalid response from API"
        case .apiError(let message):
            return message
        }
    }
}

// MARK: - NSImage Extension

extension NSImage {
    func resized(to newSize: NSSize) -> NSImage {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: newSize),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy,
                  fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}

#Preview {
    ChatView(encounterController: EncounterController(
        audioManager: AudioManager(),
        configManager: ConfigManager.shared
    ))
    .padding()
    .frame(width: 380, height: 500)
}
