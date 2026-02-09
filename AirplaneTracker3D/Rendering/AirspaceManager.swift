import MetalKit
import simd

// MARK: - AirspaceFeature

/// A parsed FAA airspace polygon with pre-built GPU vertices.
struct AirspaceFeature {
    let name: String
    let airspaceClass: String   // "B", "C", "D"
    let floorFeet: Float
    let ceilingFeet: Float
    let fillVertices: [AirspaceVertex]
    let edgeVertices: [AirspaceVertex]
}

// MARK: - AirspaceManager

/// Manages FAA Class B/C/D airspace volume data: fetching from ArcGIS,
/// parsing GeoJSON, triangulating polygons, extruding 3D meshes, and
/// maintaining triple-buffered GPU vertex buffers for Metal rendering.
final class AirspaceManager {

    // MARK: - Configuration

    /// Altitude scale matching FlightDataActor (feet to world Y).
    private let altitudeScale: Float = 0.001

    /// Minimum height for airspace volumes to ensure visibility.
    private let minimumHeight: Float = 0.5

    /// Maximum vertices per fill buffer (covers ~100 airspace features).
    private let maxFillVertices = 50_000

    /// Maximum vertices per edge buffer.
    private let maxEdgeVertices = 20_000

    // MARK: - Class Visibility Toggles

    var showClassB = true
    var showClassC = true
    var showClassD = true

    // MARK: - State

    private let device: MTLDevice
    private let coordSystem = MapCoordinateSystem.shared

    /// Cached airspace features from FAA API.
    private var features: [AirspaceFeature] = []

    /// Whether a data fetch is currently in progress.
    private var isLoading = false

    /// Last fetch bounds to avoid redundant re-fetches.
    private var lastFetchBounds: (west: Double, south: Double, east: Double, north: Double)?

    // MARK: - GPU Buffers (Triple-Buffered)

    /// Triple-buffered vertex buffers for airspace fill geometry.
    private var fillBuffers: [MTLBuffer] = []

    /// Vertex counts written to each fill buffer.
    private var fillVertexCounts: [Int] = [0, 0, 0]

    /// Triple-buffered vertex buffers for airspace edge geometry.
    private var edgeBuffers: [MTLBuffer] = []

    /// Vertex counts written to each edge buffer.
    private var edgeVertexCounts: [Int] = [0, 0, 0]

    // MARK: - Init

    init(device: MTLDevice) {
        self.device = device

        // Pre-allocate triple-buffered fill and edge vertex buffers
        let fillBufferSize = maxFillVertices * MemoryLayout<AirspaceVertex>.stride
        let edgeBufferSize = maxEdgeVertices * MemoryLayout<AirspaceVertex>.stride

        for i in 0..<3 {
            guard let fb = device.makeBuffer(length: fillBufferSize, options: .storageModeShared) else {
                fatalError("Failed to create airspace fill buffer \(i)")
            }
            fb.label = "Airspace Fill Buffer \(i)"
            fillBuffers.append(fb)

            guard let eb = device.makeBuffer(length: edgeBufferSize, options: .storageModeShared) else {
                fatalError("Failed to create airspace edge buffer \(i)")
            }
            eb.label = "Airspace Edge Buffer \(i)"
            edgeBuffers.append(eb)
        }
    }

    // MARK: - Public API

    /// Load airspace data for the given geographic bounds.
    /// Only re-fetches if camera has shifted significantly (>20%).
    func loadAirspace(west: Double, south: Double, east: Double, north: Double) async {
        // Check if we need to re-fetch
        if let last = lastFetchBounds {
            let latSpan = north - south
            let lonSpan = east - west
            let latShift = abs((north + south) / 2 - (last.north + last.south) / 2)
            let lonShift = abs((east + west) / 2 - (last.east + last.west) / 2)

            if latShift < latSpan * 0.2 && lonShift < lonSpan * 0.2 {
                return // Camera hasn't moved enough
            }
        }

        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let geojsonFeatures = try await fetchAirspaceData(
                west: west, south: south, east: east, north: north
            )
            let builtFeatures = buildFeatures(from: geojsonFeatures)

            // Update on main thread to avoid race with rendering
            await MainActor.run {
                self.features = builtFeatures
                self.lastFetchBounds = (west: west, south: south, east: east, north: north)
            }
        } catch {
            #if DEBUG
            print("[AirspaceManager] Failed to load airspace: \(error)")
            #endif
        }
    }

    /// Update GPU buffers for the current frame (called each frame from Renderer).
    /// Filters features by class toggles and writes to the appropriate buffer index.
    func update(bufferIndex: Int) {
        let stride = MemoryLayout<AirspaceVertex>.stride

        // Filter features by class visibility
        let visibleFeatures = features.filter { feature in
            switch feature.airspaceClass {
            case "B": return showClassB
            case "C": return showClassC
            case "D": return showClassD
            default: return false
            }
        }

        // Sort: D first, then C, then B (back-to-front by class importance)
        let sorted = visibleFeatures.sorted { a, b in
            let orderA = classOrder(a.airspaceClass)
            let orderB = classOrder(b.airspaceClass)
            return orderA < orderB
        }

        // Write fill vertices
        var fillCount = 0
        let fillPtr = fillBuffers[bufferIndex].contents().bindMemory(to: AirspaceVertex.self,
                                                                      capacity: maxFillVertices)
        for feature in sorted {
            let needed = feature.fillVertices.count
            guard fillCount + needed <= maxFillVertices else { break }
            for v in feature.fillVertices {
                fillPtr[fillCount] = v
                fillCount += 1
            }
        }
        fillVertexCounts[bufferIndex] = fillCount

        // Write edge vertices
        var edgeCount = 0
        let edgePtr = edgeBuffers[bufferIndex].contents().bindMemory(to: AirspaceVertex.self,
                                                                      capacity: maxEdgeVertices)
        for feature in sorted {
            let needed = feature.edgeVertices.count
            guard edgeCount + needed <= maxEdgeVertices else { break }
            for v in feature.edgeVertices {
                edgePtr[edgeCount] = v
                edgeCount += 1
            }
        }
        edgeVertexCounts[bufferIndex] = edgeCount
    }

    /// Get fill vertex buffer for the given frame index.
    func fillBuffer(at index: Int) -> MTLBuffer {
        return fillBuffers[index]
    }

    /// Get fill vertex count for the given frame index.
    func fillVertexCount(at index: Int) -> Int {
        return fillVertexCounts[index]
    }

    /// Get edge vertex buffer for the given frame index.
    func edgeBuffer(at index: Int) -> MTLBuffer {
        return edgeBuffers[index]
    }

    /// Get edge vertex count for the given frame index.
    func edgeVertexCount(at index: Int) -> Int {
        return edgeVertexCounts[index]
    }

    // MARK: - Data Fetching

    /// Fetch FAA airspace GeoJSON from ArcGIS FeatureServer.
    private func fetchAirspaceData(west: Double, south: Double,
                                    east: Double, north: Double) async throws -> [[String: Any]] {
        let baseURL = "https://services6.arcgis.com/ssFJjBXIUyZDrSYZ/arcgis/rest/services/Class_Airspace/FeatureServer/0/query"

        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "where", value: "CLASS IN ('B','C','D')"),
            URLQueryItem(name: "geometry", value: "\(west),\(south),\(east),\(north)"),
            URLQueryItem(name: "geometryType", value: "esriGeometryEnvelope"),
            URLQueryItem(name: "inSR", value: "4326"),
            URLQueryItem(name: "spatialRel", value: "esriSpatialRelIntersects"),
            URLQueryItem(name: "outFields", value: "NAME,CLASS,LOCAL_TYPE,UPPER_VAL,LOWER_VAL,UPPER_UOM,LOWER_UOM,ICAO_ID"),
            URLQueryItem(name: "f", value: "geojson"),
            URLQueryItem(name: "resultRecordCount", value: "500"),
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            return []
        }

        return features
    }

    // MARK: - Feature Building

    /// Parse GeoJSON features and build mesh geometry for each.
    private func buildFeatures(from geojsonFeatures: [[String: Any]]) -> [AirspaceFeature] {
        var result: [AirspaceFeature] = []

        for feature in geojsonFeatures {
            guard let properties = feature["properties"] as? [String: Any],
                  let geometry = feature["geometry"] as? [String: Any],
                  let airClass = properties["CLASS"] as? String else {
                continue
            }

            let name = properties["NAME"] as? String ?? "Unknown"

            // Parse altitude values
            let floorFeet = parseAltitude(
                value: properties["LOWER_VAL"],
                unit: properties["LOWER_UOM"] as? String
            )
            let ceilingFeet = parseAltitude(
                value: properties["UPPER_VAL"],
                unit: properties["UPPER_UOM"] as? String
            )

            // Extract polygon coordinates
            guard let coords = extractCoordinates(from: geometry), coords.count >= 3 else {
                continue
            }

            // Convert to world-space 2D points (XZ plane)
            let worldPoints: [SIMD2<Float>] = coords.map { coord in
                let lon = coord[0]
                let lat = coord[1]
                let x = coordSystem.lonToX(lon)
                let z = coordSystem.latToZ(lat)
                return SIMD2<Float>(x, z)
            }

            // Triangulate the polygon
            let triangleIndices = EarClipTriangulator.triangulate(polygon: worldPoints)
            guard !triangleIndices.isEmpty else { continue }

            // Build extruded mesh
            let floorY = floorFeet * altitudeScale
            let ceilingY = max(floorY + minimumHeight, ceilingFeet * altitudeScale)

            let fillColor = fillColorForClass(airClass)
            let edgeColor = edgeColorForClass(airClass)

            let fillVertices = buildFillMesh(
                worldPoints: worldPoints,
                triangleIndices: triangleIndices,
                floorY: floorY,
                ceilingY: ceilingY,
                color: fillColor
            )

            let edgeVertices = buildEdgeMesh(
                worldPoints: worldPoints,
                floorY: floorY,
                ceilingY: ceilingY,
                color: edgeColor
            )

            result.append(AirspaceFeature(
                name: name,
                airspaceClass: airClass,
                floorFeet: floorFeet,
                ceilingFeet: ceilingFeet,
                fillVertices: fillVertices,
                edgeVertices: edgeVertices
            ))
        }

        return result
    }

    // MARK: - Coordinate Extraction

    /// Extract the first polygon ring coordinates from a GeoJSON geometry.
    private func extractCoordinates(from geometry: [String: Any]) -> [[Double]]? {
        guard let type = geometry["type"] as? String,
              let coordinates = geometry["coordinates"] else {
            return nil
        }

        switch type {
        case "Polygon":
            // coordinates is [[[Double]]] -- first ring
            guard let rings = coordinates as? [[[Double]]],
                  let ring = rings.first else { return nil }
            return ring

        case "MultiPolygon":
            // coordinates is [[[[Double]]]] -- first polygon, first ring
            guard let polygons = coordinates as? [[[[Double]]]],
                  let firstPolygon = polygons.first,
                  let ring = firstPolygon.first else { return nil }
            return ring

        default:
            return nil
        }
    }

    // MARK: - Altitude Parsing

    /// Parse an altitude value with unit conversion.
    /// FL (Flight Level) values are multiplied by 100 to get feet.
    private func parseAltitude(value: Any?, unit: String?) -> Float {
        guard let value = value else { return 0 }

        let numericValue: Float
        if let intVal = value as? Int {
            numericValue = Float(intVal)
        } else if let doubleVal = value as? Double {
            numericValue = Float(doubleVal)
        } else if let strVal = value as? String, let parsed = Float(strVal) {
            numericValue = parsed
        } else {
            return 0
        }

        // Flight Level: multiply by 100 to get feet
        if unit == "FL" {
            return numericValue * 100.0
        }

        return numericValue
    }

    // MARK: - Mesh Generation

    /// Build fill mesh: floor face + ceiling face + wall quads.
    private func buildFillMesh(worldPoints: [SIMD2<Float>],
                                triangleIndices: [UInt32],
                                floorY: Float, ceilingY: Float,
                                color: SIMD4<Float>) -> [AirspaceVertex] {
        var vertices: [AirspaceVertex] = []
        let triCount = triangleIndices.count / 3

        // Floor face (original winding)
        for i in 0..<triCount {
            let i0 = Int(triangleIndices[i * 3])
            let i1 = Int(triangleIndices[i * 3 + 1])
            let i2 = Int(triangleIndices[i * 3 + 2])

            vertices.append(AirspaceVertex(
                position: SIMD3<Float>(worldPoints[i0].x, floorY, worldPoints[i0].y),
                _pad0: 0,
                color: color
            ))
            vertices.append(AirspaceVertex(
                position: SIMD3<Float>(worldPoints[i1].x, floorY, worldPoints[i1].y),
                _pad0: 0,
                color: color
            ))
            vertices.append(AirspaceVertex(
                position: SIMD3<Float>(worldPoints[i2].x, floorY, worldPoints[i2].y),
                _pad0: 0,
                color: color
            ))
        }

        // Ceiling face (reversed winding for correct face orientation)
        for i in 0..<triCount {
            let i0 = Int(triangleIndices[i * 3])
            let i1 = Int(triangleIndices[i * 3 + 1])
            let i2 = Int(triangleIndices[i * 3 + 2])

            vertices.append(AirspaceVertex(
                position: SIMD3<Float>(worldPoints[i0].x, ceilingY, worldPoints[i0].y),
                _pad0: 0,
                color: color
            ))
            vertices.append(AirspaceVertex(
                position: SIMD3<Float>(worldPoints[i2].x, ceilingY, worldPoints[i2].y),
                _pad0: 0,
                color: color
            ))
            vertices.append(AirspaceVertex(
                position: SIMD3<Float>(worldPoints[i1].x, ceilingY, worldPoints[i1].y),
                _pad0: 0,
                color: color
            ))
        }

        // Wall quads: for each polygon edge, create 2 triangles connecting floor to ceiling
        let n = worldPoints.count
        for i in 0..<n {
            let j = (i + 1) % n

            let p0 = worldPoints[i]
            let p1 = worldPoints[j]

            // Floor corners
            let f0 = SIMD3<Float>(p0.x, floorY, p0.y)
            let f1 = SIMD3<Float>(p1.x, floorY, p1.y)

            // Ceiling corners
            let c0 = SIMD3<Float>(p0.x, ceilingY, p0.y)
            let c1 = SIMD3<Float>(p1.x, ceilingY, p1.y)

            // Triangle 1: f0, f1, c1
            vertices.append(AirspaceVertex(position: f0, _pad0: 0, color: color))
            vertices.append(AirspaceVertex(position: f1, _pad0: 0, color: color))
            vertices.append(AirspaceVertex(position: c1, _pad0: 0, color: color))

            // Triangle 2: f0, c1, c0
            vertices.append(AirspaceVertex(position: f0, _pad0: 0, color: color))
            vertices.append(AirspaceVertex(position: c1, _pad0: 0, color: color))
            vertices.append(AirspaceVertex(position: c0, _pad0: 0, color: color))
        }

        return vertices
    }

    /// Build edge mesh: outline lines at floor, ceiling, and vertical edges.
    /// Each line segment = 2 vertices (drawn with .line primitive type).
    private func buildEdgeMesh(worldPoints: [SIMD2<Float>],
                                floorY: Float, ceilingY: Float,
                                color: SIMD4<Float>) -> [AirspaceVertex] {
        var vertices: [AirspaceVertex] = []
        let n = worldPoints.count

        for i in 0..<n {
            let j = (i + 1) % n

            let p0 = worldPoints[i]
            let p1 = worldPoints[j]

            // Floor edge
            vertices.append(AirspaceVertex(
                position: SIMD3<Float>(p0.x, floorY, p0.y), _pad0: 0, color: color
            ))
            vertices.append(AirspaceVertex(
                position: SIMD3<Float>(p1.x, floorY, p1.y), _pad0: 0, color: color
            ))

            // Ceiling edge
            vertices.append(AirspaceVertex(
                position: SIMD3<Float>(p0.x, ceilingY, p0.y), _pad0: 0, color: color
            ))
            vertices.append(AirspaceVertex(
                position: SIMD3<Float>(p1.x, ceilingY, p1.y), _pad0: 0, color: color
            ))

            // Vertical edge at each vertex
            vertices.append(AirspaceVertex(
                position: SIMD3<Float>(p0.x, floorY, p0.y), _pad0: 0, color: color
            ))
            vertices.append(AirspaceVertex(
                position: SIMD3<Float>(p0.x, ceilingY, p0.y), _pad0: 0, color: color
            ))
        }

        return vertices
    }

    // MARK: - Color Mapping

    /// Fill color per airspace class (low alpha for transparency).
    private func fillColorForClass(_ airClass: String) -> SIMD4<Float> {
        switch airClass {
        case "B": return SIMD4<Float>(0.27, 0.40, 1.0, 0.06)  // Blue
        case "C": return SIMD4<Float>(0.60, 0.27, 1.0, 0.06)  // Purple
        case "D": return SIMD4<Float>(0.27, 0.67, 1.0, 0.06)  // Cyan
        default:  return SIMD4<Float>(0.27, 0.53, 1.0, 0.06)  // Fallback blue
        }
    }

    /// Edge color per airspace class (higher alpha for visibility).
    private func edgeColorForClass(_ airClass: String) -> SIMD4<Float> {
        switch airClass {
        case "B": return SIMD4<Float>(0.27, 0.40, 1.0, 0.3)
        case "C": return SIMD4<Float>(0.60, 0.27, 1.0, 0.3)
        case "D": return SIMD4<Float>(0.27, 0.67, 1.0, 0.3)
        default:  return SIMD4<Float>(0.27, 0.53, 1.0, 0.3)
        }
    }

    /// Sort order: D=1, C=2, B=3 (render D first, B last for correct layering).
    private func classOrder(_ airClass: String) -> Int {
        switch airClass {
        case "D": return 1
        case "C": return 2
        case "B": return 3
        default:  return 0
        }
    }
}
