import SwiftUI
import AVFoundation
import UIKit
import Vision
import CoreImage
import WebKit
import Combine
import CoreHaptics

struct SelfieCameraSheet: View {
    @Binding var isPresented: Bool
    let onVideoRecorded: (URL) -> Void
    
    @StateObject private var cameraManager = SelfieCameraManager()
    @State private var isRecording = false
    @State private var hasRecordedVideo = false
    @State private var recordingProgress: Double = 0.0
    @State private var recordingRemaining: Double = 2.0
    @State private var recordingStart: Date?
    @State private var isRecordingUIFrozen: Bool = false
    @State private var recordedVideoURL: URL?
    @State private var selfieGIFURL: URL?
    @State private var isProcessingGIF: Bool = false
    @State private var didForwardRecording: Bool = false
    @State private var gifDisplayHeight: CGFloat = 150
    @State private var isLoadingPulse: Bool = false
    @State private var isLiftingPulse: Bool = false
    private let countdownTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                // Background checkerboard or white
                Group {
                    if hasRecordedVideo {
                        CheckerboardView()
                    } else {
                        Color.white
                    }
                }
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Handle bar
                    EmptyView()

                    // Main content fills remaining space
                    ZStack {
                        if isProcessingGIF {
                            ZStack {
                                Image("selfie-white")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 84, height: 84)
                                    .foregroundColor(.neon)
                                    .shadow(color: Color.black.opacity(isLoadingPulse ? 0.4 : 0.3), radius: isLoadingPulse ? 30 : 14, x: 0, y: 0)
                                    .scaleEffect(isLoadingPulse ? 1.1 : 0.8)
                                    .opacity(isLoadingPulse ? 1.0 : 0.8)
                            }
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isLoadingPulse)
                            .onAppear { isLoadingPulse = true }
                            .onDisappear { isLoadingPulse = false }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if cameraManager.isSessionRunning {
                            // Preview or GIF
                            if let gifURL = selfieGIFURL {
                                GIFWebView(url: gifURL)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .ignoresSafeArea()
                            } else {
                                Group {
                                    if let frame = cameraManager.processedFrame {
                                        Image(uiImage: frame)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .clipped()
                                    } else {
                                        SelfieCameraPreview(session: cameraManager.captureSession)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                }
                                .padding(-1)
                                .ignoresSafeArea()
                                .background(Color.white)
                                // Show pulsing selfie icon while background lifting gets ready (iOS 17+)
                                .overlay(alignment: .center) {
                                    if !hasRecordedVideo {
                                        let liftingReady: Bool = {
                                            if #available(iOS 17.0, *) { return cameraManager.processedFrame != nil } else { return true }
                                        }()
                                        if !liftingReady {
                                            Image("selfie-white")
                                                .renderingMode(.template)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 84, height: 84)
                                                .foregroundColor(.neon)
                                                .shadow(color: Color.black.opacity(isLiftingPulse ? 0.4 : 0.3), radius: isLiftingPulse ? 30 : 14, x: 0, y: 0)
                                                .scaleEffect(isLiftingPulse ? 1.1 : 0.8)
                                                .opacity(isLiftingPulse ? 1.0 : 0.85)
                                                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isLiftingPulse)
                                                .onAppear { isLiftingPulse = true }
                                                .onDisappear { isLiftingPulse = false }
                                        }
                                    }
                                }
                                .overlay(alignment: .bottom) {
                                    if !hasRecordedVideo {
                                        let baseButton: CGFloat = 65
                                        let baseRingAdd: CGFloat = 8
                                        let size: CGFloat = baseButton
                                        let ringSize: CGFloat = (baseButton + baseRingAdd)
                                        let liftingReady: Bool = {
                                            if #available(iOS 17.0, *) { return cameraManager.processedFrame != nil } else { return true }
                                        }()
                                        ZStack {
                                            Circle()
                                                .stroke(liftingReady ? Color.white.opacity(0.80) : Color(.systemGray4), lineWidth: 4)
                                                .frame(width: ringSize, height: ringSize)
                                            Circle()
                                                .trim(from: 0, to: recordingProgress)
                                                .stroke(
                                                    (isRecording || isRecordingUIFrozen)
                                                    ? Color.neon
                                                    : (liftingReady ? Color.white : Color(.systemGray4)),
                                                    style: StrokeStyle(lineWidth: 4)
                                                )
                                                .blendMode(.normal)
                                                .opacity(1)
                                                .rotationEffect(.degrees(-90))
                                                .frame(width: ringSize, height: ringSize)
                                            Button(action: { if isRecording { stopRecording() } else { startRecording() } }) {
                                                Circle()
                                                    .fill(
                                                        (isRecording || isRecordingUIFrozen)
                                                        ? Color.neon
                                                        : (liftingReady ? Color.white.opacity(0.80) : Color(.systemGray4))
                                                    )
                                                    .frame(width: size, height: size)
                                                    .overlay(
                                                        Group {
                                                            if (isRecording || isRecordingUIFrozen) {
                                                                Text(String(format: "%.1f", recordingRemaining))
                                                                    .font(.system(size: size * 0.32))
                                                                    .monospacedDigit()
                                                                    .foregroundColor(.black)
                                                            } else {
                                                                Image("selfie-white")
                                                                    .renderingMode(.template)
                                                                    .resizable()
                                                                    .scaledToFit()
                                                                    .foregroundColor(.black)
                                                                    .frame(width: size * 0.45, height: size * 0.45)
                                                            }
                                                        }
                                                    )
                                            }
                                            .disabled(!liftingReady)
                                        }
                                        .padding(.bottom, 110)
                                    }
                                }
                            }
                        } else {
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .ignoresSafeArea(edges: .bottom)

                // Overlay controls on top of GIF/preview
                VStack(spacing: 0) {
                    if let _ = selfieGIFURL {
                        HStack(spacing: 12) {
                            // Retake (left) with banner — match size, icon, font
                            Button(action: {
                                selfieGIFURL = nil
                                recordedVideoURL = nil
                                hasRecordedVideo = false
                                didForwardRecording = false
                            }) {
                                HStack(spacing: 8) {
                                    Image("Retake")
                                        .renderingMode(.template)
                                        .resizable()
                                        .foregroundColor(.black)
                                        .frame(width: 20, height: 20)
                                    Text("Retake")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.black)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 60)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                            }
                            .buttonStyle(.plain)

                            // Continue (right) with banner — match size, icon, font
                            Button(action: {
                                if let url = recordedVideoURL, !didForwardRecording {
                                    didForwardRecording = true
                                    onVideoRecorded(url)
                                }
                                isPresented = false
                            }) {
                                HStack(spacing: 8) {
                                    Image("add")
                                        .renderingMode(.template)
                                        .resizable()
                                        .foregroundColor(.black)
                                        .frame(width: 20, height: 20)
                                    Text("Add")
                                        .font(.system(size: 20, weight: .semibold))
                                }
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 60)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.78, green: 1.00, blue: 0.20),
                                            Color(red: 0.62, green: 0.90, blue: 0.00)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 36)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationBarHidden(true)
        }
        .onReceive(countdownTimer) { _ in
            if isRecording, let start = recordingStart {
                let elapsed = Date().timeIntervalSince(start)
                recordingRemaining = max(0.0, 2.0 - elapsed)
            } else if isRecordingUIFrozen {
                recordingRemaining = max(0.0, recordingRemaining)
            } else {
                recordingRemaining = 2.0
            }
        }
        .onDisappear {
            if let url = recordedVideoURL, hasRecordedVideo, !didForwardRecording {
                didForwardRecording = true
                onVideoRecorded(url)
            }
            cameraManager.stopSession()
        }
        .alert("Camera Error", isPresented: $cameraManager.showError) { Button("OK") { } } message: { Text(cameraManager.errorMessage) }
        .presentationDetents([.height(UIScreen.main.bounds.height * 0.7)])
        .presentationCornerRadius(35)
    }
    
    private func startRecording() {
        guard !isRecording else { return }
        
        isRecording = true
        isRecordingUIFrozen = false
        recordingProgress = 0.0
        recordingStart = Date()
        recordingRemaining = 2.0
        
        // Start continuous medium haptic for the full 2s
        cameraManager.startContinuousHaptics(duration: 2.0)
        
        cameraManager.startRecording { success in
            if success {
                // Start progress animation
                withAnimation(.linear(duration: 2.0)) {
                    recordingProgress = 1.0
                }
                
                // Auto-stop after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    stopRecording()
                }
            } else {
                isRecording = false
                isRecordingUIFrozen = false
                recordingProgress = 0.0
                recordingStart = nil
                recordingRemaining = 2.0
                cameraManager.stopHaptics()
            }
        }
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        recordingProgress = 0.0
        recordingStart = nil
        // Freeze UI in recording look with 0.0 until preview replaces it
        isRecordingUIFrozen = true
        recordingRemaining = 0.0
        
        // Stop haptics when recording ends
        cameraManager.stopHaptics()
        
        cameraManager.stopRecording { videoURL in
            if let url = videoURL {
                // Store video for later forwarding and show GIF preview
                recordedVideoURL = url
                hasRecordedVideo = true
                isProcessingGIF = true
                selfieGIFURL = nil
                Task {
                    if let gif = await PhotoLibraryStickerService.shared.processSelfieVideoAsAnimatedSticker(videoURL: url) {
                        await MainActor.run {
                            selfieGIFURL = gif
                            // Compute display height maintaining aspect ratio for width = 150 (not used when filling)
                            if let size = SelfieCameraSheet.getGIFPixelSize(from: gif) {
                                let aspect = size.height / max(size.width, 1)
                                gifDisplayHeight = 150 * aspect
                            } else {
                                gifDisplayHeight = 150
                            }
                            isProcessingGIF = false
                            isRecordingUIFrozen = false
                        }
                    } else {
                        await MainActor.run {
                            isProcessingGIF = false
                            isRecordingUIFrozen = false
                        }
                    }
                }
            }
        }
    }
}

// Checkerboard background for transparency preview
struct CheckerboardView: View {
    let square: CGFloat = 28 // 2x bigger than before
    let colorA = Color(white: 0.92)
    let colorB = Color(white: 0.82)
    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let cols = Int(ceil(size.width / square))
                let rows = Int(ceil(size.height / square))
                for r in 0..<rows {
                    for c in 0..<cols {
                        let rect = CGRect(x: CGFloat(c) * square, y: CGFloat(r) * square, width: square, height: square)
                        let color = ((r + c) % 2 == 0) ? colorA : colorB
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - GIF WebView
struct GIFWebView: UIViewRepresentable {
    let url: URL
    let objectFit: String

    init(url: URL, objectFit: String = "cover") {
        self.url = url
        self.objectFit = objectFit
    }
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        // Ensure embedded GIFs in carousels never steal gestures (tap/long-press/drag)
        webView.isUserInteractionEnabled = false
        webView.allowsLinkPreview = false
        webView.scrollView.isUserInteractionEnabled = false
        if #available(iOS 11.0, *) {
            webView.scrollView.contentInsetAdjustmentBehavior = .never
        }
        return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if url.isFileURL {
            if let data = try? Data(contentsOf: url) {
                let ext = url.pathExtension.lowercased()
                let mime: String = {
                    switch ext {
                    case "webp": return "image/webp"
                    case "gif": return "image/gif"
                    case "png": return "image/png"
                    case "jpg", "jpeg": return "image/jpeg"
                    default: return "image/webp"
                    }
                }()
                let b64 = data.base64EncodedString()
                let html = """
                <html>
                  <head>
                    <meta name='viewport' content='initial-scale=1, width=device-width, height=device-height, viewport-fit=cover'/>
                    <style>
                      html, body { margin:0; padding:0; width:100%; height:100%; background:transparent; -webkit-user-select:none; -webkit-touch-callout:none; user-select:none; }
                      img { width:100%; height:100%; object-fit: \(objectFit); object-position: center center; display:block; opacity:0; transition:opacity 0.15s ease-out; pointer-events:none; }
                    </style>
                  </head>
                  <body>
                    <img src='data:\(mime);base64,\(b64)' onload="this.style.opacity=1" />
                  </body>
                </html>
                """
                uiView.loadHTMLString(html, baseURL: nil)
            } else {
                // Fallback to directory + filename if data read fails
                let base = url.deletingLastPathComponent()
                let html = """
                <html>
                  <head>
                    <meta name='viewport' content='initial-scale=1, width=device-width, height=device-height, viewport-fit=cover'/>
                    <style>
                      html, body { margin:0; padding:0; width:100%; height:100%; background:transparent; -webkit-user-select:none; -webkit-touch-callout:none; user-select:none; }
                      img { width:100%; height:100%; object-fit: \(objectFit); object-position: center center; display:block; opacity:0; transition:opacity 0.15s ease-out; pointer-events:none; }
                    </style>
                  </head>
                  <body>
                    <img src='\(url.lastPathComponent)' onload="this.style.opacity=1" />
                  </body>
                </html>
                """
                uiView.loadHTMLString(html, baseURL: base)
            }
        } else {
            // Remote URL: use absolute string to avoid base URL restrictions
            let html = """
            <html>
              <head>
                <meta name='viewport' content='initial-scale=1, width=device-width, height=device-height, viewport-fit=cover'/>
                <style>
                  html, body { margin:0; padding:0; width:100%; height:100%; background:transparent; -webkit-user-select:none; -webkit-touch-callout:none; user-select:none; }
                  img { width:100%; height:100%; object-fit: \(objectFit); object-position: center center; display:block; opacity:0; transition:opacity 0.15s ease-out; pointer-events:none; }
                </style>
              </head>
              <body>
                <img src='\(url.absoluteString)' onload="this.style.opacity=1" />
              </body>
            </html>
            """
            uiView.loadHTMLString(html, baseURL: nil)
        }
    }
}

// MARK: - GIF utilities
extension SelfieCameraSheet {
    static func getGIFPixelSize(from url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(src) > 0,
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            return nil
        }
        return CGSize(width: cg.width, height: cg.height)
    }
}

// MARK: - Camera Preview
struct SelfieCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.session = session
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        // Update is handled by the CameraPreviewView itself
    }
}

// Custom UIView for camera preview
class CameraPreviewView: UIView {
    var session: AVCaptureSession? {
        didSet {
            guard let session = session else { return }
            previewLayer.session = session
        }
    }
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        previewLayer.videoGravity = .resizeAspectFill
        print("🤳 Camera preview layer frame updated: \(bounds)")
    }
}

// MARK: - Camera Manager
class SelfieCameraManager: NSObject, ObservableObject {
    @Published var isSessionRunning = false
    @Published var showError = false
    @Published var errorMessage = ""
	@Published var processedFrame: UIImage?
    
    let captureSession = AVCaptureSession()
    private var videoOutput: AVCaptureMovieFileOutput?
	private var videoDataOutput: AVCaptureVideoDataOutput?
    private var currentVideoURL: URL?
    private var recordingCompletion: ((Bool) -> Void)?
    private var stopRecordingCompletion: ((URL?) -> Void)?
	
	// Haptics
	private var hapticsEngine: CHHapticEngine?
	private var hapticPlayer: CHHapticAdvancedPatternPlayer?
	private var hapticTimer: Timer?
	
	// Vision foreground instance mask (iOS 17+)
	@available(iOS 17.0, *)
	private lazy var foregroundRequest: VNGenerateForegroundInstanceMaskRequest = {
		VNGenerateForegroundInstanceMaskRequest()
	}()
	private let ciContext = CIContext()
	private let segmentationQueue = DispatchQueue(label: "SelfieSegmentationQueue")
	private var lastSegmentationTime: CFTimeInterval = CFAbsoluteTimeGetCurrent() - 1
	private let minSegmentationInterval: CFTimeInterval = 0.1 // ~10 FPS
    
    override init() {
        super.init()
        prepareHaptics()
        requestCameraPermission()
    }
    
    private func requestCameraPermission() {
        print("🤳 Requesting camera permission...")
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            print("✅ Camera permission already granted")
            setupCamera()
        case .notDetermined:
            print("⏳ Requesting camera permission...")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        print("✅ Camera permission granted")
                        self?.setupCamera()
                    } else {
                        print("❌ Camera permission denied")
                        self?.showError("Camera permission denied")
                    }
                }
            }
        case .denied, .restricted:
            print("❌ Camera permission denied or restricted")
            showError("Camera access denied. Please enable camera access in Settings.")
        @unknown default:
            print("❌ Unknown camera permission status")
            showError("Camera permission status unknown")
        }
    }
    
    private func setupCamera() {
        print("🤳 Setting up selfie camera...")
        
        captureSession.sessionPreset = .high
        
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("❌ Front camera not available")
            showError("Front camera not available")
            return
        }
        
        print("✅ Front camera found: \(frontCamera.localizedName)")
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: frontCamera)
            
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
                print("✅ Video input added to session")
            } else {
                print("❌ Cannot add video input to session")
                showError("Cannot add camera input")
                return
            }
            
            // Add video output for recording
            videoOutput = AVCaptureMovieFileOutput()
            if let videoOutput = videoOutput, captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
                
                // Set maximum recording duration to 3 seconds (with buffer)
                videoOutput.maxRecordedDuration = CMTime(seconds: 3.0, preferredTimescale: 600)
                print("✅ Video output added to session")
            } else {
                print("❌ Cannot add video output to session")
            }
            
				print("✅ Selfie camera setup completed")
            
				// Add video data output for real-time segmentation preview
				let dataOutput = AVCaptureVideoDataOutput()
				dataOutput.alwaysDiscardsLateVideoFrames = true
				dataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
				if captureSession.canAddOutput(dataOutput) {
					captureSession.addOutput(dataOutput)
					let connection = dataOutput.connection(with: .video)
					connection?.isVideoMirrored = true
					connection?.videoOrientation = .portrait
					dataOutput.setSampleBufferDelegate(self, queue: segmentationQueue)
					self.videoDataOutput = dataOutput
					print("✅ Video data output added for real-time person segmentation")
				} else {
					print("❌ Cannot add video data output to session")
				}
				
				// Automatically start the session after setup
            DispatchQueue.main.async {
                self.startSession()
            }
            
        } catch {
            print("❌ Failed to setup camera: \(error)")
            showError("Failed to setup camera: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Haptics
    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            hapticsEngine = try CHHapticEngine()
            hapticsEngine?.isAutoShutdownEnabled = true
            hapticsEngine?.resetHandler = { [weak self] in
                try? self?.hapticsEngine?.start()
            }
            try hapticsEngine?.start()
        } catch {
            print("❌ Haptics engine error: \(error)")
        }
    }
    
    func startContinuousHaptics(duration: TimeInterval) {
        // Clear any previous
        stopHaptics()
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            do {
                let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6)
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [intensity, sharpness], relativeTime: 0, duration: duration)
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                try hapticsEngine?.start()
                hapticPlayer = try hapticsEngine?.makeAdvancedPlayer(with: pattern)
                try hapticPlayer?.start(atTime: 0)
            } catch {
                print("❌ Failed to play continuous haptics: \(error)")
            }
        } else {
            // Fallback: repeated medium impacts
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            let interval: TimeInterval = 0.05
            var elapsed: TimeInterval = 0
            hapticTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] t in
                generator.impactOccurred()
                elapsed += interval
                if elapsed >= duration { self?.stopHaptics() }
            }
        }
    }
    
    func stopHaptics() {
		try? hapticPlayer?.stop(atTime: 0)
		hapticPlayer = nil
		hapticTimer?.invalidate()
		hapticTimer = nil
	}
    
    func startSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if !self.captureSession.isRunning {
                print("🤳 Starting selfie camera session...")
                self.captureSession.startRunning()
                
                DispatchQueue.main.async {
                    self.isSessionRunning = self.captureSession.isRunning
                    print("🤳 Selfie camera session running: \(self.isSessionRunning)")
                }
            }
        }
    }
    
    func stopSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                
                DispatchQueue.main.async {
                    self.isSessionRunning = false
                }
            }
        }
    }
    
    func startRecording(completion: @escaping (Bool) -> Void) {
        guard let videoOutput = videoOutput else {
            completion(false)
            return
        }
        
        recordingCompletion = completion
        
        // Create temporary file URL
        let tempDir = FileManager.default.temporaryDirectory
        currentVideoURL = tempDir.appendingPathComponent("selfie_\(UUID().uuidString).mov")
        
        guard let videoURL = currentVideoURL else {
            completion(false)
            return
        }
        
        // Remove existing file if it exists
        try? FileManager.default.removeItem(at: videoURL)
        
        videoOutput.startRecording(to: videoURL, recordingDelegate: self)
        completion(true)
    }
    
    func stopRecording(completion: @escaping (URL?) -> Void) {
        stopRecordingCompletion = completion
        videoOutput?.stopRecording()
    }
    
    private func showError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            self.showError = true
        }
    }
}

// MARK: - Recording Delegate
extension SelfieCameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("📹 Started recording selfie video to: \(fileURL)")
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("❌ Recording error: \(error)")
            DispatchQueue.main.async {
                self.stopRecordingCompletion?(nil)
            }
        } else {
            print("✅ Finished recording selfie video: \(outputFileURL)")
            DispatchQueue.main.async {
                self.stopRecordingCompletion?(outputFileURL)
            }
        }
    }
}

// MARK: - Real-time Segmentation Delegate
extension SelfieCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
	func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
		let now = CFAbsoluteTimeGetCurrent()
		if now - lastSegmentationTime < minSegmentationInterval { return }
		lastSegmentationTime = now
		guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

		let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let handler = VNImageRequestHandler(ciImage: ciImage, orientation: .up, options: [:])
        if #available(iOS 17.0, *) {
            do {
                try handler.perform([foregroundRequest])
                guard let obs = foregroundRequest.results?.first as? VNInstanceMaskObservation else { return }
                // Generate mask covering foreground instances. Use instance 1 as primary.
                let maskPB = try obs.generateMaskedImage(ofInstances: [1], from: handler, croppedToInstancesExtent: false)
                let maskCI = CIImage(cvPixelBuffer: maskPB).oriented(.up)
                let resizedMask = maskCI.resize(aspectFillTo: ciImage.extent.size)
                let alphaMask = resizedMask.clampedToExtent()

                // Composite subject over white
                let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: ciImage.extent)
                if let blend = CIFilter(name: "CIBlendWithAlphaMask") {
                    blend.setValue(ciImage, forKey: kCIInputImageKey)
                    blend.setValue(white, forKey: kCIInputBackgroundImageKey)
                    blend.setValue(alphaMask, forKey: kCIInputMaskImageKey)
                    if let output = blend.outputImage,
                       let cg = ciContext.createCGImage(output, from: ciImage.extent) {
                        let ui = UIImage(cgImage: cg, scale: 1, orientation: .up)
                        DispatchQueue.main.async { self.processedFrame = ui }
                    }
                }
            } catch {
                // Ignore preview errors
            }
        } else {
            // iOS < 17 fallback: show raw preview
        }
	}
}

// MARK: - CIImage helpers
private extension CIImage {
	func resize(aspectFillTo target: CGSize) -> CIImage {
		let scale = max(target.width / extent.width, target.height / extent.height)
		let scaled = self.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
		let x = (scaled.extent.width - target.width) / 2
		let y = (scaled.extent.height - target.height) / 2
		return scaled.cropped(to: CGRect(x: x, y: y, width: target.width, height: target.height))
	}
}
