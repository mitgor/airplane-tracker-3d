import MetalKit
import simd

// MARK: - TrailManager

/// Manages per-aircraft trail point ring buffers and produces GPU vertex data
/// for screen-space polyline extrusion rendering. Triple-buffered to match
/// the Renderer's triple buffering scheme.
final class TrailManager {

    // MARK: - Types

    /// A single trail point stored on CPU.
    struct TrailPoint {
        var position: SIMD3<Float>
        var altitude: Float
    }

    /// Fixed-capacity ring buffer of trail points for one aircraft.
    struct TrailRingBuffer {
        var points: [TrailPoint] = []
        let maxLength: Int

        mutating func append(_ point: TrailPoint) {
            points.append(point)
            if points.count > maxLength {
                points.removeFirst(points.count - maxLength)
            }
        }
    }

    // MARK: - Configuration

    /// Maximum number of trail points per aircraft (configurable, range 50-4000).
    var maxTrailLength: Int = 500 {
        didSet {
            maxTrailLength = max(50, min(4000, maxTrailLength))
        }
    }

    /// Screen-space line width in pixels.
    var lineWidth: Float = 3.0

    // MARK: - State

    /// Per-aircraft trail ring buffers keyed by hex identifier.
    private var trails: [String: TrailRingBuffer] = [:]

    /// Tracks how many consecutive update calls each aircraft has been missing.
    private var missCount: [String: Int] = [:]

    /// Set of hex IDs present in the most recent update call.
    private var currentHexSet: Set<String> = []

    // MARK: - GPU Buffers

    /// Triple-buffered trail vertex buffers for GPU rendering.
    private var trailBuffers: [MTLBuffer] = []

    /// How many trail vertices were written to each frame buffer.
    private var trailVertexCounts: [Int] = [0, 0, 0]

    /// Maximum number of aircraft to support.
    private let maxAircraft = 1024

    /// Metal device reference.
    private let device: MTLDevice

    // MARK: - Init

    init(device: MTLDevice) {
        self.device = device

        // Pre-allocate triple-buffered trail vertex buffers.
        // Each aircraft can have maxTrailLength points, each producing 2 vertices,
        // plus 2 degenerate vertices per aircraft for strip breaks.
        // Use a generous default allocation: 1024 aircraft * 500 points * 2 verts * 64 bytes
        let vertexStride = MemoryLayout<TrailVertex>.stride
        let maxVerticesPerAircraft = 500 * 2 + 2  // points * 2 sides + 2 degenerate
        let bufferSize = maxAircraft * maxVerticesPerAircraft * vertexStride

        for i in 0..<Renderer.maxFramesInFlight {
            guard let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
                fatalError("Failed to create trail vertex buffer")
            }
            buffer.label = "Trail Vertex Buffer \(i)"
            trailBuffers.append(buffer)
        }
    }

    // MARK: - Per-Frame Update

    /// Update trail ring buffers from interpolated aircraft states and flatten to GPU vertex buffer.
    ///
    /// - Parameters:
    ///   - states: Current frame's interpolated aircraft states.
    ///   - bufferIndex: Which triple-buffer slot to write to.
    ///   - tintColor: When non-nil, replaces altitude colors with this tint (retro mode).
    func update(states: [InterpolatedAircraftState], bufferIndex: Int, tintColor: SIMD4<Float>? = nil) {
        // Build set of current hex IDs
        currentHexSet.removeAll(keepingCapacity: true)
        for state in states {
            currentHexSet.insert(state.hex)
        }

        // 1. Append new trail points for each aircraft
        for state in states {
            if trails[state.hex] == nil {
                trails[state.hex] = TrailRingBuffer(points: [], maxLength: maxTrailLength)
            }

            // Skip if position is essentially the same as the last point
            if let lastPoint = trails[state.hex]?.points.last {
                let dist = simd_distance(lastPoint.position, state.position)
                if dist < 0.1 {
                    continue
                }
            }

            let point = TrailPoint(position: state.position, altitude: state.altitude)
            trails[state.hex]?.append(point)

            // Reset miss count since this aircraft is present
            missCount[state.hex] = 0
        }

        // 2. Track and remove stale aircraft (missing for 3+ consecutive calls)
        var toRemove: [String] = []
        for hex in trails.keys {
            if !currentHexSet.contains(hex) {
                let count = (missCount[hex] ?? 0) + 1
                missCount[hex] = count
                if count >= 3 {
                    toRemove.append(hex)
                }
            }
        }
        for hex in toRemove {
            trails.removeValue(forKey: hex)
            missCount.removeValue(forKey: hex)
        }

        // 3. Flatten all trail ring buffers into the GPU vertex buffer
        let buffer = trailBuffers[bufferIndex]
        let vertexPtr = buffer.contents().bindMemory(to: TrailVertex.self,
                                                      capacity: buffer.length / MemoryLayout<TrailVertex>.stride)
        let maxVertices = buffer.length / MemoryLayout<TrailVertex>.stride
        var vertexIndex = 0
        var isFirstTrail = true

        for (_, trail) in trails {
            let points = trail.points
            guard points.count >= 2 else { continue }

            // Insert degenerate triangle to break strip between aircraft trails
            if !isFirstTrail && vertexIndex > 0 && vertexIndex + 4 + points.count * 2 <= maxVertices {
                // Repeat last vertex of previous trail
                vertexPtr[vertexIndex] = vertexPtr[vertexIndex - 1]
                vertexIndex += 1

                // First vertex of this trail (direction = +1)
                let firstPoint = points[0]
                let nextPoint = points[1]
                let firstColor = tintColor.map { tint -> SIMD4<Float> in
                    var c = tint; c.w = 0.3; return c
                } ?? altitudeColor(firstPoint.altitude, alphaForIndex: 0, totalCount: points.count)
                vertexPtr[vertexIndex] = TrailVertex(
                    position: firstPoint.position,
                    direction: 1.0,
                    color: firstColor,
                    prevPosition: firstPoint.position,
                    _pad0: 0,
                    nextPosition: nextPoint.position,
                    _pad1: 0
                )
                vertexIndex += 1
            }
            isFirstTrail = false

            // Emit 2 vertices per point (direction = +1 and -1)
            for i in 0..<points.count {
                guard vertexIndex + 2 <= maxVertices else { break }

                let point = points[i]
                let prevPos = i > 0 ? points[i - 1].position : point.position
                let nextPos = i < points.count - 1 ? points[i + 1].position : point.position
                let color: SIMD4<Float>
                if let tint = tintColor {
                    // Retro mode: use tint with age-based alpha
                    let alphaT: Float = points.count > 1 ? Float(i) / Float(points.count - 1) : 1.0
                    color = SIMD4<Float>(tint.x, tint.y, tint.z, 0.3 + 0.7 * alphaT)
                } else {
                    color = altitudeColor(point.altitude, alphaForIndex: i, totalCount: points.count)
                }

                // +1 side
                vertexPtr[vertexIndex] = TrailVertex(
                    position: point.position,
                    direction: 1.0,
                    color: color,
                    prevPosition: prevPos,
                    _pad0: 0,
                    nextPosition: nextPos,
                    _pad1: 0
                )
                vertexIndex += 1

                // -1 side
                vertexPtr[vertexIndex] = TrailVertex(
                    position: point.position,
                    direction: -1.0,
                    color: color,
                    prevPosition: prevPos,
                    _pad0: 0,
                    nextPosition: nextPos,
                    _pad1: 0
                )
                vertexIndex += 1
            }
        }

        trailVertexCounts[bufferIndex] = vertexIndex
    }

    // MARK: - Buffer Accessors

    /// Get the trail vertex buffer for the given frame index.
    func trailBuffer(at index: Int) -> MTLBuffer {
        return trailBuffers[index]
    }

    /// Get the number of trail vertices written for the given frame index.
    func trailVertexCount(at index: Int) -> Int {
        return trailVertexCounts[index]
    }

    // MARK: - Altitude Color Gradient

    /// Altitude-based color gradient matching AircraftInstanceManager.altitudeColor().
    /// Green (low) -> Yellow -> Orange -> Pink (high).
    /// Alpha fades from 1.0 (newest) to 0.3 (oldest) along the trail length.
    ///
    /// - Parameters:
    ///   - altitude: Altitude in feet.
    ///   - alphaForIndex: Index of this point in the trail (0 = oldest).
    ///   - totalCount: Total number of points in the trail.
    /// - Returns: RGBA color as SIMD4<Float>.
    private func altitudeColor(_ altitude: Float, alphaForIndex index: Int, totalCount: Int) -> SIMD4<Float> {
        // Base color from altitude
        var color: SIMD4<Float>
        if altitude < 5000 {
            // Green
            color = SIMD4<Float>(0.2, 0.8, 0.2, 1.0)
        } else if altitude < 15000 {
            // Green -> Yellow
            let t = (altitude - 5000) / 10000
            color = SIMD4<Float>(0.2 + 0.8 * t, 0.8, 0.2 * (1 - t), 1.0)
        } else if altitude < 30000 {
            // Yellow -> Orange
            let t = (altitude - 15000) / 15000
            color = SIMD4<Float>(1.0, 0.8 - 0.3 * t, 0.0, 1.0)
        } else {
            // Orange -> Pink
            let t = min((altitude - 30000) / 15000, 1.0)
            color = SIMD4<Float>(1.0, 0.5 - 0.1 * t, 0.3 * t, 1.0)
        }

        // Alpha fade: 0.3 (oldest, index 0) to 1.0 (newest, index totalCount-1)
        let alphaT: Float
        if totalCount > 1 {
            alphaT = Float(index) / Float(totalCount - 1)
        } else {
            alphaT = 1.0
        }
        color.w = 0.3 + 0.7 * alphaT

        return color
    }
}
