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

        // Gesture recognizers for camera control
        let magnificationGesture = NSMagnificationGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleMagnification(_:)))
        mtkView.addGestureRecognizer(magnificationGesture)

        let rotationGesture = NSRotationGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleRotation(_:)))
        mtkView.addGestureRecognizer(rotationGesture)

        let panGesture = NSPanGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.buttonMask = 0 // trackpad
        panGesture.numberOfTouchesRequired = 2
        mtkView.addGestureRecognizer(panGesture)

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

        // MARK: - Gesture Handlers

        @objc func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
            guard let camera = renderer?.camera else { return }
            camera.zoom(delta: Float(gesture.magnification) * 5.0)
            if gesture.state == .ended || gesture.state == .cancelled {
                gesture.magnification = 0
            }
        }

        @objc func handleRotation(_ gesture: NSRotationGestureRecognizer) {
            guard let camera = renderer?.camera else { return }
            camera.orbit(deltaAzimuth: -Float(gesture.rotation), deltaElevation: 0)
            gesture.rotation = 0
        }

        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard let camera = renderer?.camera else { return }
            let translation = gesture.translation(in: gesture.view)
            camera.pan(deltaX: Float(translation.x) * 0.5, deltaY: Float(translation.y) * 0.5)
            gesture.setTranslation(.zero, in: gesture.view)
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
