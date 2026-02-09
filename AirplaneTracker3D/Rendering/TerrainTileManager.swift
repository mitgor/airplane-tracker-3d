import MetalKit
import Foundation
import ImageIO

/// Manages asynchronous fetching of Terrarium elevation tiles, decoding elevation data,
/// and generating 32x32 subdivided terrain meshes with vertex displacement.
/// Modeled after MapTileManager with the same async fetch + LRU cache pattern.
final class TerrainTileManager {

    // MARK: - Types

    /// Terrain mesh data stored in cache and used for rendering.
    struct TerrainMeshData {
        let vertexBuffer: MTLBuffer
        let indexBuffer: MTLBuffer
        let indexCount: Int
    }

    // MARK: - Properties

    private let device: MTLDevice

    /// LRU cache: tile coordinate -> terrain mesh data
    private var cache: [TileCoordinate: TerrainMeshData] = [:]
    /// Ordered list for LRU eviction (most recently used at the end)
    private var cacheOrder: [TileCoordinate] = []
    /// Maximum number of cached terrain meshes
    private let maxCacheSize: Int = 250

    /// Tiles currently being downloaded (prevents duplicate requests)
    private var pendingRequests: Set<TileCoordinate> = []

    /// URLSession configured for AWS Terrarium tile fetching
    private let urlSession: URLSession

    /// Serial queue for thread-safe cache access
    private let cacheQueue = DispatchQueue(label: "com.airplanetracker3d.terraincache")

    /// Terrain elevation scale factor.
    /// At 0.005, Everest (8849m) = 44.2 units. Cruise altitude (10668m * 0.001) = 10.7 units.
    /// Using 0.003 for a balanced look: Everest = 26.5 units, still visually prominent.
    let terrainScaleFactor: Float = 0.003

    /// Subdivision count for terrain mesh (32x32 segments)
    private let subdivisions: Int = 32

    /// Shared coordinate system
    private let coordSystem = MapCoordinateSystem.shared

    // MARK: - Init

    init(device: MTLDevice) {
        self.device = device

        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "AirplaneTracker3D/1.0"]
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.urlCache = URLCache(memoryCapacity: 50 * 1024 * 1024,
                                   diskCapacity: 200 * 1024 * 1024)
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Mesh Access

    /// Get the terrain mesh for a tile if cached, or start an async fetch.
    /// Returns nil if the tile is still loading (caller should render flat fallback).
    func terrainMesh(for tile: TileCoordinate) -> TerrainMeshData? {
        var cachedMesh: TerrainMeshData?
        var shouldFetch = false

        cacheQueue.sync {
            if let mesh = cache[tile] {
                // Move to end of cacheOrder (mark as recently used)
                if let idx = cacheOrder.firstIndex(of: tile) {
                    cacheOrder.remove(at: idx)
                    cacheOrder.append(tile)
                }
                cachedMesh = mesh
            } else if !pendingRequests.contains(tile) {
                pendingRequests.insert(tile)
                shouldFetch = true
            }
        }

        if shouldFetch {
            fetchTerrainTile(tile)
        }

        return cachedMesh
    }

    // MARK: - Async Fetch

    /// Download a Terrarium PNG tile, decode elevation, and build a terrain mesh.
    private func fetchTerrainTile(_ tile: TileCoordinate) {
        let url = URL(string: "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/\(tile.zoom)/\(tile.x)/\(tile.y).png")!

        Task {
            do {
                let (data, response) = try await urlSession.data(from: url)

                // Verify valid response
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode != 200 {
                    cacheQueue.sync { pendingRequests.remove(tile) }
                    return
                }

                // Decode PNG to raw RGBA pixels
                guard let elevations = decodeTerrainPNG(data: data) else {
                    cacheQueue.sync { pendingRequests.remove(tile) }
                    return
                }

                // Build terrain mesh from elevation data
                let mesh = buildTerrainMesh(tile: tile, elevations: elevations)

                // Store in cache
                cacheQueue.sync {
                    pendingRequests.remove(tile)
                    if let mesh = mesh {
                        cache[tile] = mesh
                        cacheOrder.append(tile)

                        // Evict oldest if over limit
                        while cacheOrder.count > maxCacheSize {
                            let evicted = cacheOrder.removeFirst()
                            cache.removeValue(forKey: evicted)
                        }
                    }
                }
            } catch {
                #if DEBUG
                print("[TerrainTileManager] Failed to fetch tile \(tile.zoom)/\(tile.x)/\(tile.y): \(error.localizedDescription)")
                #endif
                cacheQueue.sync { pendingRequests.remove(tile) }
            }
        }
    }

    // MARK: - PNG Decoding

    /// Decode a Terrarium PNG to an array of 65536 elevation values (256x256).
    /// Terrarium formula: elevation = (R * 256 + G + B/256) - 32768
    private func decodeTerrainPNG(data: Data) -> [Float]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width == 256, height == 256 else { return nil }

        // Create RGBA context to extract pixel bytes
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 0, count: bytesPerRow * height)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Apply Terrarium formula to all pixels
        var elevations = [Float](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let offset = i * 4
            let r = Float(pixelData[offset])
            let g = Float(pixelData[offset + 1])
            let b = Float(pixelData[offset + 2])
            elevations[i] = (r * 256.0 + g + b / 256.0) - 32768.0
        }

        return elevations
    }

    // MARK: - Mesh Generation

    /// Build a 32x32 subdivided terrain mesh from elevation data.
    /// Returns nil if buffer creation fails.
    private func buildTerrainMesh(tile: TileCoordinate, elevations: [Float]) -> TerrainMeshData? {
        let segs = subdivisions // 32
        let vertsPerSide = segs + 1 // 33
        let vertexCount = vertsPerSide * vertsPerSide // 1089
        let triangleCount = segs * segs * 2 // 2048
        let indexCount = triangleCount * 3 // 6144

        // Get tile world bounds
        let bounds = TileCoordinate.tileBounds(tile: tile)
        let minX = coordSystem.lonToX(bounds.minLon)
        let maxX = coordSystem.lonToX(bounds.maxLon)
        let minZ = coordSystem.latToZ(bounds.maxLat) // north edge -> smaller Z
        let maxZ = coordSystem.latToZ(bounds.minLat) // south edge -> larger Z

        let extentX = maxX - minX
        let extentZ = maxZ - minZ

        // Generate vertices with elevation displacement
        var vertices = [TerrainVertex](repeating: TerrainVertex(
            position: SIMD3<Float>(0, 0, 0),
            texCoord: SIMD2<Float>(0, 0),
            normal: SIMD3<Float>(0, 1, 0)
        ), count: vertexCount)

        for iy in 0...segs {
            for ix in 0...segs {
                let u = Float(ix) / Float(segs)
                let v = Float(iy) / Float(segs)

                let worldX = minX + u * extentX
                let worldZ = minZ + v * extentZ

                // Sample elevation from 256x256 grid
                let ex = min(Int(u * 255.0), 255)
                let ey = min(Int(v * 255.0), 255)
                let elevation = elevations[ey * 256 + ex]

                // Clamp negative (ocean) to zero
                let worldY = max(0, elevation) * terrainScaleFactor

                let idx = iy * vertsPerSide + ix
                vertices[idx].position = SIMD3<Float>(worldX, worldY, worldZ)
                vertices[idx].texCoord = SIMD2<Float>(u, v)
                // Normal will be computed after all positions are set
            }
        }

        // Generate triangle indices (two triangles per quad, UInt32)
        var indices = [UInt32](repeating: 0, count: indexCount)
        var iIdx = 0
        for iy in 0..<segs {
            for ix in 0..<segs {
                let topLeft = UInt32(iy * vertsPerSide + ix)
                let topRight = topLeft + 1
                let bottomLeft = UInt32((iy + 1) * vertsPerSide + ix)
                let bottomRight = bottomLeft + 1

                // Triangle 1: top-left, bottom-left, top-right
                indices[iIdx] = topLeft;     iIdx += 1
                indices[iIdx] = bottomLeft;  iIdx += 1
                indices[iIdx] = topRight;    iIdx += 1

                // Triangle 2: top-right, bottom-left, bottom-right
                indices[iIdx] = topRight;    iIdx += 1
                indices[iIdx] = bottomLeft;  iIdx += 1
                indices[iIdx] = bottomRight; iIdx += 1
            }
        }

        // Compute normals using neighbor cross-product method
        for iy in 0...segs {
            for ix in 0...segs {
                let idx = iy * vertsPerSide + ix

                // Get neighboring positions (clamped at edges)
                let left  = vertices[iy * vertsPerSide + max(ix - 1, 0)].position
                let right = vertices[iy * vertsPerSide + min(ix + 1, segs)].position
                let up    = vertices[max(iy - 1, 0) * vertsPerSide + ix].position
                let down  = vertices[min(iy + 1, segs) * vertsPerSide + ix].position

                let dx = right - left
                let dz = down - up

                var normal = simd_cross(dz, dx)
                let len = simd_length(normal)
                if len > 0.0001 {
                    normal /= len
                } else {
                    normal = SIMD3<Float>(0, 1, 0)
                }

                vertices[idx].normal = normal
            }
        }

        // Create Metal buffers
        guard let vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<TerrainVertex>.stride * vertexCount,
            options: .storageModeShared
        ) else {
            return nil
        }
        vertexBuffer.label = "Terrain Vertices \(tile.zoom)/\(tile.x)/\(tile.y)"

        guard let indexBuffer = device.makeBuffer(
            bytes: indices,
            length: MemoryLayout<UInt32>.stride * indexCount,
            options: .storageModeShared
        ) else {
            return nil
        }
        indexBuffer.label = "Terrain Indices \(tile.zoom)/\(tile.x)/\(tile.y)"

        return TerrainMeshData(
            vertexBuffer: vertexBuffer,
            indexBuffer: indexBuffer,
            indexCount: indexCount
        )
    }

    // MARK: - Cache Management

    /// Clear all cached terrain meshes.
    func clearCache() {
        cacheQueue.sync {
            cache.removeAll()
            cacheOrder.removeAll()
            pendingRequests.removeAll()
        }
    }
}
