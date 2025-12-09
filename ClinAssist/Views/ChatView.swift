import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Chat View (Embedded in Sidebar)

struct ChatView: View {
    @ObservedObject var encounterController: EncounterController
    @StateObject private var chatController = ChatController()
    
    @State private var inputText: String = ""
    @State private var isExpanded: Bool = true  // Default to expanded
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
                
                // Pop-out button
                Button(action: popOutChat) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open in separate window")
                
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
                ChatContentView(
                    chatController: chatController,
                    inputText: $inputText,
                    isInputFocused: _isInputFocused,
                    isCompact: true
                )
            }
        }
        .onAppear {
            chatController.transcriptProvider = { [weak encounterController] in
                encounterController?.state?.transcript ?? []
            }
            chatController.clinicalNotesProvider = { [weak encounterController] in
                encounterController?.state?.clinicalNotes ?? []
            }
            // Connect attachment handler to add attachments to encounter for SOAP generation
            chatController.attachmentHandler = { [weak encounterController] chatAttachment in
                let encounterAttachment = ChatController.toEncounterAttachment(chatAttachment)
                encounterController?.addEncounterAttachment(encounterAttachment)
            }
        }
    }
    
    private func popOutChat() {
        ChatWindowController.shared.showChatWindow(
            chatController: chatController,
            transcriptProvider: { [weak encounterController] in
                encounterController?.state?.transcript ?? []
            },
            clinicalNotesProvider: { [weak encounterController] in
                encounterController?.state?.clinicalNotes ?? []
            }
        )
    }
}

// MARK: - Chat Content View (Shared between embedded and window)

struct ChatContentView: View {
    @ObservedObject var chatController: ChatController
    @Binding var inputText: String
    @FocusState var isInputFocused: Bool
    var isCompact: Bool = false
    
    var body: some View {
        VStack(spacing: 10) {
                    // Chat messages
                    ScrollViewReader { proxy in
                        ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(chatController.messages) { message in
                            ChatMessageView(message: message, isCompact: isCompact)
                                        .id(message.id)
                                }
                            }
                    .padding(12)
                        }
                .frame(minHeight: isCompact ? 280 : 400)
                .frame(maxHeight: isCompact ? 350 : .infinity)
                        .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
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
                        .font(.system(size: isCompact ? 20 : 24))
                                .foregroundColor(.blue)
                        }
                        .menuStyle(.borderlessButton)
                .frame(width: isCompact ? 24 : 28)
                        
                        // Text input with paste support
                PasteableTextField(
                    text: $inputText,
                    placeholder: "Ask about this case...",
                    isCompact: isCompact,
                    onPasteImage: { image in
                        chatController.addClipboardImage(image: image)
                    },
                    onSubmit: {
                        if !NSEvent.modifierFlags.contains(.shift) {
                                sendMessage()
                            }
                    }
                )
                .focused($isInputFocused)
                        
                        // Send button
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: isCompact ? 20 : 24))
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
        .padding(isCompact ? 10 : 16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
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
        DispatchQueue.main.async {
            if let screenshot = captureScreen() {
                chatController.addScreenshotAttachment(image: screenshot)
                debugLog("✅ Screenshot attached", component: "Screenshot")
            } else {
                debugLog("❌ Screenshot failed", component: "Screenshot")
            }
        }
    }
    
    private func captureScreen() -> NSImage? {
        let mainDisplayID = CGMainDisplayID()
        let displayBounds = CGDisplayBounds(mainDisplayID)
        
        guard let screenshot = CGWindowListCreateImage(
            displayBounds,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else { 
            debugLog("❌ CGWindowListCreateImage returned nil", component: "Screenshot")
            return nil 
        }
        
        return NSImage(cgImage: screenshot, size: NSSize(width: screenshot.width, height: screenshot.height))
    }
    
    private func showCameraSelector() {
        let cameras = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        ).devices
        
        if cameras.isEmpty {
            chatController.addSystemMessage("No cameras found.")
            return
        }
        
        CameraWindowController.shared.showCameraWindow { [weak chatController] image in
            chatController?.addCameraWindowAttachment(image: image)
        }
    }
}

// MARK: - Chat Message View with Markdown

struct ChatMessageView: View {
    let message: ChatMessage
    var isCompact: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                Image(systemName: "sparkles")
                    .font(.system(size: isCompact ? 12 : 14))
                    .foregroundColor(.purple)
                    .frame(width: 20)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Attachments
                if !message.attachments.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(message.attachments) { attachment in
                            AttachmentBadge(attachment: attachment)
                        }
                    }
                }
                
                // Text with Markdown rendering
                if !message.text.isEmpty {
                    if message.role == .assistant {
                        MarkdownTextView(text: message.text, isCompact: isCompact)
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(10)
                    } else {
                    Text(message.text)
                            .font(.system(size: isCompact ? 12 : 13))
                        .foregroundColor(.primary)
                            .padding(10)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(10)
                        .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .user {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: isCompact ? 12 : 14))
                    .foregroundColor(.blue)
                    .frame(width: 20)
            }
        }
    }
}

// MARK: - Markdown Text View

struct MarkdownTextView: View {
    let text: String
    var isCompact: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseMarkdownBlocks(text).enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
        .textSelection(.enabled)
    }
    
    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(parseInlineMarkdown(text))
                .font(.system(size: isCompact ? 12 : 13))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
        case .heading(let level, let text):
            Text(text)
                .font(.system(size: headingSize(level), weight: .semibold))
                .foregroundColor(.primary)
                .padding(.top, level == 1 ? 8 : 4)
            
        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 4) {
                if !language.isEmpty {
                    Text(language)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: isCompact ? 11 : 12, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(Color(NSColor.textBackgroundColor).opacity(0.8))
                .cornerRadius(6)
            }
            
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .font(.system(size: isCompact ? 12 : 13))
                            .foregroundColor(.secondary)
                        Text(parseInlineMarkdown(item))
                            .font(.system(size: isCompact ? 12 : 13))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            
        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(index + 1).")
                            .font(.system(size: isCompact ? 12 : 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(minWidth: 20, alignment: .trailing)
                        Text(parseInlineMarkdown(item))
                            .font(.system(size: isCompact ? 12 : 13))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            
        case .blockquote(let text):
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.blue.opacity(0.5))
                    .frame(width: 3)
                Text(parseInlineMarkdown(text))
                    .font(.system(size: isCompact ? 12 : 13))
                    .foregroundColor(.secondary)
                    .italic()
            }
            .padding(.vertical, 4)
            
        case .horizontalRule:
            Divider()
                .padding(.vertical, 8)
        }
    }
    
    private func headingSize(_ level: Int) -> CGFloat {
        let baseSize: CGFloat = isCompact ? 12 : 13
        switch level {
        case 1: return baseSize + 6
        case 2: return baseSize + 4
        case 3: return baseSize + 2
        default: return baseSize + 1
        }
    }
    
    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        // Simple approach: use AttributedString's markdown initializer if available
        // Otherwise fall back to plain text
        if let attributed = try? AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attributed
        }
        return AttributedString(text)
    }
    
    private func parseMarkdownBlocks(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var currentParagraph = ""
        var inCodeBlock = false
        var codeBlockLanguage = ""
        var codeBlockContent = ""
        
        while i < lines.count {
            let line = lines[i]
            
            // Code block
            if line.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(.codeBlock(language: codeBlockLanguage, code: codeBlockContent.trimmingCharacters(in: .newlines)))
                    inCodeBlock = false
                    codeBlockLanguage = ""
                    codeBlockContent = ""
                } else {
                    if !currentParagraph.isEmpty {
                        blocks.append(.paragraph(currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)))
                        currentParagraph = ""
                    }
                    inCodeBlock = true
                    codeBlockLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                i += 1
                continue
            }
            
            if inCodeBlock {
                codeBlockContent += line + "\n"
                i += 1
                continue
            }
            
            // Horizontal rule
            if line.trimmingCharacters(in: .whitespaces).matches(of: /^[-*_]{3,}$/).count > 0 {
                if !currentParagraph.isEmpty {
                    blocks.append(.paragraph(currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentParagraph = ""
                }
                blocks.append(.horizontalRule)
                i += 1
                continue
            }
            
            // Headings
            if let headingMatch = line.firstMatch(of: /^(#{1,6})\s+(.+)$/) {
                if !currentParagraph.isEmpty {
                    blocks.append(.paragraph(currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentParagraph = ""
                }
                let level = headingMatch.1.count
                let text = String(headingMatch.2)
                blocks.append(.heading(level: level, text: text))
                i += 1
                continue
            }
            
            // Bullet list
            if line.firstMatch(of: /^[\s]*[-*+]\s+(.+)$/) != nil {
                if !currentParagraph.isEmpty {
                    blocks.append(.paragraph(currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentParagraph = ""
                }
                var items: [String] = []
                while i < lines.count, let match = lines[i].firstMatch(of: /^[\s]*[-*+]\s+(.+)$/) {
                    items.append(String(match.1))
                    i += 1
                }
                blocks.append(.bulletList(items: items))
                continue
            }
            
            // Numbered list
            if line.firstMatch(of: /^[\s]*\d+[.)]\s+(.+)$/) != nil {
                if !currentParagraph.isEmpty {
                    blocks.append(.paragraph(currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentParagraph = ""
                }
                var items: [String] = []
                while i < lines.count, let match = lines[i].firstMatch(of: /^[\s]*\d+[.)]\s+(.+)$/) {
                    items.append(String(match.1))
                    i += 1
                }
                blocks.append(.numberedList(items: items))
                continue
            }
            
            // Blockquote
            if line.hasPrefix(">") {
                if !currentParagraph.isEmpty {
                    blocks.append(.paragraph(currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentParagraph = ""
                }
                var quoteText = ""
                while i < lines.count && lines[i].hasPrefix(">") {
                    quoteText += lines[i].dropFirst().trimmingCharacters(in: .whitespaces) + " "
                    i += 1
                }
                blocks.append(.blockquote(text: quoteText.trimmingCharacters(in: .whitespaces)))
                continue
            }
            
            // Empty line = paragraph break
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !currentParagraph.isEmpty {
                    blocks.append(.paragraph(currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentParagraph = ""
                }
                i += 1
                continue
            }
            
            // Regular text
            currentParagraph += line + " "
            i += 1
        }
        
        // Add remaining paragraph
        if !currentParagraph.isEmpty {
            blocks.append(.paragraph(currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        
        return blocks
    }
}

enum MarkdownBlock {
    case paragraph(String)
    case heading(level: Int, text: String)
    case codeBlock(language: String, code: String)
    case bulletList(items: [String])
    case numberedList(items: [String])
    case blockquote(text: String)
    case horizontalRule
}

// MARK: - NSFont Extension for Traits

extension NSFont {
    func withTraits(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

// MARK: - Pasteable Text Field (supports image paste from clipboard)

struct PasteableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isCompact: Bool
    var onPasteImage: (NSImage) -> Void
    var onSubmit: () -> Void
    
    func makeNSView(context: Context) -> PasteableNSTextField {
        let textField = PasteableNSTextField()
        textField.delegate = context.coordinator
        textField.onPasteImage = onPasteImage
        textField.placeholderString = placeholder
        textField.font = NSFont.systemFont(ofSize: isCompact ? 12 : 13)
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.lineBreakMode = .byWordWrapping
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        return textField
    }
    
    func updateNSView(_ nsView: PasteableNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.onPasteImage = onPasteImage
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PasteableTextField
        
        init(_ parent: PasteableTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if !NSEvent.modifierFlags.contains(.shift) {
                    parent.onSubmit()
                    return true
                }
            }
            return false
        }
    }
}

class PasteableNSTextField: NSTextField {
    var onPasteImage: ((NSImage) -> Void)?
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Check for Cmd+V (paste)
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
            if handleImagePaste() {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
    
    private func handleImagePaste() -> Bool {
        let pasteboard = NSPasteboard.general
        
        // Check for image types in pasteboard
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .tiff,
            .png,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
            .fileURL
        ]
        
        // Try to get image directly
        if let image = NSImage(pasteboard: pasteboard) {
            // Verify it's a valid image with actual data
            if image.isValid && image.size.width > 0 && image.size.height > 0 {
                onPasteImage?(image)
                return true
            }
        }
        
        // Try file URL for image files
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]
                if imageExtensions.contains(url.pathExtension.lowercased()) {
                    if let image = NSImage(contentsOf: url) {
                        onPasteImage?(image)
                        return true
                    }
                }
            }
        }
        
        return false
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
class ChatController: NSObject, ObservableObject, @preconcurrency AVCapturePhotoCaptureDelegate {
    @Published var messages: [ChatMessage] = []
    @Published var pendingAttachments: [ChatAttachment] = []
    @Published var isLoading: Bool = false
    
    var transcriptProvider: (() -> [TranscriptEntry])?
    var clinicalNotesProvider: (() -> [ClinicalNote])?
    
    /// Callback to notify EncounterController when attachments are added
    /// This allows attachments to be included in final SOAP generation
    var attachmentHandler: ((ChatAttachment) -> Void)?
    
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
        
        Help the physician with questions about this case. Be concise and clinically relevant. Use markdown formatting for better readability.
        """
        
        // Build user content with attachments
        var userContent = text
        for attachment in attachments {
            if attachment.type == .image, let base64 = attachment.base64Data {
                userContent += "\n[Image attached: \(attachment.name)]"
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
            "max_tokens": 8192
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
        
        let ext = url.pathExtension.lowercased()
        
        // Check if it's an image - route to image handler for proper multimodal support
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif"]
        if imageExtensions.contains(ext) {
            addImageAttachment(url: url)
            return
        }
        
        // Check if it's a PDF - handle differently for multimodal
        let isPDF = ext == "pdf"
        let textContent = isPDF ? nil : String(data: data, encoding: .utf8)
        let base64Data = isPDF ? data.base64EncodedString() : nil
        let mimeType = isPDF ? "application/pdf" : nil
        
        let attachment = ChatAttachment(
            name: url.lastPathComponent,
            type: .file,
            data: data,
            textContent: textContent,
            base64Data: base64Data,
            mimeType: mimeType,
            thumbnail: nil,
            icon: isPDF ? "doc.richtext.fill" : "doc.fill"
        )
        pendingAttachments.append(attachment)
        attachmentHandler?(attachment)  // Notify encounter controller
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
        attachmentHandler?(attachment)  // Notify encounter controller
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
        attachmentHandler?(attachment)  // Notify encounter controller
    }
    
    func addClipboardImage(image: NSImage) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        
        let base64 = pngData.base64EncodedString()
        
        let attachment = ChatAttachment(
            name: "Pasted Image",
            type: .image,
            data: pngData,
            base64Data: base64,
            mimeType: "image/png",
            thumbnail: image.resized(to: NSSize(width: 100, height: 100)),
            icon: "doc.on.clipboard"
        )
        pendingAttachments.append(attachment)
        attachmentHandler?(attachment)  // Notify encounter controller
        debugLog("✅ Clipboard image pasted", component: "Chat")
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
        attachmentHandler?(attachment)  // Notify encounter controller
    }
    
    func addCameraWindowAttachment(image: NSImage) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        
        let base64 = pngData.base64EncodedString()
        
        let attachment = ChatAttachment(
            name: "Camera Capture",
            type: .image,
            data: pngData,
            base64Data: base64,
            mimeType: "image/png",
            thumbnail: image.resized(to: NSSize(width: 100, height: 100)),
            icon: "camera.fill"
        )
        pendingAttachments.append(attachment)
        attachmentHandler?(attachment)  // Notify encounter controller
        debugLog("✅ Camera capture attached", component: "Camera")
    }
    
    // MARK: - Conversion Helper
    
    /// Convert ChatAttachment to EncounterAttachment for SOAP generation
    static func toEncounterAttachment(_ chatAttachment: ChatAttachment) -> EncounterAttachment {
        let attachmentType: EncounterAttachmentType
        
        // Determine type based on chat attachment type and mime type
        if chatAttachment.type == .image {
            attachmentType = .image
        } else if chatAttachment.mimeType == "application/pdf" {
            attachmentType = .pdf
        } else {
            attachmentType = .textFile
        }
        
        return EncounterAttachment(
            name: chatAttachment.name,
            type: attachmentType,
            base64Data: chatAttachment.base64Data,
            mimeType: chatAttachment.mimeType,
            textContent: chatAttachment.textContent
        )
    }
}

// MARK: - Chat Window Controller

@MainActor
class ChatWindowController {
    private var window: NSWindow?
    
    static let shared = ChatWindowController()
    
    func showChatWindow(
        chatController: ChatController,
        transcriptProvider: @escaping () -> [TranscriptEntry],
        clinicalNotesProvider: @escaping () -> [ClinicalNote]
    ) {
        // Close existing window if any
        window?.close()
        
        // Ensure providers are set
        chatController.transcriptProvider = transcriptProvider
        chatController.clinicalNotesProvider = clinicalNotesProvider
        
        let chatWindowView = ChatWindowContentView(
            chatController: chatController,
            onCollapse: { [weak self] in
                self?.window?.close()
                self?.window = nil
            }
        )
        
        let hostingView = NSHostingView(rootView: chatWindowView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Chat - Gemini 3 Pro"
        window.contentView = hostingView
        window.center()
        window.setFrameAutosaveName("ChatWindow")
        window.minSize = NSSize(width: 400, height: 400)
        window.isReleasedWhenClosed = false
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        self.window = window
    }
    
    func closeWindow() {
        window?.close()
        window = nil
    }
}

// MARK: - Chat Window Content View

struct ChatWindowContentView: View {
    @ObservedObject var chatController: ChatController
    let onCollapse: () -> Void
    
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundColor(.purple)
                
                Text("Chat with Gemini 3 Pro")
                    .font(.system(size: 14, weight: .semibold))
                
                Spacer()
                
                if chatController.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }
                
                Button(action: onCollapse) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Collapse back to sidebar")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Chat content
            ChatContentView(
                chatController: chatController,
                inputText: $inputText,
                isInputFocused: _isInputFocused,
                isCompact: false
            )
            .padding(12)
        }
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
    .frame(width: 380, height: 600)
}
