import SwiftUI
import UIKit
import Photos
@preconcurrency import AVFoundation
import Combine
import CoreMotion
import ImageIO
import UniformTypeIdentifiers

struct CameraMotionSnapshot: Equatable, Codable {
    var pitch: Double
    var roll: Double
    var yaw: Double

    private func degrees(_ radians: Double) -> Double {
        radians * 180 / .pi
    }

    var pitchDegrees: Double { degrees(pitch) }
    var rollDegrees: Double { degrees(roll) }
    var yawDegrees: Double { degrees(yaw) }
}

struct CameraImagePicker: View {
    var onImagePicked: (Data?) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraCaptureController()
    @State private var containerSize: CGSize = .zero
    @State private var previewResetID = UUID()
    @State private var isFinishingPhoto = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                if let confirmedImage = camera.confirmedImage {
                    capturedPreview(confirmedImage, in: proxy.size)
                } else {
                    liveCamera(in: proxy.size)
                }
            }
            .onAppear {
                containerSize = proxy.size
                relaunchCamera()
            }
            .onDisappear {
                camera.stopSession()
                camera.previewLayer = nil
                AppOrientationManager.request(.portrait)
            }
            .onChange(of: proxy.size) { _, newValue in
                containerSize = newValue
            }
        }
        .ignoresSafeArea()
        .background(
            CameraOrientationController(orientation: .landscapeRight)
                .allowsHitTesting(false)
        )
    }

    private func liveCamera(in size: CGSize) -> some View {
        let metrics = PhotoCaptureGuideLayout.metrics(in: size)
        let controlsRect = metrics.controlsRect

        return ZStack {
            CameraPreviewView(session: camera.session) { previewLayer in
                camera.previewLayer = previewLayer
                camera.configurePreviewLayer(previewLayer)
            }
            .id(previewResetID)
            .ignoresSafeArea()

            PhotoCaptureGuideOverlayView()

            ZStack {
                if controlsRect.width > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.72))
                        .frame(width: controlsRect.width)
                        .frame(maxHeight: .infinity)
                        .position(x: controlsRect.midX, y: size.height / 2)
                }

                HStack {
                    Button {
                        onImagePicked(nil)
                        AppOrientationManager.request(.portrait)
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.black.opacity(0.42), in: Circle())
                    }
                    .padding(.leading, 18)
                    .padding(.top, 20)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                HStack {
                    Spacer(minLength: 0)

                    VStack(spacing: 24) {
                        Spacer(minLength: 0)

                        motionPanel(
                            title: "实时角度",
                            snapshot: camera.liveMotionSnapshot
                        )

                        Button {
                            camera.capturePhoto(containerSize: size)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.18))
                                    .frame(width: 90, height: 90)

                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 74, height: 74)
                            }
                        }
                        .disabled(camera.isCapturing)

                        Text("请横着拍摄")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.42), in: Capsule())

                        Spacer(minLength: 0)
                    }
                    .frame(width: max(controlsRect.width, 112))
                }
            }
        }
    }

    private func capturedPreview(_ image: UIImage, in size: CGSize) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: size.width * 0.96, maxHeight: size.height * 0.74)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )

            Spacer(minLength: 20)

            motionPanel(
                title: "拍摄角度",
                snapshot: camera.capturedMotionSnapshot
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 14)

            HStack(spacing: 18) {
                Button("Retake") {
                    isFinishingPhoto = false
                    relaunchCamera()
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button("Use Photo") {
                    guard !isFinishingPhoto else { return }
                    isFinishingPhoto = true
                    let imageData = image.jpegDataWithMotionMetadata(
                        motionSnapshot: camera.capturedMotionSnapshot
                    )
                    onImagePicked(imageData)
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        AppOrientationManager.request(.portrait)
                    }
                    if let imageData {
                        camera.saveToPhotoLibrary(imageData)
                    }
                }
                .font(.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .disabled(isFinishingPhoto)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func relaunchCamera() {
        previewResetID = UUID()
        isFinishingPhoto = false
        camera.resetPreview()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            camera.startSession()
        }
    }

    @ViewBuilder
    private func motionPanel(title: String, snapshot: CameraMotionSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.82))

            if let snapshot {
                VStack(alignment: .leading, spacing: 4) {
                    motionRow(label: "Pitch", value: snapshot.pitchDegrees)
                    motionRow(label: "Roll", value: snapshot.rollDegrees)
                    motionRow(label: "Yaw", value: snapshot.yawDegrees)
                }
            } else {
                Text("读取中…")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func motionRow(label: String, value: Double) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.white.opacity(0.68))
            Text(String(format: "%.1f°", value))
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
        }
    }
}

final class CameraCaptureController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "camera.capture.session")
    private let motionManager = CMMotionManager()

    @Published var confirmedImage: UIImage?
    @Published var isCapturing = false
    @Published var liveMotionSnapshot: CameraMotionSnapshot?
    @Published var capturedMotionSnapshot: CameraMotionSnapshot?

    weak var previewLayer: AVCaptureVideoPreviewLayer?

    private var isConfigured = false
    private var pendingContainerSize: CGSize = .zero

    func startSession() {
        startMotionUpdates()
        sessionQueue.async {
            if !self.isConfigured {
                self.configureSession()
            }
            if let previewLayer = self.previewLayer {
                self.configurePreviewLayer(previewLayer)
            }
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stopSession() {
        stopMotionUpdates()
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func resetPreview() {
        DispatchQueue.main.async {
            self.confirmedImage = nil
            self.isCapturing = false
            self.capturedMotionSnapshot = nil
        }
        previewLayer = nil
    }

    func capturePhoto(containerSize: CGSize) {
        pendingContainerSize = containerSize
        capturedMotionSnapshot = liveMotionSnapshot
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        settings.photoQualityPrioritization = .speed
        if let connection = photoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(0) {
            connection.videoRotationAngle = 0
        }

        DispatchQueue.main.async {
            self.isCapturing = true
        }
        sessionQueue.async {
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func saveToPhotoLibrary(_ imageData: Data) {
        DispatchQueue.global(qos: .utility).async {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else { return }
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("jpg")
                do {
                    try imageData.write(to: tempURL, options: .atomic)
                } catch {
                    return
                }
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: tempURL)
                } completionHandler: { _, _ in
                    try? FileManager.default.removeItem(at: tempURL)
                }
            }
        }
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 15.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let attitude = motion?.attitude else { return }
            self.liveMotionSnapshot = CameraMotionSnapshot(
                pitch: attitude.pitch,
                roll: attitude.roll,
                yaw: attitude.yaw
            )
        }
    }

    private func stopMotionUpdates() {
        guard motionManager.isDeviceMotionActive else { return }
        motionManager.stopDeviceMotionUpdates()
    }

    private func configureSession() {
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else {
            session.sessionPreset = .high
        }

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            return
        }

        session.addOutput(photoOutput)
        isConfigured = true
        session.commitConfiguration()
    }

    func configurePreviewLayer(_ previewLayer: AVCaptureVideoPreviewLayer) {
        previewLayer.videoGravity = .resizeAspectFill
        if let connection = previewLayer.connection,
           connection.isVideoRotationAngleSupported(0) {
            connection.videoRotationAngle = 0
        }
    }
}

extension CameraCaptureController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard
            error == nil,
            let imageData = photo.fileDataRepresentation()
        else {
            DispatchQueue.main.async {
                self.isCapturing = false
            }
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let normalizedGuideRect = UIImage.normalizedGuideFrameRect(
                using: self.pendingContainerSize,
                previewLayer: self.previewLayer
            )

            self.sessionQueue.async {
                autoreleasepool {
                    guard let decodedImage = UIImage.downsampledUpright(
                        fromJPEGData: imageData,
                        maxPixelSize: 2200
                    ) else {
                        DispatchQueue.main.async {
                            self.isCapturing = false
                        }
                        return
                    }

                    let framedImage = decodedImage.croppedToGuideFrame(
                        normalizedRect: normalizedGuideRect
                    ).normalizedForRecognition(forceLandscape: true)

                    self.stopSession()
                    DispatchQueue.main.async {
                        self.confirmedImage = framedImage
                        self.isCapturing = false
                    }
                }
            }
        }
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    var session: AVCaptureSession
    var onLayerReady: (AVCaptureVideoPreviewLayer) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        onLayerReady(view.videoPreviewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
        uiView.videoPreviewLayer.videoGravity = .resizeAspectFill
        onLayerReady(uiView.videoPreviewLayer)
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

private struct CameraOrientationController: UIViewControllerRepresentable {
    var orientation: UIInterfaceOrientationMask

    func makeUIViewController(context: Context) -> OrientationLockViewController {
        let controller = OrientationLockViewController()
        controller.orientation = orientation
        return controller
    }

    func updateUIViewController(_ uiViewController: OrientationLockViewController, context: Context) {
        uiViewController.orientation = orientation
    }

    static func dismantleUIViewController(_ uiViewController: OrientationLockViewController, coordinator: ()) {
        uiViewController.orientation = .portrait
        uiViewController.applyOrientation()
        AppOrientationManager.request(.portrait)
    }
}

private final class OrientationLockViewController: UIViewController {
    var orientation: UIInterfaceOrientationMask = .landscapeRight {
        didSet {
            setNeedsUpdateOfSupportedInterfaceOrientations()
            applyOrientation()
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        orientation
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        orientation.preferredInterfaceOrientation
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyOrientation()
    }

    func applyOrientation() {
        AppOrientationManager.request(orientation, windowScene: view.window?.windowScene)
    }
}

private enum AppOrientationManager {
    static func request(_ mask: UIInterfaceOrientationMask, windowScene: UIWindowScene? = nil) {
        let preferred = mask.preferredInterfaceOrientation
        UIDevice.current.setValue(preferred.rawValue, forKey: "orientation")
        if let windowScene {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
            return
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
    }
}

private extension UIInterfaceOrientationMask {
    var preferredInterfaceOrientation: UIInterfaceOrientation {
        if contains(.landscapeRight) {
            return .landscapeRight
        }
        if contains(.landscapeLeft) {
            return .landscapeLeft
        }
        if contains(.portraitUpsideDown) {
            return .portraitUpsideDown
        }
        return .portrait
    }
}

private extension UIImage {
    static func downsampledUpright(fromJPEGData data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize)
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: thumbnail)
    }

    func uprightNormalized() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func jpegDataWithMotionMetadata(motionSnapshot: CameraMotionSnapshot?) -> Data? {
        guard let baseData = jpegData(compressionQuality: 0.92) else { return nil }
        guard let motionSnapshot else { return baseData }
        guard
            let source = CGImageSourceCreateWithData(baseData as CFData, nil),
            let uti = CGImageSourceGetType(source),
            let mutableData = CFDataCreateMutable(nil, 0),
            let destination = CGImageDestinationCreateWithData(mutableData, uti, 1, nil)
        else {
            return baseData
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let metadataJSON = (try? encoder.encode(motionSnapshot))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""

        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        var exif = (properties[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
        var tiff = (properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]) ?? [:]
        exif[kCGImagePropertyExifUserComment] = metadataJSON
        tiff[kCGImagePropertyTIFFImageDescription] = metadataJSON
        properties[kCGImagePropertyExifDictionary] = exif
        properties[kCGImagePropertyTIFFDictionary] = tiff

        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return baseData }
        return mutableData as Data
    }

    static func motionSnapshot(fromJPEGData data: Data) -> CameraMotionSnapshot? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return nil
        }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let metadataJSON =
            (exif?[kCGImagePropertyExifUserComment] as? String) ??
            (tiff?[kCGImagePropertyTIFFImageDescription] as? String)

        guard
            let metadataJSON,
            let data = metadataJSON.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(CameraMotionSnapshot.self, from: data)
    }

    func normalizedForRecognition(forceLandscape: Bool) -> UIImage {
        let normalized = uprightNormalized()
        guard forceLandscape, normalized.size.width < normalized.size.height else {
            return normalized
        }

        let rotatedRenderer = UIGraphicsImageRenderer(
            size: CGSize(width: normalized.size.height, height: normalized.size.width)
        )
        return rotatedRenderer.image { context in
            context.cgContext.translateBy(x: normalized.size.height / 2, y: normalized.size.width / 2)
            context.cgContext.rotate(by: .pi / 2)
            normalized.draw(
                in: CGRect(
                    x: -normalized.size.width / 2,
                    y: -normalized.size.height / 2,
                    width: normalized.size.width,
                    height: normalized.size.height
                )
            )
        }
    }

    static func normalizedGuideFrameRect(using viewSize: CGSize, previewLayer: AVCaptureVideoPreviewLayer?) -> CGRect {
        let metrics = PhotoCaptureGuideLayout.metrics(in: viewSize)
        let boardRect = metrics.boardRect
        guard boardRect.width > 0, boardRect.height > 0 else { return .null }

        if let previewLayer {
            return previewLayer.metadataOutputRectConverted(fromLayerRect: boardRect)
        } else {
            return CGRect(
                x: boardRect.minX / viewSize.width,
                y: boardRect.minY / viewSize.height,
                width: boardRect.width / viewSize.width,
                height: boardRect.height / viewSize.height
            )
        }
    }

    func croppedToGuideFrame(using viewSize: CGSize, previewLayer: AVCaptureVideoPreviewLayer?) -> UIImage {
        croppedToGuideFrame(normalizedRect: Self.normalizedGuideFrameRect(using: viewSize, previewLayer: previewLayer))
    }

    func croppedToGuideFrame(normalizedRect: CGRect) -> UIImage {
        guard let cgImage else { return self }
        guard !normalizedRect.isNull, normalizedRect.width > 0, normalizedRect.height > 0 else { return self }

        let cropRect = CGRect(
            x: normalizedRect.minX * CGFloat(cgImage.width),
            y: normalizedRect.minY * CGFloat(cgImage.height),
            width: normalizedRect.width * CGFloat(cgImage.width),
            height: normalizedRect.height * CGFloat(cgImage.height)
        ).integral

        guard
            cropRect.minX >= 0,
            cropRect.minY >= 0,
            cropRect.maxX <= CGFloat(cgImage.width),
            cropRect.maxY <= CGFloat(cgImage.height),
            let cropped = cgImage.cropping(to: cropRect)
        else {
            return self
        }
        return UIImage(cgImage: cropped)
    }
}
