import AVFoundation
import CoreImage
import Foundation

enum CameraError: LocalizedError {
    case permissionDenied
    case noCameraAvailable
    case cannotAddInput
    case cannotAddOutput
    case deviceConfiguration(Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera access was denied. Enable it in Settings › Privacy › Camera."
        case .noCameraAvailable:
            return "No rear camera is available on this device."
        case .cannotAddInput:
            return "The camera input could not be added to the capture session."
        case .cannotAddOutput:
            return "The video output could not be added to the capture session."
        case .deviceConfiguration(let error):
            return "Camera configuration failed: \(error.localizedDescription)"
        }
    }
}

/// Owns the `AVCaptureSession` and delivers raw rear-camera frames as `CIImage`s.
///
/// Threading model:
/// - `start()` / `stop()` can be called from any context; all session mutation happens on `sessionQueue`.
/// - `onFrame` fires on a dedicated high-priority video queue. Do the minimum there
///   (build the filtered `CIImage` graph) and hand the result to the renderer.
/// - `onInterruption` fires on the main queue.
final class CameraManager: NSObject {

    struct Configuration {
        var preset: AVCaptureSession.Preset = .hd1920x1080
        var targetFrameRate: Int32 = 30
        /// Rotation applied to the video connection so buffers arrive upright in portrait.
        var rotationAngle: CGFloat = 90
    }

    let configuration: Configuration

    /// Called on the video queue for every captured frame.
    var onFrame: (@Sendable (CIImage) -> Void)?
    /// Called on the main queue when the session is interrupted (`String` reason) or resumes (`nil`).
    var onInterruption: (@Sendable (String?) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "MonsterScanner.camera.session", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "MonsterScanner.camera.video", qos: .userInteractive)
    private let videoOutput = AVCaptureVideoDataOutput()
    private var isConfigured = false
    private var frameCount = 0
    private var observers: [NSObjectProtocol] = []

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        super.init()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Lifecycle

    /// Requests permission, configures the session once, and starts it. Safe to call repeatedly.
    func start() async throws {
        guard await Self.ensurePermission() else {
            throw CameraError.permissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                do {
                    if !isConfigured {
                        try configureSession()
                        isConfigured = true
                    }
                    if !session.isRunning {
                        session.startRunning()
                        Log.camera.info("Capture session started")
                    }
                    continuation.resume()
                } catch {
                    Log.camera.error("Failed to start capture session: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            guard session.isRunning else { return }
            session.stopRunning()
            Log.camera.info("Capture session stopped")
        }
    }

    // MARK: - Permission

    private static func ensurePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            Log.camera.info("Camera permission \(granted ? "granted" : "denied", privacy: .public)")
            return granted
        default:
            Log.camera.error("Camera permission previously denied or restricted")
            return false
        }
    }

    // MARK: - Configuration (sessionQueue only)

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = session.canSetSessionPreset(configuration.preset) ? configuration.preset : .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.noCameraAvailable
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CameraError.deviceConfiguration(error)
        }
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(configuration.rotationAngle) {
                connection.videoRotationAngle = configuration.rotationAngle
            } else {
                Log.camera.warning("Rotation angle \(Double(self.configuration.rotationAngle)) unsupported; frames arrive in sensor orientation")
            }
        }

        configureFrameRate(on: device)
        installObservers()

        Log.camera.info("Session configured: \(device.localizedName, privacy: .public), preset \(self.session.sessionPreset.rawValue, privacy: .public)")
    }

    private func configureFrameRate(on device: AVCaptureDevice) {
        let target = Double(configuration.targetFrameRate)
        let supported = device.activeFormat.videoSupportedFrameRateRanges.contains {
            $0.minFrameRate <= target && target <= $0.maxFrameRate
        }
        guard supported else {
            Log.camera.warning("Active format does not support \(target) fps; leaving default frame rate")
            return
        }
        do {
            try device.lockForConfiguration()
            let duration = CMTime(value: 1, timescale: configuration.targetFrameRate)
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
            Log.camera.debug("Frame rate locked to \(target) fps")
        } catch {
            Log.camera.warning("Could not lock device for frame-rate configuration: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        observers.append(center.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            let description = error?.localizedDescription ?? "unknown"
            Log.camera.error("Capture runtime error: \(description, privacy: .public)")
            self?.onInterruption?("Camera error: \(description)")

            // Media services resets are recoverable by simply restarting the session.
            if error?.code == AVError.mediaServicesWereReset.rawValue {
                self?.sessionQueue.async { self?.session.startRunning() }
            }
        })

        observers.append(center.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int ?? -1
            Log.camera.notice("Capture session interrupted (reason \(reason))")
            self?.onInterruption?("Camera interrupted")
        })

        observers.append(center.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session, queue: .main) { [weak self] _ in
            Log.camera.notice("Capture session interruption ended")
            self?.onInterruption?(nil)
        })
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate (videoQueue)

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            Log.camera.error("Received a sample buffer without an image buffer")
            return
        }
        frameCount += 1
        if frameCount % 300 == 0 {
            Log.camera.debug("Delivered \(self.frameCount) frames")
        }
        onFrame?(CIImage(cvPixelBuffer: pixelBuffer))
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        Log.camera.debug("Dropped a late video frame")
    }
}
