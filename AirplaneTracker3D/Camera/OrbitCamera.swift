import simd
import Foundation

/// Orbital camera that revolves around a target point using spherical coordinates.
final class OrbitCamera {

    // MARK: - Properties

    /// Point the camera looks at
    var target: SIMD3<Float> = .zero

    /// Distance from target (radius of the orbit sphere)
    var distance: Float = 200 {
        didSet { distance = distance.clamped(to: 10...1000) }
    }

    /// Horizontal angle in radians
    var azimuth: Float = 0

    /// Vertical angle in radians (clamped to prevent gimbal lock)
    var elevation: Float = 0.5 {
        didSet { elevation = elevation.clamped(to: 0.05...(Float.pi / 2 - 0.05)) }
    }

    /// Field of view in radians
    var fov: Float = Float(45).degreesToRadians

    /// Near clipping plane
    var nearPlane: Float = 0.1

    /// Far clipping plane
    var farPlane: Float = 5000.0

    /// Viewport aspect ratio (updated by renderer on resize)
    var aspectRatio: Float = 1.0

    // MARK: - Auto-Rotate

    var isAutoRotating: Bool = false
    var autoRotateSpeed: Float = 0.5 // radians per second

    // MARK: - Follow Target

    /// When set, camera smoothly tracks this point
    var followTarget: SIMD3<Float>? = nil
    /// Exponential decay factor for follow smoothing
    let followSmoothness: Float = 0.08

    // MARK: - Computed Properties

    /// Camera position in world space from spherical coordinates
    var position: SIMD3<Float> {
        let x = target.x + distance * cos(elevation) * sin(azimuth)
        let y = target.y + distance * sin(elevation)
        let z = target.z + distance * cos(elevation) * cos(azimuth)
        return SIMD3<Float>(x, y, z)
    }

    /// View matrix (world-to-camera transform)
    var viewMatrix: simd_float4x4 {
        return OrbitCamera.lookAt(eye: position, center: target, up: SIMD3<Float>(0, 1, 0))
    }

    /// Projection matrix using Metal NDC depth [0, 1]
    var projectionMatrix: simd_float4x4 {
        return OrbitCamera.perspectiveMetal(fovY: fov, aspectRatio: aspectRatio, nearZ: nearPlane, farZ: farPlane)
    }

    // MARK: - Camera Controls

    /// Orbit by adding deltas to azimuth and elevation
    func orbit(deltaAzimuth: Float, deltaElevation: Float) {
        azimuth += deltaAzimuth
        elevation += deltaElevation
    }

    /// Zoom by scaling distance
    func zoom(delta: Float) {
        distance *= (1.0 - delta * 0.01)
    }

    /// Pan the target in camera-local right/up directions
    func pan(deltaX: Float, deltaY: Float) {
        let forward = simd_normalize(target - position)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(forward, worldUp))
        let up = simd_normalize(simd_cross(right, forward))

        let scale = distance * 0.002
        target += right * (-deltaX * scale) + up * (deltaY * scale)
    }

    /// Reset camera to default position
    func reset() {
        target = .zero
        distance = 200
        azimuth = 0
        elevation = 0.5
    }

    /// Update per frame (follow target + auto-rotation)
    func update(deltaTime: Float) {
        // Follow target: smooth lerp toward followed aircraft
        if let ft = followTarget {
            let lerpFactor = 1.0 - pow(1.0 - followSmoothness, deltaTime * 60.0)
            target = target + (ft - target) * lerpFactor
        }

        if isAutoRotating {
            azimuth += autoRotateSpeed * deltaTime
        }
    }

    // MARK: - Matrix Math

    /// Build a look-at view matrix
    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = simd_normalize(center - eye)
        let s = simd_normalize(simd_cross(f, up))
        let u = simd_cross(s, f)

        var result = matrix_identity_float4x4
        result.columns.0 = SIMD4<Float>(s.x, u.x, -f.x, 0)
        result.columns.1 = SIMD4<Float>(s.y, u.y, -f.y, 0)
        result.columns.2 = SIMD4<Float>(s.z, u.z, -f.z, 0)
        result.columns.3 = SIMD4<Float>(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
        return result
    }

    /// Build a perspective projection matrix for Metal NDC depth [0, 1]
    static func perspectiveMetal(fovY: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
        let yScale = 1.0 / tan(fovY * 0.5)
        let xScale = yScale / aspectRatio
        let zRange = farZ - nearZ

        var result = simd_float4x4(0)
        result.columns.0.x = xScale
        result.columns.1.y = yScale
        // Metal NDC depth [0, 1]: map near -> 0, far -> 1
        result.columns.2.z = farZ / zRange
        result.columns.2.w = 1.0
        result.columns.3.z = -(nearZ * farZ) / zRange
        return result
    }
}

// MARK: - Helpers

private extension Float {
    var degreesToRadians: Float { self * .pi / 180.0 }

    func clamped(to range: ClosedRange<Float>) -> Float {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
