import CoreMotion
import Foundation

/// Where the rear camera is pointing.
struct Orientation: Equatable, Sendable {
    /// Compass azimuth of the camera's view direction: 0 = magnetic north, clockwise, in [0, 360).
    var heading: Double
    /// Elevation of the view direction in degrees: 0 = level, +90 = straight up, -90 = straight down.
    var pitch: Double
    var timestamp: TimeInterval
}

struct MotionConfiguration {
    var updateInterval: TimeInterval = 1.0 / 30.0
    var referenceFrame: CMAttitudeReferenceFrame = .xMagneticNorthZVertical
    /// Exponential smoothing applied to heading and pitch. 0 = raw, 0.9 = very laggy. Tames compass jitter.
    var smoothing: Double = 0.35
    /// Which rotation-matrix convention to use when deriving the camera axis. See `cameraForward(from:)`.
    var useColumnConvention = false

    static let `default` = MotionConfiguration()
}

/// Wraps `CMMotionManager` and converts device attitude into a camera heading + pitch.
final class MotionTracker {

    enum Status: Equatable {
        case idle
        case running(referenceFrame: String)
        case unavailable(String)
    }

    let configuration: MotionConfiguration

    /// Delivered on the main queue at `configuration.updateInterval`.
    var onUpdate: (@Sendable (Orientation) -> Void)?

    /// Main-thread only.
    private(set) var status: Status = .idle

    private let manager = CMMotionManager()
    private let queue: OperationQueue
    private var smoothed: Orientation?
    private var lastDiagnosticLog: TimeInterval = 0

    init(configuration: MotionConfiguration = .default) {
        self.configuration = configuration
        queue = OperationQueue()
        queue.name = "MonsterScanner.motion"
        queue.maxConcurrentOperationCount = 1
    }

    // MARK: - Lifecycle

    func start() {
        guard manager.isDeviceMotionAvailable else {
            let reason = "Device motion is not available on this device."
            status = .unavailable(reason)
            Log.motion.error("\(reason, privacy: .public)")
            return
        }
        guard !manager.isDeviceMotionActive else { return }

        var frame = configuration.referenceFrame
        if !CMMotionManager.availableAttitudeReferenceFrames().contains(frame) {
            Log.motion.warning("Reference frame \(frame.rawValue) unavailable; using arbitrary-X fallback (heading is relative, not magnetic)")
            frame = .xArbitraryCorrectedZVertical
        }

        manager.deviceMotionUpdateInterval = configuration.updateInterval
        manager.showsDeviceMovementDisplay = true  // lets iOS show its calibration UI if the compass needs it
        manager.startDeviceMotionUpdates(using: frame, to: queue) { [weak self] motion, error in
            guard let self else { return }
            if let error {
                Log.motion.error("Device motion error: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard let motion else { return }
            let orientation = self.process(motion)
            DispatchQueue.main.async { self.onUpdate?(orientation) }
        }

        let frameName = Self.describe(frame)
        status = .running(referenceFrame: frameName)
        Log.motion.info("Device motion started using \(frameName, privacy: .public)")
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        queue.addOperation { [weak self] in self?.smoothed = nil }
        status = .idle
        Log.motion.info("Device motion stopped")
    }

    // MARK: - Processing (motion queue)

    private func process(_ motion: CMDeviceMotion) -> Orientation {
        let forward = Self.cameraForward(from: motion.attitude.rotationMatrix,
                                         columnConvention: configuration.useColumnConvention)

        // Reference frame: +X = magnetic north, +Z = up, therefore +Y = west.
        // Azimuth is clockwise from north, so east is -Y.
        let rawHeading = Angles.normalized(Angles.degrees(atan2(-forward.y, forward.x)))
        let rawPitch = Angles.degrees(asin(max(-1, min(1, forward.z))))

        let result: Orientation
        if let previous = smoothed, configuration.smoothing > 0 {
            let alpha = 1 - configuration.smoothing
            let headingStep = Angles.signedDelta(from: previous.heading, to: rawHeading) * alpha
            result = Orientation(
                heading: Angles.normalized(previous.heading + headingStep),
                pitch: previous.pitch + (rawPitch - previous.pitch) * alpha,
                timestamp: motion.timestamp
            )
        } else {
            result = Orientation(heading: rawHeading, pitch: rawPitch, timestamp: motion.timestamp)
        }
        smoothed = result

        if motion.timestamp - lastDiagnosticLog > 5 {
            lastDiagnosticLog = motion.timestamp
            Log.motion.debug("heading \(result.heading, format: .fixed(precision: 1))° pitch \(result.pitch, format: .fixed(precision: 1))° | CM heading \(motion.heading, format: .fixed(precision: 1))° | mag accuracy \(motion.magneticField.accuracy.rawValue)")
        }
        return result
    }

    /// The direction the rear camera looks, expressed in the attitude reference frame.
    ///
    /// Core Motion's device frame has +X to the right, +Y toward the top edge and +Z out of the
    /// screen, so the rear camera looks along −Z. `rotationMatrix` maps reference-frame vectors
    /// into the device frame (it is directly usable as a view matrix, as in Apple's pARk sample),
    /// so device −Z expressed in reference coordinates is the negated third *row*.
    ///
    /// This is the single place that assumption lives. If the arrow ever points mirror-image to
    /// reality on a device, set `MotionConfiguration.useColumnConvention = true`.
    static func cameraForward(from m: CMRotationMatrix, columnConvention: Bool) -> SIMD3<Double> {
        columnConvention
            ? SIMD3(-m.m13, -m.m23, -m.m33)
            : SIMD3(-m.m31, -m.m32, -m.m33)
    }

    private static func describe(_ frame: CMAttitudeReferenceFrame) -> String {
        switch frame {
        case .xMagneticNorthZVertical: return "xMagneticNorthZVertical"
        case .xTrueNorthZVertical: return "xTrueNorthZVertical"
        case .xArbitraryCorrectedZVertical: return "xArbitraryCorrectedZVertical"
        case .xArbitraryZVertical: return "xArbitraryZVertical"
        default: return "frame(\(frame.rawValue))"
        }
    }
}
