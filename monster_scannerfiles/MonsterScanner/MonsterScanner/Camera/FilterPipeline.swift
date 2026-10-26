import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Every knob of the "scary" look lives here. Tweak values, or build presets, without touching the pipeline.
struct FilterConfiguration: Equatable {
    // Tone
    var saturation: Float = 0.08
    var contrast: Float = 1.3
    var brightness: Float = -0.03
    /// Per-channel gain applied after desaturation. (0.42, 1.0, 0.52) ≈ phosphor-green night vision.
    var tint: SIMD3<Float> = [0.42, 1.0, 0.52]

    // Vignette
    var vignetteIntensity: Float = 0.8
    /// Vignette radius as a fraction of the frame's half-diagonal.
    var vignetteRadiusScale: Float = 0.9
    var vignetteFalloff: Float = 0.6

    // Film grain
    var grainOpacity: Float = 0.035
    /// Scale of the noise texture in pixels (>1 = coarser grain).
    var grainScale: CGFloat = 1.0

    // Scanlines
    var scanlineOpacity: Float = 0.1
    /// Height in pixels of one dark + one clear line pair.
    var scanlineSpacing: CGFloat = 4

    // Flicker
    /// Probability per frame that a flicker starts (0.015 ≈ one every ~2 s at 30 fps).
    var flickerProbability: Double = 0.015
    var flickerFrameRange: ClosedRange<Int> = 1...3
    var flickerExposureRange: ClosedRange<Float> = -1.4 ... -0.5

    static let `default` = FilterConfiguration()

    /// Useful for A/B checking the raw feed.
    static let passthrough = FilterConfiguration(
        saturation: 1, contrast: 1, brightness: 0, tint: [1, 1, 1],
        vignetteIntensity: 0, grainOpacity: 0, scanlineOpacity: 0, flickerProbability: 0
    )
}

/// Builds the real-time night-vision look as a single lazily-evaluated `CIImage` graph.
///
/// `apply(to:)` is designed to be called from the camera's video queue once per frame.
/// It only *describes* the work; the actual GPU render happens in `CameraRenderer`.
/// `configuration` may be changed from any thread.
final class FilterPipeline {

    var configuration: FilterConfiguration {
        get { lock.withLock { storedConfiguration } }
        set {
            lock.withLock { storedConfiguration = newValue }
            Log.filter.info("Filter configuration updated")
        }
    }

    private let lock = NSLock()
    private var storedConfiguration: FilterConfiguration

    // Reused filter instances (cheap; Apple's own real-time samples do the same).
    private let colorControls = CIFilter.colorControls()
    private let tintMatrix = CIFilter.colorMatrix()
    private let vignette = CIFilter.vignetteEffect()
    private let grainMatrix = CIFilter.colorMatrix()
    private let exposure = CIFilter.exposureAdjust()

    /// Infinite-extent random noise; translated by a random offset each frame so grain crawls.
    private let noiseSource: CIImage

    private struct ScanlineKey: Equatable {
        var extent: CGRect
        var spacing: CGFloat
        var opacity: Float
    }
    private var cachedScanlines: (key: ScanlineKey, image: CIImage)?

    // Flicker state — touched only from the frame queue.
    private var flickerFramesRemaining = 0
    private var flickerExposure: Float = 0
    private var rng = SystemRandomNumberGenerator()

    init(configuration: FilterConfiguration = .default) {
        storedConfiguration = configuration
        noiseSource = CIFilter.randomGenerator().outputImage ?? CIImage.empty()
        Log.filter.info("Filter pipeline initialised")
    }

    // MARK: - Entry point

    func apply(to input: CIImage) -> CIImage {
        let config = configuration
        let extent = input.extent
        guard !extent.isEmpty, !extent.isInfinite else { return input }

        var image = input
        image = applyTone(to: image, config: config)
        image = applyVignette(to: image, extent: extent, config: config)
        image = applyGrain(to: image, extent: extent, config: config)
        image = applyScanlines(to: image, extent: extent, config: config)
        image = applyFlicker(to: image, config: config)
        return image.cropped(to: extent)
    }

    // MARK: - Stages

    private func applyTone(to image: CIImage, config: FilterConfiguration) -> CIImage {
        colorControls.inputImage = image
        colorControls.saturation = config.saturation
        colorControls.contrast = config.contrast
        colorControls.brightness = config.brightness
        guard let toned = colorControls.outputImage else { return image }

        tintMatrix.inputImage = toned
        tintMatrix.rVector = CIVector(x: CGFloat(config.tint.x), y: 0, z: 0, w: 0)
        tintMatrix.gVector = CIVector(x: 0, y: CGFloat(config.tint.y), z: 0, w: 0)
        tintMatrix.bVector = CIVector(x: 0, y: 0, z: CGFloat(config.tint.z), w: 0)
        tintMatrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        tintMatrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        return tintMatrix.outputImage ?? toned
    }

    private func applyVignette(to image: CIImage, extent: CGRect, config: FilterConfiguration) -> CIImage {
        guard config.vignetteIntensity > 0 else { return image }
        vignette.inputImage = image
        vignette.center = CGPoint(x: extent.midX, y: extent.midY)
        vignette.radius = Float(hypot(extent.width, extent.height) / 2) * config.vignetteRadiusScale
        vignette.intensity = config.vignetteIntensity
        vignette.falloff = config.vignetteFalloff
        return vignette.outputImage?.cropped(to: extent) ?? image
    }

    private func applyGrain(to image: CIImage, extent: CGRect, config: FilterConfiguration) -> CIImage {
        guard config.grainOpacity > 0 else { return image }
        let offsetX = CGFloat.random(in: 0..<2048, using: &rng)
        let offsetY = CGFloat.random(in: 0..<2048, using: &rng)
        let noise = noiseSource
            .transformed(by: CGAffineTransform(scaleX: config.grainScale, y: config.grainScale))
            .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
            .cropped(to: extent)

        // Collapse the RGBA noise to grey (green channel) with a constant alpha.
        grainMatrix.inputImage = noise
        grainMatrix.rVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        grainMatrix.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        grainMatrix.bVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        grainMatrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        grainMatrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(config.grainOpacity))
        guard let grain = grainMatrix.outputImage else { return image }
        return grain.composited(over: image)
    }

    private func applyScanlines(to image: CIImage, extent: CGRect, config: FilterConfiguration) -> CIImage {
        guard config.scanlineOpacity > 0, let scanlines = scanlines(for: extent, config: config) else { return image }
        return scanlines.composited(over: image)
    }

    private func scanlines(for extent: CGRect, config: FilterConfiguration) -> CIImage? {
        let key = ScanlineKey(extent: extent, spacing: config.scanlineSpacing, opacity: config.scanlineOpacity)
        if let cached = cachedScanlines, cached.key == key {
            return cached.image
        }

        let stripes = CIFilter.stripesGenerator()
        stripes.center = .zero
        stripes.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: CGFloat(config.scanlineOpacity))
        stripes.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        stripes.width = Float(config.scanlineSpacing / 2)
        stripes.sharpness = 0.9
        guard let vertical = stripes.outputImage else { return nil }

        // Stripes are generated along X; swapping the axes turns them into horizontal scanlines.
        let horizontal = vertical
            .transformed(by: CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0))
            .cropped(to: extent)
        cachedScanlines = (key, horizontal)
        Log.filter.debug("Rebuilt scanline overlay for extent \(extent.width)x\(extent.height)")
        return horizontal
    }

    private func applyFlicker(to image: CIImage, config: FilterConfiguration) -> CIImage {
        if flickerFramesRemaining == 0,
           config.flickerProbability > 0,
           Double.random(in: 0..<1, using: &rng) < config.flickerProbability {
            flickerFramesRemaining = Int.random(in: config.flickerFrameRange, using: &rng)
            flickerExposure = Float.random(in: config.flickerExposureRange, using: &rng)
            Log.filter.debug("Flicker: \(self.flickerFramesRemaining) frame(s) at \(Double(self.flickerExposure)) EV")
        }
        guard flickerFramesRemaining > 0 else { return image }
        flickerFramesRemaining -= 1

        exposure.inputImage = image
        exposure.ev = flickerExposure
        return exposure.outputImage ?? image
    }
}
