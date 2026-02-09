import MetalKit
import simd

// MARK: - HeatmapManager

/// Manages a 32x32 CPU-side density grid that accumulates aircraft detection counts,
/// converts them to a theme-aware color-ramped RGBA Metal texture, and provides a
/// textured ground-plane quad for rendering.
///
/// Design: CPU-side heatmap grid with texture upload, no compute shader needed for 32x32 grid.
final class HeatmapManager {

    // MARK: - Configuration

    /// Grid resolution (32x32 = 1024 cells).
    private let gridSize = 32

    /// Ground quad Y offset (slightly above ground to prevent z-fighting with map tiles).
    private let groundY: Float = 0.01

    // MARK: - State

    private let device: MTLDevice
    private let coordSystem = MapCoordinateSystem.shared

    /// 32x32 flat array: each cell counts aircraft detections.
    private var grid: [UInt32]

    /// Geographic bounds of the current grid (west, south, east, north).
    private var lastBounds: (west: Double, south: Double, east: Double, north: Double)?

    // MARK: - GPU Resources

    /// Reusable 32x32 RGBA8 Metal texture for heatmap color ramp.
    private let texture: MTLTexture

    /// Triple-buffered vertex buffers for the ground quad (6 vertices each).
    private var vertexBuffers: [MTLBuffer] = []

    /// Whether any grid cell has data (> 0).
    var hasData: Bool {
        return grid.contains(where: { $0 > 0 })
    }

    // MARK: - Init

    init(device: MTLDevice) {
        self.device = device

        // Initialize grid to zeros
        grid = [UInt32](repeating: 0, count: 32 * 32)

        // Create 32x32 RGBA8 texture (reused, replaced each frame via texture.replace)
        let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 32,
            height: 32,
            mipmapped: false
        )
        textureDesc.usage = [.shaderRead]
        textureDesc.storageMode = .managed

        guard let tex = device.makeTexture(descriptor: textureDesc) else {
            fatalError("Failed to create heatmap texture")
        }
        tex.label = "Heatmap Texture"
        self.texture = tex

        // Pre-allocate triple-buffered vertex buffers (6 vertices * 32 bytes = 192 bytes each)
        let bufferSize = 6 * MemoryLayout<HeatmapVertex>.stride
        for i in 0..<3 {
            guard let buf = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
                fatalError("Failed to create heatmap vertex buffer \(i)")
            }
            buf.label = "Heatmap Vertex Buffer \(i)"
            vertexBuffers.append(buf)
        }
    }

    // MARK: - Public API

    /// Accumulate aircraft positions into the 32x32 density grid.
    /// - Parameters:
    ///   - states: Current interpolated aircraft states.
    ///   - west: Western bound of visible area (longitude).
    ///   - south: Southern bound of visible area (latitude).
    ///   - east: Eastern bound of visible area (longitude).
    ///   - north: Northern bound of visible area (latitude).
    func accumulate(states: [InterpolatedAircraftState],
                    west: Double, south: Double, east: Double, north: Double) {
        // Check if bounds shifted > 50% -- if so, reset grid
        if let last = lastBounds {
            let latSpan = last.north - last.south
            let lonSpan = last.east - last.west
            let latShift = abs((north + south) / 2 - (last.north + last.south) / 2)
            let lonShift = abs((east + west) / 2 - (last.east + last.west) / 2)

            if latShift > latSpan * 0.5 || lonShift > lonSpan * 0.5 {
                // Camera moved significantly -- reset grid
                grid = [UInt32](repeating: 0, count: gridSize * gridSize)
                lastBounds = (west: west, south: south, east: east, north: north)
            }
        } else {
            // First accumulation
            lastBounds = (west: west, south: south, east: east, north: north)
        }

        guard let bounds = lastBounds else { return }

        let lonSpan = bounds.east - bounds.west
        let latSpan = bounds.north - bounds.south
        guard lonSpan > 0 && latSpan > 0 else { return }

        // Map each aircraft into the grid
        for state in states {
            let lon = state.lon
            let lat = state.lat

            // Normalize to 0..1 within bounds
            let normX = (lon - bounds.west) / lonSpan
            let normY = (lat - bounds.south) / latSpan

            // Skip aircraft outside bounds
            guard normX >= 0 && normX < 1 && normY >= 0 && normY < 1 else { continue }

            // Map to grid cell
            let gx = Int(normX * Double(gridSize))
            let gy = Int(normY * Double(gridSize))

            // Clamp (safety)
            let clampedX = min(gx, gridSize - 1)
            let clampedY = min(gy, gridSize - 1)

            grid[clampedY * gridSize + clampedX] += 1
        }
    }

    /// Generate RGBA texture from grid and update ground-quad vertex buffer.
    /// - Parameters:
    ///   - bufferIndex: Triple-buffer index for this frame.
    ///   - themeConfig: Current theme configuration for color ramp selection.
    func update(bufferIndex: Int, themeConfig: ThemeConfig) {
        guard let bounds = lastBounds else { return }

        // --- Generate RGBA texture from grid ---
        generateTexture(themeConfig: themeConfig)

        // --- Update ground quad geometry ---
        updateQuadGeometry(bufferIndex: bufferIndex, bounds: bounds)
    }

    // MARK: - Accessors for Renderer

    /// Get vertex buffer for the given frame index.
    func vertexBuffer(at index: Int) -> MTLBuffer {
        return vertexBuffers[index]
    }

    /// Vertex count (always 6: two triangles forming a quad).
    func vertexCount() -> Int {
        return 6
    }

    /// Get the heatmap texture.
    func heatmapTexture() -> MTLTexture? {
        return hasData ? texture : nil
    }

    // MARK: - Texture Generation

    /// Generate RGBA8 texture from grid data with theme-aware color ramp.
    private func generateTexture(themeConfig: ThemeConfig) {
        // Find max value (clamp to at least 1 to avoid division by zero)
        let maxVal = max(grid.max() ?? 0, 1)

        // Determine color ramp parameters based on theme
        let isRetro = themeConfig.isWireframe
        let isNight: Bool
        // Detect night theme by clear color (dark blue background)
        if themeConfig.clearColor.r < 0.1 && themeConfig.clearColor.g < 0.1 && themeConfig.clearColor.b < 0.2 && !isRetro {
            isNight = true
        } else {
            isNight = false
        }

        // Build RGBA8 pixel data
        var pixels = [UInt8](repeating: 0, count: gridSize * gridSize * 4)

        for y in 0..<gridSize {
            for x in 0..<gridSize {
                let cellValue = grid[y * gridSize + x]
                let pixelIndex = (y * gridSize + x) * 4

                if cellValue == 0 {
                    // Transparent
                    pixels[pixelIndex + 0] = 0
                    pixels[pixelIndex + 1] = 0
                    pixels[pixelIndex + 2] = 0
                    pixels[pixelIndex + 3] = 0
                    continue
                }

                let intensity = Float(cellValue) / Float(maxVal)

                var r: Float
                var g: Float
                var b: Float
                var a: Float

                if isRetro {
                    // Retro: dark-green at low -> bright-green at high
                    r = 0
                    g = Float(60) / 255.0 + intensity * (255.0 - 60.0) / 255.0
                    b = 0
                    a = 0.15 + intensity * 0.55
                } else if isNight {
                    // Night: dark-blue at low -> bright-cyan at high
                    r = 0
                    g = Float(80) / 255.0 + intensity * (255.0 - 80.0) / 255.0
                    b = Float(180) / 255.0 + intensity * (255.0 - 180.0) / 255.0
                    a = 0.15 + intensity * 0.55
                } else {
                    // Day: blue at low -> cyan at high
                    r = 0
                    g = Float(100) / 255.0 + intensity * (255.0 - 100.0) / 255.0
                    b = 1.0
                    a = 0.15 + intensity * 0.45
                }

                // Premultiply alpha for correct blending
                let pr = r * a
                let pg = g * a
                let pb = b * a

                pixels[pixelIndex + 0] = UInt8(min(max(pr * 255.0, 0), 255))
                pixels[pixelIndex + 1] = UInt8(min(max(pg * 255.0, 0), 255))
                pixels[pixelIndex + 2] = UInt8(min(max(pb * 255.0, 0), 255))
                pixels[pixelIndex + 3] = UInt8(min(max(a * 255.0, 0), 255))
            }
        }

        // Upload to Metal texture
        let region = MTLRegionMake2D(0, 0, gridSize, gridSize)
        texture.replace(region: region, mipmapLevel: 0,
                        withBytes: pixels, bytesPerRow: gridSize * 4)
    }

    // MARK: - Quad Geometry

    /// Update the ground-plane quad vertices from geographic bounds.
    private func updateQuadGeometry(bufferIndex: Int,
                                     bounds: (west: Double, south: Double, east: Double, north: Double)) {
        // Convert geographic bounds to world-space
        let minX = coordSystem.lonToX(bounds.west)
        let maxX = coordSystem.lonToX(bounds.east)
        // Note: latToZ has negative Z for north, so north -> smaller Z value
        let minZ = coordSystem.latToZ(bounds.north) // north edge -> smaller Z
        let maxZ = coordSystem.latToZ(bounds.south) // south edge -> larger Z

        // 6 vertices forming 2 triangles (quad)
        // texCoord: (0,0) at northwest corner, (1,1) at southeast corner
        let vertices: [HeatmapVertex] = [
            // Triangle 1: NW, NE, SE
            HeatmapVertex(position: SIMD3<Float>(minX, groundY, minZ),
                          _pad0: 0,
                          texCoord: SIMD2<Float>(0, 0),
                          _pad1: SIMD2<Float>(0, 0)),
            HeatmapVertex(position: SIMD3<Float>(maxX, groundY, minZ),
                          _pad0: 0,
                          texCoord: SIMD2<Float>(1, 0),
                          _pad1: SIMD2<Float>(0, 0)),
            HeatmapVertex(position: SIMD3<Float>(maxX, groundY, maxZ),
                          _pad0: 0,
                          texCoord: SIMD2<Float>(1, 1),
                          _pad1: SIMD2<Float>(0, 0)),
            // Triangle 2: NW, SE, SW
            HeatmapVertex(position: SIMD3<Float>(minX, groundY, minZ),
                          _pad0: 0,
                          texCoord: SIMD2<Float>(0, 0),
                          _pad1: SIMD2<Float>(0, 0)),
            HeatmapVertex(position: SIMD3<Float>(maxX, groundY, maxZ),
                          _pad0: 0,
                          texCoord: SIMD2<Float>(1, 1),
                          _pad1: SIMD2<Float>(0, 0)),
            HeatmapVertex(position: SIMD3<Float>(minX, groundY, maxZ),
                          _pad0: 0,
                          texCoord: SIMD2<Float>(0, 1),
                          _pad1: SIMD2<Float>(0, 0)),
        ]

        // Write to the appropriate triple-buffered buffer
        let ptr = vertexBuffers[bufferIndex].contents().bindMemory(to: HeatmapVertex.self, capacity: 6)
        for i in 0..<6 {
            ptr[i] = vertices[i]
        }
    }
}
