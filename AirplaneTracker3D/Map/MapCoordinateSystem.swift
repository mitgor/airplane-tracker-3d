import Foundation
import simd

/// Converts between geographic coordinates (latitude/longitude) and Metal world-space (X, Y, Z).
/// Uses Mercator projection for alignment with slippy map tiles.
/// Ground plane is at Y = 0. Center lat/lon maps to world origin (0, 0, 0).
final class MapCoordinateSystem {

    // MARK: - Singleton

    static let shared = MapCoordinateSystem()

    // MARK: - Configuration

    /// Center latitude in degrees (default: Seattle area)
    let centerLat: Double = 47.6

    /// Center longitude in degrees
    let centerLon: Double = -122.3

    /// World scale: world units per degree of longitude at the equator.
    /// At zoom 10, tiles are ~0.35 degrees wide. With scale 500, a tile is ~175 world units wide.
    let worldScale: Double = 500.0

    // MARK: - Precomputed

    /// Mercator Y of center latitude (used as offset for Z mapping)
    private let centerMercatorY: Double

    private init() {
        let latRad = centerLat * .pi / 180.0
        centerMercatorY = log(tan(.pi / 4.0 + latRad / 2.0)) * 180.0 / .pi
    }

    // MARK: - Geographic to World-Space

    /// Convert longitude to world X coordinate. Center longitude maps to X = 0.
    func lonToX(_ lon: Double) -> Float {
        return Float((lon - centerLon) * worldScale)
    }

    /// Convert latitude to world Z coordinate using Mercator projection. Center latitude maps to Z = 0.
    /// Note: Z is negated so that north is towards negative Z (into the screen with default camera).
    func latToZ(_ lat: Double) -> Float {
        let latRad = lat * .pi / 180.0
        let mercatorY = log(tan(.pi / 4.0 + latRad / 2.0)) * 180.0 / .pi
        // Negate so north (higher lat / higher mercatorY) goes to negative Z
        return Float(-(mercatorY - centerMercatorY) * worldScale)
    }

    // MARK: - World-Space to Geographic

    /// Convert world X back to longitude.
    func xToLon(_ x: Float) -> Double {
        return Double(x) / worldScale + centerLon
    }

    /// Convert world Z back to latitude (inverse Mercator).
    func zToLat(_ z: Float) -> Double {
        let mercatorY = -Double(z) / worldScale + centerMercatorY
        let latRad = 2.0 * atan(exp(mercatorY * .pi / 180.0)) - .pi / 2.0
        return latRad * 180.0 / .pi
    }

    // MARK: - Convenience

    /// Convert a geographic point to world-space XZ (Y is always 0 on ground).
    func worldPosition(lat: Double, lon: Double) -> SIMD3<Float> {
        return SIMD3<Float>(lonToX(lon), 0, latToZ(lat))
    }
}
