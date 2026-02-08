import SwiftUI
import MetalKit

/// NSViewRepresentable wrapper that bridges MTKView into SwiftUI.
/// IMPORTANT: This view has ZERO dependency on SwiftUI @State to prevent recreation.
struct MetalView: NSViewRepresentable {

    /// Flight data manager injected from ContentView for aircraft rendering.
    var flightDataManager: FlightDataManager?

    /// Callback when an aircraft is clicked (or nil when deselecting)
    var onAircraftSelected: ((SelectedAircraftInfo?) -> Void)?

    /// Callback to toggle follow mode on the renderer
    var onFollowToggle: ((Bool) -> Void)?

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
        renderer.flightDataManager = flightDataManager
        context.coordinator.renderer = renderer
        context.coordinator.onAircraftSelected = onAircraftSelected
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
        // Propagate flight data manager if it was set after initial creation
        if let fdm = flightDataManager {
            context.coordinator.renderer?.flightDataManager = fdm
        }
        // Update callbacks
        context.coordinator.onAircraftSelected = onAircraftSelected
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MTKViewDelegate {
        var renderer: Renderer?
        var onAircraftSelected: ((SelectedAircraftInfo?) -> Void)?

        override init() {
            super.init()
            NotificationCenter.default.addObserver(
                self, selector: #selector(handleFollowToggle),
                name: .toggleFollowMode, object: nil
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(handleClearSelection),
                name: .clearSelection, object: nil
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(handleCycleTheme),
                name: .cycleTheme, object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func handleFollowToggle() {
            toggleFollow()
        }

        @objc private func handleCycleTheme() {
            renderer?.themeManager.cycleTheme()
        }

        @objc private func handleClearSelection() {
            guard let renderer = renderer else { return }
            renderer.selectionManager.selectedHex = nil
            renderer.selectionManager.isFollowing = false
            renderer.camera.followTarget = nil
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            renderer?.mtkView(view, drawableSizeWillChange: size)
        }

        func draw(in view: MTKView) {
            renderer?.draw(in: view)
        }

        // MARK: - Click Handling

        @MainActor func handleClick(at point: CGPoint, in viewSize: CGSize) {
            guard let renderer = renderer else { return }
            let states = renderer.flightDataManager?.interpolatedStates(at: CACurrentMediaTime()) ?? []
            let result = renderer.selectionManager.handleClick(
                screenPoint: point, viewSize: viewSize,
                viewMatrix: renderer.camera.viewMatrix,
                projMatrix: renderer.camera.projectionMatrix,
                states: states
            )
            // Clear follow mode on any click
            renderer.selectionManager.isFollowing = false
            renderer.camera.followTarget = nil
            onAircraftSelected?(result)
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

        // MARK: - Follow Mode

        func toggleFollow() {
            guard let renderer = renderer else { return }
            renderer.selectionManager.isFollowing.toggle()
            if !renderer.selectionManager.isFollowing {
                renderer.camera.followTarget = nil
            }
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

    // Mouse click for aircraft selection
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        coordinator?.handleClick(at: point, in: bounds.size)
    }

    // Key events
    override func keyDown(with event: NSEvent) {
        guard let camera = coordinator?.renderer?.camera else { return }
        switch event.charactersIgnoringModifiers {
        case "r":
            camera.reset()
        case "a":
            camera.isAutoRotating.toggle()
        case "t":
            NotificationCenter.default.post(name: .cycleTheme, object: nil)
        default:
            super.keyDown(with: event)
        }
    }
}
