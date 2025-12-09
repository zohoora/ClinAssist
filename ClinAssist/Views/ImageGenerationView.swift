import SwiftUI
import AppKit

// MARK: - Generated Image Model

struct GeneratedImage: Identifiable {
    let id = UUID()
    let prompt: String
    let image: NSImage
    let timestamp: Date
}

// MARK: - Image Generation Controller

@MainActor
class ImageGenerationController: ObservableObject {
    @Published var isGenerating: Bool = false
    @Published var generatedImages: [GeneratedImage] = []
    @Published var errorMessage: String?
    
    private var imageClient: GeminiImageClient?
    
    init() {
        setupClient()
    }
    
    private func setupClient() {
        // Prefer OpenRouter (user already has this configured)
        // Fall back to direct Gemini API if available
        if let config = ConfigManager.shared.config {
            if !config.openrouterApiKey.isEmpty {
                // Use OpenRouter with Gemini's image generation
                imageClient = GeminiImageClient(apiKey: config.openrouterApiKey, useOpenRouter: true)
                debugLog("🎨 Image client initialized via OpenRouter", component: "ImageGen")
            } else if let geminiKey = config.geminiApiKey, !geminiKey.isEmpty {
                // Fall back to direct Gemini Imagen API
                imageClient = GeminiImageClient(apiKey: geminiKey, useOpenRouter: false)
                debugLog("🎨 Image client initialized via direct Gemini API", component: "ImageGen")
            } else {
                debugLog("⚠️ No API key configured for image generation", component: "ImageGen")
            }
        }
    }
    
    func generateImage(prompt: String) async {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        guard let client = imageClient else {
            errorMessage = "No API key configured for image generation"
            return
        }
        
        isGenerating = true
        errorMessage = nil
        
        do {
            let image = try await client.generateImage(prompt: prompt)
            
            let generatedImage = GeneratedImage(
                prompt: prompt,
                image: image,
                timestamp: Date()
            )
            
            generatedImages.append(generatedImage)
            
            // Show the image in a popup window
            ImagePopupController.shared.showImage(generatedImage)
            
        } catch {
            errorMessage = error.localizedDescription
            debugLog("❌ Image generation failed: \(error)", component: "ImageGen")
        }
        
        isGenerating = false
    }
    
    func showImage(_ image: GeneratedImage) {
        ImagePopupController.shared.showImage(image)
    }
    
    func clearHistory() {
        generatedImages.removeAll()
    }
}

// MARK: - Image Generation View

struct ImageGenerationView: View {
    @StateObject private var controller = ImageGenerationController()
    @State private var promptText: String = ""
    @State private var isExpanded: Bool = false
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("IMAGE GENERATION")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text("(Gemini 3 Pro)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                
                if !controller.generatedImages.isEmpty {
                    Text("• \(controller.generatedImages.count)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                
                Spacer()
                
                if controller.isGenerating {
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
                VStack(spacing: 10) {
                    // Input area
                    HStack(spacing: 8) {
                        TextField("Describe the image to generate...", text: $promptText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .lineLimit(1...3)
                            .padding(8)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .focused($isInputFocused)
                            .onSubmit {
                                if !promptText.isEmpty && !controller.isGenerating {
                                    generateImage()
                                }
                            }
                        
                        Button(action: generateImage) {
                            Image(systemName: controller.isGenerating ? "hourglass" : "wand.and.stars")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(controller.isGenerating || promptText.isEmpty ? Color.gray : Color.purple)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(controller.isGenerating || promptText.isEmpty)
                    }
                    
                    // Error message
                    if let error = controller.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                    }
                    
                    // Generated images history
                    if !controller.generatedImages.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Session Images")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Button(action: { controller.clearHistory() }) {
                                    Text("Clear")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(controller.generatedImages.reversed()) { genImage in
                                        ImageThumbnailView(generatedImage: genImage) {
                                            controller.showImage(genImage)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }
    
    private func generateImage() {
        let prompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        
        Task {
            await controller.generateImage(prompt: prompt)
        }
        promptText = ""
    }
}

// MARK: - Image Thumbnail View

struct ImageThumbnailView: View {
    let generatedImage: GeneratedImage
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: generatedImage.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            
            Text(formatTime(generatedImage.timestamp))
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .onTapGesture {
            onTap()
        }
        .help(generatedImage.prompt)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Image Popup Controller

class ImagePopupController {
    static let shared = ImagePopupController()
    private var window: NSWindow?
    
    func showImage(_ generatedImage: GeneratedImage) {
        DispatchQueue.main.async { [weak self] in
            self?.createAndShowWindow(for: generatedImage)
        }
    }
    
    private func createAndShowWindow(for generatedImage: GeneratedImage) {
        // Close existing window
        window?.close()
        
        let popupView = ImagePopupView(generatedImage: generatedImage)
        let hostingView = NSHostingView(rootView: popupView)
        
        // Calculate window size based on image
        let imageSize = generatedImage.image.size
        let maxDimension: CGFloat = 800
        let minDimension: CGFloat = 400
        
        var width = imageSize.width
        var height = imageSize.height
        
        if width > maxDimension || height > maxDimension {
            let scale = maxDimension / max(width, height)
            width *= scale
            height *= scale
        }
        
        width = max(width, minDimension)
        height = max(height, minDimension) + 80 // Extra for prompt text
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "Generated Image"
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.minSize = NSSize(width: 300, height: 350)
        newWindow.isReleasedWhenClosed = false
        
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        window = newWindow
    }
}

// MARK: - Image Popup View

struct ImagePopupView: View {
    let generatedImage: GeneratedImage
    @State private var isCopied: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Image
            Image(nsImage: generatedImage.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            
            // Info bar
            VStack(spacing: 8) {
                // Prompt
                Text(generatedImage.prompt)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Actions
                HStack(spacing: 12) {
                    Button(action: copyImage) {
                        HStack(spacing: 4) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            Text(isCopied ? "Copied!" : "Copy Image")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: saveImage) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Text(formatTimestamp(generatedImage.timestamp))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
    
    private func copyImage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([generatedImage.image])
        isCopied = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }
    
    private func saveImage() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "generated_image_\(Int(Date().timeIntervalSince1970)).png"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                if let tiffData = generatedImage.image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: url)
                }
            }
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm:ss"
        return formatter.string(from: date)
    }
}

#Preview {
    ImageGenerationView()
        .padding()
        .frame(width: 380)
}

