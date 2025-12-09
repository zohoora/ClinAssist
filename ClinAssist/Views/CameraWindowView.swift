import SwiftUI
import AVFoundation
import AppKit

// MARK: - Camera Window View

struct CameraWindowView: View {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (NSImage) -> Void
    
    @StateObject private var cameraManager = SimpleCameraManager()
    @State private var selectedDeviceID: String = ""
    @State private var selectionRect: CGRect = .zero
    @State private var isSelecting: Bool = false
    @State private var selectionStart: CGPoint = .zero
    @State private var showSelectionOverlay: Bool = false
    @State private var previewSize: CGSize = .zero
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Camera Capture")
                    .font(.system(size: 14, weight: .semibold))
                
                Spacer()
                
                // Camera selector
                if cameraManager.availableCameras.count > 0 {
                    HStack(spacing: 4) {
                        Text("Camera")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Picker("", selection: $selectedDeviceID) {
                            ForEach(cameraManager.availableCameras, id: \.uniqueID) { camera in
                                Text(camera.localizedName)
                                    .tag(camera.uniqueID)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 180)
                        .onChange(of: selectedDeviceID) { _, newValue in
                            if let camera = cameraManager.availableCameras.first(where: { $0.uniqueID == newValue }) {
                                cameraManager.selectCamera(camera)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Camera preview area
            ZStack {
                // Camera preview
                SimpleCameraPreview(cameraManager: cameraManager)
                    .background(Color.black)
                    .overlay(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { previewSize = geo.size }
                                .onChange(of: geo.size) { _, newSize in previewSize = newSize }
                        }
                    )
                
                // Selection overlay
                if showSelectionOverlay && selectionRect.width > 0 && selectionRect.height > 0 {
                    SelectionOverlayView(selectionRect: selectionRect, previewSize: previewSize)
                }
                
                // Drag gesture for selection
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { value in
                                if !isSelecting {
                                    isSelecting = true
                                    selectionStart = value.startLocation
                                    showSelectionOverlay = true
                                }
                                let current = value.location
                                selectionRect = CGRect(
                                    x: min(selectionStart.x, current.x),
                                    y: min(selectionStart.y, current.y),
                                    width: abs(current.x - selectionStart.x),
                                    height: abs(current.y - selectionStart.y)
                                )
                            }
                            .onEnded { _ in isSelecting = false }
                    )
                
                // Instructions
                if !showSelectionOverlay && cameraManager.isRunning {
                    VStack {
                        Spacer()
                        Text("Drag to select a region, or capture the full frame")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(6)
                            .padding(.bottom, 16)
                    }
                }
                
                // Loading/Error state
                if !cameraManager.isRunning {
                    VStack(spacing: 12) {
                        if cameraManager.permissionDenied {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("Camera access denied")
                                .font(.system(size: 14, weight: .medium))
                            Text("Enable in System Settings > Privacy & Security > Camera")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        } else if let error = cameraManager.errorMessage {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 40))
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        } else {
                            ProgressView()
                            Text("Starting camera...")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor))
                }
            }
            .frame(minHeight: 300)
            
            Divider()
            
            // Bottom toolbar
            HStack(spacing: 16) {
                Button(action: { selectionRect = .zero; showSelectionOverlay = false }) {
                    Label("Clear Selection", systemImage: "xmark.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .disabled(!showSelectionOverlay)
                .opacity(showSelectionOverlay ? 1 : 0.5)
                
                Spacer()
                
                if showSelectionOverlay && selectionRect.width > 0 {
                    Text("Selection: \(Int(selectionRect.width)) × \(Int(selectionRect.height))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                
                Button(action: captureImage) {
                    Label(showSelectionOverlay ? "Capture Region" : "Capture Full", systemImage: "camera.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(cameraManager.isRunning ? Color.blue : Color.gray)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(!cameraManager.isRunning)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            cameraManager.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if selectedDeviceID.isEmpty, let first = cameraManager.availableCameras.first {
                    selectedDeviceID = first.uniqueID
                }
            }
        }
        .onDisappear {
            cameraManager.stop()
        }
    }
    
    private func captureImage() {
        debugLog("Capture button pressed, isRunning: \(cameraManager.isRunning)", component: "Camera")
        
        guard cameraManager.isRunning else {
            debugLog("Camera not running, aborting capture", component: "Camera")
            return
        }
        
        cameraManager.capturePhoto { [self] image in
            debugLog("Photo completion called, image: \(image != nil)", component: "Camera")
            
            guard let capturedImage = image else {
                debugLog("No image received from capture", component: "Camera")
                return
            }
            
            var finalImage = capturedImage
            
            // Crop if selection exists
            if showSelectionOverlay && selectionRect.width > 10 && selectionRect.height > 10 && previewSize.width > 0 {
                if let cropped = cropImageToSelection(capturedImage) {
                    finalImage = cropped
                }
            }
            
            debugLog("Calling onCapture with image size: \(finalImage.size)", component: "Camera")
            onCapture(finalImage)
            dismiss()
        }
    }
    
    private func cropImageToSelection(_ image: NSImage) -> NSImage? {
        let imageSize = image.size
        guard imageSize.width > 0 && imageSize.height > 0 else { return nil }
        
        let viewAspect = previewSize.width / previewSize.height
        let imageAspect = imageSize.width / imageSize.height
        
        var cropRect: CGRect
        
        if imageAspect > viewAspect {
            let scaleFactor = previewSize.width / imageSize.width
            let scaledHeight = imageSize.height * scaleFactor
            let yOffset = (previewSize.height - scaledHeight) / 2
            let adjustedY = selectionRect.minY - yOffset
            cropRect = CGRect(
                x: selectionRect.minX / scaleFactor,
                y: adjustedY / scaleFactor,
                width: selectionRect.width / scaleFactor,
                height: selectionRect.height / scaleFactor
            )
        } else {
            let scaleFactor = previewSize.height / imageSize.height
            let scaledWidth = imageSize.width * scaleFactor
            let xOffset = (previewSize.width - scaledWidth) / 2
            let adjustedX = selectionRect.minX - xOffset
            cropRect = CGRect(
                x: adjustedX / scaleFactor,
                y: selectionRect.minY / scaleFactor,
                width: selectionRect.width / scaleFactor,
                height: selectionRect.height / scaleFactor
            )
        }
        
        cropRect = cropRect.intersection(CGRect(origin: .zero, size: imageSize))
        guard cropRect.width > 10 && cropRect.height > 10 else { return nil }
        
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        
        let flippedRect = CGRect(
            x: cropRect.minX,
            y: CGFloat(cgImage.height) - cropRect.maxY,
            width: cropRect.width,
            height: cropRect.height
        )
        
        guard let croppedCG = cgImage.cropping(to: flippedRect) else { return nil }
        return NSImage(cgImage: croppedCG, size: cropRect.size)
    }
}

// MARK: - Selection Overlay

struct SelectionOverlayView: View {
    let selectionRect: CGRect
    let previewSize: CGSize
    
    var body: some View {
        ZStack {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: previewSize))
                path.addRect(selectionRect)
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
            
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: selectionRect.width, height: selectionRect.height)
                .position(x: selectionRect.midX, y: selectionRect.midY)
        }
    }
}

// MARK: - Simple Camera Manager (Non-MainActor)

class SimpleCameraManager: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var permissionDenied = false
    @Published var errorMessage: String?
    @Published var availableCameras: [AVCaptureDevice] = []
    
    private var session: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var currentDevice: AVCaptureDevice?
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    
    private var photoCaptureCompletion: ((NSImage?) -> Void)?
    
    override init() {
        super.init()
        loadCameras()
    }
    
    func loadCameras() {
        availableCameras = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        ).devices
    }
    
    func start() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.setupAndStart()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.global(qos: .userInitiated).async {
                        self?.setupAndStart()
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.permissionDenied = true
                    }
                }
            }
        default:
            DispatchQueue.main.async { [weak self] in
                self?.permissionDenied = true
            }
        }
    }
    
    private func setupAndStart() {
        loadCameras()
        
        guard let device = availableCameras.first else {
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = "No camera found"
            }
            return
        }
        
        setupSession(with: device)
    }
    
    private func setupSession(with device: AVCaptureDevice) {
        let newSession = AVCaptureSession()
        
        do {
            newSession.beginConfiguration()
            newSession.sessionPreset = .photo
            
            let input = try AVCaptureDeviceInput(device: device)
            guard newSession.canAddInput(input) else {
                throw NSError(domain: "Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add input"])
            }
            newSession.addInput(input)
            
            let output = AVCapturePhotoOutput()
            guard newSession.canAddOutput(output) else {
                throw NSError(domain: "Camera", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add output"])
            }
            newSession.addOutput(output)
            
            newSession.commitConfiguration()
            
            let layer = AVCaptureVideoPreviewLayer(session: newSession)
            layer.videoGravity = .resizeAspect
            
            self.session = newSession
            self.photoOutput = output
            self.currentDevice = device
            
            DispatchQueue.main.async { [weak self] in
                self?.previewLayer = layer
            }
            
            newSession.startRunning()
            
            DispatchQueue.main.async { [weak self] in
                self?.isRunning = true
                self?.errorMessage = nil
            }
            
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = "Camera error: \(error.localizedDescription)"
            }
        }
    }
    
    func selectCamera(_ device: AVCaptureDevice) {
        guard device.uniqueID != currentDevice?.uniqueID else { return }
        
        stop()
        
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.setupSession(with: device)
        }
    }
    
    func stop() {
        session?.stopRunning()
        session = nil
        photoOutput = nil
        currentDevice = nil
        
        DispatchQueue.main.async { [weak self] in
            self?.previewLayer = nil
            self?.isRunning = false
        }
    }
    
    func capturePhoto(completion: @escaping (NSImage?) -> Void) {
        debugLog("capturePhoto called, session running: \(session?.isRunning ?? false)", component: "Camera")
        
        // Try photo output first
        if let output = photoOutput, let session = session, session.isRunning {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    completion(nil)
                    return
                }
                
                self.photoCaptureCompletion = completion
                
                let settings = AVCapturePhotoSettings()
                debugLog("Initiating photo capture via AVCapturePhotoOutput...", component: "Camera")
                output.capturePhoto(with: settings, delegate: self)
            }
        } else {
            // Fallback: capture from preview layer
            debugLog("Falling back to preview layer capture", component: "Camera")
            captureFromPreviewLayer(completion: completion)
        }
    }
    
    private func captureFromPreviewLayer(completion: @escaping (NSImage?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let layer = self?.previewLayer else {
                debugLog("No preview layer for fallback capture", component: "Camera")
                completion(nil)
                return
            }
            
            // Create an image from the preview layer
            let size = layer.bounds.size
            guard size.width > 0 && size.height > 0 else {
                debugLog("Preview layer has zero size", component: "Camera")
                completion(nil)
                return
            }
            
            let image = NSImage(size: size)
            image.lockFocus()
            
            if let context = NSGraphicsContext.current?.cgContext {
                layer.render(in: context)
            }
            
            image.unlockFocus()
            
            debugLog("Captured from preview layer: \(image.size)", component: "Camera")
            completion(image)
        }
    }
}

extension SimpleCameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        debugLog("Photo capture delegate called", component: "Camera")
        
        let completion = photoCaptureCompletion
        photoCaptureCompletion = nil
        
        if let error = error {
            debugLog("Photo capture error: \(error.localizedDescription)", component: "Camera")
            DispatchQueue.main.async {
                completion?(nil)
            }
            return
        }
        
        guard let data = photo.fileDataRepresentation() else {
            debugLog("No image data from photo", component: "Camera")
            DispatchQueue.main.async {
                completion?(nil)
            }
            return
        }
        
        guard let image = NSImage(data: data) else {
            debugLog("Could not create NSImage from data", component: "Camera")
            DispatchQueue.main.async {
                completion?(nil)
            }
            return
        }
        
        debugLog("Photo captured successfully: \(image.size)", component: "Camera")
        DispatchQueue.main.async {
            completion?(image)
        }
    }
}

// MARK: - Simple Camera Preview

struct SimpleCameraPreview: NSViewRepresentable {
    @ObservedObject var cameraManager: SimpleCameraManager
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Remove any existing preview layers
        nsView.layer?.sublayers?.filter { $0 is AVCaptureVideoPreviewLayer }.forEach { $0.removeFromSuperlayer() }
        
        if let layer = cameraManager.previewLayer {
            layer.frame = nsView.bounds
            nsView.layer?.addSublayer(layer)
            
            // Update frame when view resizes
            DispatchQueue.main.async {
                layer.frame = nsView.bounds
            }
        }
    }
}

// MARK: - Camera Window Controller

class CameraWindowController {
    private var window: NSWindow?
    static let shared = CameraWindowController()
    
    func showCameraWindow(onCapture: @escaping (NSImage) -> Void) {
        window?.close()
        
        let cameraView = CameraWindowView(onCapture: { [weak self] image in
            onCapture(image)
            self?.window?.close()
            self?.window = nil
        })
        
        let hostingView = NSHostingView(rootView: cameraView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "Camera Capture"
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.setFrameAutosaveName("CameraWindow")
        newWindow.minSize = NSSize(width: 480, height: 360)
        newWindow.isReleasedWhenClosed = false
        
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        window = newWindow
    }
}

#Preview {
    CameraWindowView(onCapture: { _ in })
        .frame(width: 720, height: 540)
}
