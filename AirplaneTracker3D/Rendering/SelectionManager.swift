import simd
import Foundation

// MARK: - SelectionManager

/// Handles ray-sphere click picking for aircraft selection,
/// tracks selection state, and supports follow-camera mode.
final class SelectionManager {

    // MARK: - Properties

    /// Currently selected aircraft hex (nil = nothing selected)
    var selectedHex: String? = nil

    /// Whether the camera should follow the selected aircraft
    var isFollowing: Bool = false

    // MARK: - Click Handling

    /// Process a mouse click and test against all aircraft positions.
    /// Returns SelectedAircraftInfo if an aircraft was hit, nil if deselecting.
    func handleClick(
        screenPoint: CGPoint,
        viewSize: CGSize,
        viewMatrix: simd_float4x4,
        projMatrix: simd_float4x4,
        states: [InterpolatedAircraftState]
    ) -> SelectedAircraftInfo? {
        // Convert screen point to NDC
        let ndcX = Float(screenPoint.x / viewSize.width) * 2.0 - 1.0
        let ndcY = 1.0 - Float(screenPoint.y / viewSize.height) * 2.0

        // Compute inverse view-projection matrix
        let vpMatrix = projMatrix * viewMatrix
        let invVP = vpMatrix.inverse

        // Unproject near and far points
        let nearClip = SIMD4<Float>(ndcX, ndcY, 0, 1)
        let farClip  = SIMD4<Float>(ndcX, ndcY, 1, 1)

        var nearWorld = invVP * nearClip
        var farWorld  = invVP * farClip

        // Perspective divide
        nearWorld /= nearWorld.w
        farWorld  /= farWorld.w

        let rayOrigin = SIMD3<Float>(nearWorld.x, nearWorld.y, nearWorld.z)
        let rayDir = simd_normalize(
            SIMD3<Float>(farWorld.x, farWorld.y, farWorld.z) - rayOrigin
        )

        // Test each aircraft
        var closestT: Float = Float.greatestFiniteMagnitude
        var closestState: InterpolatedAircraftState?

        for state in states {
            if let t = raySphereIntersect(
                origin: rayOrigin, dir: rayDir,
                center: state.position, radius: 3.0
            ) {
                if t < closestT {
                    closestT = t
                    closestState = state
                }
            }
        }

        if let state = closestState {
            selectedHex = state.hex
            isFollowing = false // Reset follow on new selection
            return SelectedAircraftInfo(
                id: state.hex,
                hex: state.hex,
                callsign: state.callsign,
                altitude: state.altitude,
                groundSpeed: state.groundSpeed,
                heading: state.heading * 180.0 / .pi, // Convert back to degrees
                verticalRate: state.verticalRate,
                squawk: state.squawk,
                lat: state.lat,
                lon: state.lon,
                position: state.position
            )
        } else {
            // Click on empty space: deselect
            selectedHex = nil
            isFollowing = false
            return nil
        }
    }

    // MARK: - Follow Camera Support

    /// Returns the current world-space position of the selected aircraft, if any.
    func selectedPosition(from states: [InterpolatedAircraftState]) -> SIMD3<Float>? {
        guard let hex = selectedHex else { return nil }
        return states.first(where: { $0.hex == hex })?.position
    }

    // MARK: - Ray-Sphere Intersection

    private func raySphereIntersect(
        origin: SIMD3<Float>, dir: SIMD3<Float>,
        center: SIMD3<Float>, radius: Float
    ) -> Float? {
        let oc = origin - center
        let b = simd_dot(oc, dir)
        let c = simd_dot(oc, oc) - radius * radius
        let discriminant = b * b - c
        guard discriminant >= 0 else { return nil }
        let t = -b - sqrt(discriminant)
        return t > 0 ? t : nil
    }
}
