import simd
import Foundation

/// Smoothly animates the OrbitCamera from its current position to a target world position.
/// Uses smoothstep ease-in-out interpolation over a configurable duration.
/// FlyToAnimator does NOT own the camera -- it receives the camera reference and mutates
/// its target and distance properties each frame.
final class FlyToAnimator {

    // MARK: - Properties

    /// Whether an animation is currently in progress
    private(set) var isAnimating: Bool = false

    /// Start camera target (captured when animation begins)
    private var startTarget: SIMD3<Float> = .zero

    /// End camera target (world position to fly to)
    private var endTarget: SIMD3<Float> = .zero

    /// Start camera distance (captured when animation begins)
    private var startDistance: Float = 0

    /// End camera distance (zoom in on arrival)
    private var endDistance: Float = 0

    /// Elapsed time since animation started
    private var elapsed: Float = 0

    /// Total animation duration in seconds
    var duration: Float = 2.0

    // MARK: - Animation Control

    /// Begin a fly-to animation from the camera's current state to the given world position.
    /// - Parameters:
    ///   - camera: The OrbitCamera to animate (start state is captured from current values)
    ///   - worldPosition: The destination world-space position to fly to
    func startFlyTo(from camera: OrbitCamera, to worldPosition: SIMD3<Float>) {
        startTarget = camera.target
        endTarget = worldPosition
        startDistance = camera.distance
        endDistance = min(camera.distance, 80)
        elapsed = 0
        isAnimating = true
    }

    /// Update the animation, advancing the camera toward the target.
    /// Call once per frame from the render loop.
    /// - Parameters:
    ///   - camera: The OrbitCamera to mutate
    ///   - deltaTime: Time since last frame in seconds
    func update(camera: OrbitCamera, deltaTime: Float) {
        guard isAnimating else { return }

        elapsed += deltaTime
        let t = min(elapsed / duration, 1.0)

        // Smoothstep ease-in-out: t * t * (3.0 - 2.0 * t)
        let smooth = t * t * (3.0 - 2.0 * t)

        // Lerp target and distance
        camera.target = startTarget + (endTarget - startTarget) * smooth
        camera.distance = startDistance + (endDistance - startDistance) * smooth

        if t >= 1.0 {
            isAnimating = false
        }
    }

    /// Cancel any in-progress animation.
    func cancel() {
        isAnimating = false
    }
}
