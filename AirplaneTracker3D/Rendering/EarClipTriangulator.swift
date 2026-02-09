import simd

// MARK: - EarClipTriangulator

/// Pure Swift ear-clipping polygon triangulation.
/// Converts a 2D polygon (array of XZ points) into triangle index arrays
/// suitable for Metal rendering. Handles convex and mildly concave polygons
/// typical of FAA airspace boundaries (8-50 vertices).
struct EarClipTriangulator {

    /// Triangulate a 2D polygon into triangle indices.
    /// - Parameter polygon: Array of 2D points in counter-clockwise order.
    ///   Points should form a simple (non-self-intersecting) polygon.
    /// - Returns: Array of UInt32 index triples (every 3 values = one triangle).
    ///   Returns empty array if polygon has fewer than 3 vertices.
    static func triangulate(polygon: [SIMD2<Float>]) -> [UInt32] {
        guard polygon.count >= 3 else { return [] }

        // Work with a mutable copy of indices
        var indices = Array(0..<polygon.count)

        // Ensure counter-clockwise winding
        if signedArea(polygon) < 0 {
            indices.reverse()
        }

        var result: [UInt32] = []
        result.reserveCapacity((polygon.count - 2) * 3)

        var safetyCounter = indices.count * indices.count // O(n^2) max iterations
        var i = 0

        while indices.count > 2 && safetyCounter > 0 {
            safetyCounter -= 1
            let n = indices.count

            let prev = indices[(i + n - 1) % n]
            let curr = indices[i % n]
            let next = indices[(i + 1) % n]

            if isEar(polygon: polygon, indices: indices, prev: prev, curr: curr, next: next) {
                // Emit triangle
                result.append(UInt32(prev))
                result.append(UInt32(curr))
                result.append(UInt32(next))

                // Remove the ear tip vertex
                indices.remove(at: i % n)

                // Stay at current index (next vertex slides into this position)
                if indices.count > 0 {
                    i = i % indices.count
                }
            } else {
                i = (i + 1) % n
            }
        }

        return result
    }

    // MARK: - Private Helpers

    /// Compute the signed area of a polygon (positive = CCW, negative = CW).
    private static func signedArea(_ polygon: [SIMD2<Float>]) -> Float {
        var area: Float = 0
        let n = polygon.count
        for i in 0..<n {
            let j = (i + 1) % n
            area += polygon[i].x * polygon[j].y
            area -= polygon[j].x * polygon[i].y
        }
        return area * 0.5
    }

    /// Check if the triangle (prev, curr, next) forms a valid ear.
    /// An ear is a convex vertex whose triangle contains no other polygon vertices.
    private static func isEar(polygon: [SIMD2<Float>], indices: [Int],
                              prev: Int, curr: Int, next: Int) -> Bool {
        let a = polygon[prev]
        let b = polygon[curr]
        let c = polygon[next]

        // Check convexity: cross product must be positive (CCW turn)
        let cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        if cross <= 0 {
            return false
        }

        // Check that no other vertex lies inside the triangle
        for idx in indices {
            if idx == prev || idx == curr || idx == next { continue }
            if pointInTriangle(polygon[idx], a: a, b: b, c: c) {
                return false
            }
        }

        return true
    }

    /// Point-in-triangle test using barycentric coordinates.
    private static func pointInTriangle(_ p: SIMD2<Float>,
                                         a: SIMD2<Float>,
                                         b: SIMD2<Float>,
                                         c: SIMD2<Float>) -> Bool {
        let v0 = c - a
        let v1 = b - a
        let v2 = p - a

        let dot00 = v0.x * v0.x + v0.y * v0.y
        let dot01 = v0.x * v1.x + v0.y * v1.y
        let dot02 = v0.x * v2.x + v0.y * v2.y
        let dot11 = v1.x * v1.x + v1.y * v1.y
        let dot12 = v1.x * v2.x + v1.y * v2.y

        let invDenom = 1.0 / (dot00 * dot11 - dot01 * dot01)
        let u = (dot11 * dot02 - dot01 * dot12) * invDenom
        let v = (dot00 * dot12 - dot01 * dot02) * invDenom

        // Point is inside if u >= 0, v >= 0, and u + v < 1
        // Use small epsilon to avoid edge cases
        return u >= -0.0001 && v >= -0.0001 && (u + v) < 1.0001
    }
}
