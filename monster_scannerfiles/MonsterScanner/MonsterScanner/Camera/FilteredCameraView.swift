import CoreImage
import MetalKit
import SwiftUI

/// Thread-safe hand-off point between the camera's video queue (producer) and the renderer (consumer).
final class FrameStore {
    private let lock = NSLock()
    private var latest: CIImage?

    func set(_ image: CIImage) {
        lock.withLock { latest = image }
    }

    func latestFrame() -> CIImage? {
        lock.withLock { latest }
    }
}

/// Full-screen Metal-backed view that draws the latest filtered frame, aspect-filled.
struct FilteredCameraView: UIViewRepresentable {
    let frameStore: FrameStore

    func makeCoordinator() -> CameraRenderer {
        CameraRenderer(frameStore: frameStore)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.delegate = context.coordinator
        view.framebufferOnly = false          // Core Image needs to write into the drawable
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 30
        view.isOpaque = true
        view.backgroundColor = .black
        view.autoResizeDrawable = true
        view.contentMode = .scaleAspectFill
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}

/// Renders `CIImage`s into an `MTKView` using a Metal-backed `CIContext`.
final class CameraRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let context: CIContext
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let frameStore: FrameStore
    private var renderedFrames = 0

    init(frameStore: FrameStore) {
        self.frameStore = frameStore
        if let device = MTLCreateSystemDefaultDevice() {
            self.device = device
            commandQueue = device.makeCommandQueue()
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false, .name: "MonsterScanner"])
            Log.renderer.info("Metal renderer ready on \(device.name, privacy: .public)")
        } else {
            device = nil
            commandQueue = nil
            context = CIContext()
            Log.renderer.error("No Metal device available; preview will not render")
        }
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        Log.renderer.debug("Drawable size changed to \(size.width)x\(size.height)")
    }

    func draw(in view: MTKView) {
        guard let image = frameStore.latestFrame(),
              let drawable = view.currentDrawable,
              let commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let drawableSize = view.drawableSize
        guard drawableSize.width > 0, drawableSize.height > 0,
              image.extent.width > 0, image.extent.height > 0 else { return }

        // Aspect-fill: scale so the image covers the drawable, then crop the centre.
        let scale = max(drawableSize.width / image.extent.width, drawableSize.height / image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let sourceRect = CGRect(
            x: scaled.extent.midX - drawableSize.width / 2,
            y: scaled.extent.midY - drawableSize.height / 2,
            width: drawableSize.width,
            height: drawableSize.height
        )

        let destination = CIRenderDestination(
            width: Int(drawableSize.width),
            height: Int(drawableSize.height),
            pixelFormat: view.colorPixelFormat,
            commandBuffer: commandBuffer
        ) { drawable.texture }
        destination.colorSpace = colorSpace

        do {
            try context.startTask(toRender: scaled, from: sourceRect, to: destination, at: .zero)
        } catch {
            Log.renderer.error("Render task failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()

        renderedFrames += 1
        if renderedFrames % 300 == 0 {
            Log.renderer.debug("Rendered \(self.renderedFrames) frames")
        }
    }
}
