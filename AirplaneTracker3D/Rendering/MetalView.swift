import SwiftUI
import MetalKit

/// NSViewRepresentable wrapper that bridges MTKView into SwiftUI.
/// IMPORTANT: This view has ZERO dependency on SwiftUI @State to prevent recreation.
struct MetalView: NSViewRepresentable {

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MetalMTKView()

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        mtkView.device = device
        mtkView.preferredFramesPerSecond = 60
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0.529, green: 0.808, blue: 0.922, alpha: 1.0)

        // 4x MSAA (REND-10)
        mtkView.sampleCount = 4

        // Enable layer backing for proper rendering
        mtkView.layer?.isOpaque = true

        // Create renderer and set delegate
        let renderer = Renderer(metalView: mtkView)
        context.coordinator.renderer = renderer
        mtkView.delegate = context.coordinator
        mtkView.coordinator = context.coordinator

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // No SwiftUI state drives updates -- Metal renders independently
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MTKViewDelegate {
        var renderer: Renderer?

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            renderer?.mtkView(view, drawableSizeWillChange: size)
        }

        func draw(in view: MTKView) {
            renderer?.draw(in: view)
        }
    }
}

// MARK: - Custom MTKView Subclass for Input Handling

class MetalMTKView: MTKView {

    weak var coordinator: MetalView.Coordinator?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // Scroll wheel for orbit
    override func scrollWheel(with event: NSEvent) {
        guard let camera = coordinator?.renderer?.camera else { return }
        let sensitivity: Float = 0.005
        camera.orbit(deltaAzimuth: Float(event.scrollingDeltaX) * sensitivity,
                     deltaElevation: Float(event.scrollingDeltaY) * sensitivity)
    }

    // Key events
    override func keyDown(with event: NSEvent) {
        guard let camera = coordinator?.renderer?.camera else { return }
        switch event.charactersIgnoringModifiers {
        case "r":
            camera.reset()
        case "a":
            camera.isAutoRotating.toggle()
        default:
            super.keyDown(with: event)
        }
    }
}
