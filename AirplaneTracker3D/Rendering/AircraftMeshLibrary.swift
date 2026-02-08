import MetalKit
import simd

// MARK: - Aircraft Mesh

/// A renderable mesh: vertex and index buffers with counts.
struct AircraftMesh {
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let vertexCount: Int
    let indexCount: Int
}

// MARK: - AircraftMeshLibrary

/// Generates procedural 3D geometry for all 6 aircraft categories plus
/// separate spinning part meshes (rotor, propeller).
class AircraftMeshLibrary {

    private var bodyMeshes: [AircraftCategory: AircraftMesh] = [:]
    private(set) var rotorMesh: AircraftMesh?
    private(set) var propellerMesh: AircraftMesh?

    init(device: MTLDevice) {
        // Generate body meshes for each category
        bodyMeshes[.jet] = buildJet(device: device)
        bodyMeshes[.widebody] = buildWidebody(device: device)
        bodyMeshes[.helicopter] = buildHelicopter(device: device)
        bodyMeshes[.small] = buildSmallProp(device: device)
        bodyMeshes[.military] = buildMilitary(device: device)
        bodyMeshes[.regional] = buildRegional(device: device)

        // Separate spinning meshes
        rotorMesh = buildRotor(device: device)
        propellerMesh = buildPropeller(device: device)
    }

    func mesh(for category: AircraftCategory) -> AircraftMesh {
        return bodyMeshes[category] ?? bodyMeshes[.jet]!
    }

    // MARK: - Glow Texture

    /// Create a 64x64 radial gradient glow texture (white with variable alpha).
    static func createGlowTexture(device: MTLDevice) -> MTLTexture? {
        let size = 64
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let center = Float(size) / 2.0
        for y in 0..<size {
            for x in 0..<size {
                let dx = Float(x) - center
                let dy = Float(y) - center
                let dist = sqrt(dx * dx + dy * dy) / center  // 0 at center, 1 at edge

                var alpha: Float = 0
                if dist < 0.3 {
                    alpha = 1.0
                } else if dist < 0.7 {
                    alpha = 1.0 - (dist - 0.3) / 0.4
                } else {
                    alpha = max(0, 1.0 - (dist - 0.3) / 0.7) * 0.2
                }

                let idx = (y * size + x) * 4
                pixels[idx + 0] = 255                        // R
                pixels[idx + 1] = 255                        // G
                pixels[idx + 2] = 255                        // B
                pixels[idx + 3] = UInt8(min(255, alpha * 255)) // A
            }
        }

        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: size, height: size, depth: 1))
        texture.replace(region: region, mipmapLevel: 0,
                       withBytes: pixels, bytesPerRow: size * 4)
        return texture
    }

    // MARK: - Geometry Helpers

    private func appendCylinder(
        vertices: inout [AircraftVertex], indices: inout [UInt16],
        radius: Float, height: Float, segments: Int = 8,
        offset: SIMD3<Float> = .zero
    ) {
        let base = UInt16(vertices.count)
        let halfH = height / 2.0

        // Generate side vertices (two rings)
        for i in 0..<segments {
            let angle = Float(i) / Float(segments) * 2.0 * .pi
            let x = cos(angle) * radius
            let z = sin(angle) * radius
            let normal = normalize(SIMD3<Float>(cos(angle), 0, sin(angle)))

            // Bottom ring
            vertices.append(AircraftVertex(
                position: SIMD3<Float>(x, -halfH, z) + offset,
                normal: normal
            ))
            // Top ring
            vertices.append(AircraftVertex(
                position: SIMD3<Float>(x, halfH, z) + offset,
                normal: normal
            ))
        }

        // Side indices
        for i in 0..<UInt16(segments) {
            let bl = base + i * 2
            let tl = base + i * 2 + 1
            let br = base + ((i + 1) % UInt16(segments)) * 2
            let tr = base + ((i + 1) % UInt16(segments)) * 2 + 1
            indices.append(contentsOf: [bl, br, tl, tl, br, tr])
        }

        // Cap centers
        let bottomCenter = UInt16(vertices.count)
        vertices.append(AircraftVertex(
            position: SIMD3<Float>(0, -halfH, 0) + offset,
            normal: SIMD3<Float>(0, -1, 0)
        ))
        let topCenter = UInt16(vertices.count)
        vertices.append(AircraftVertex(
            position: SIMD3<Float>(0, halfH, 0) + offset,
            normal: SIMD3<Float>(0, 1, 0)
        ))

        // Cap vertices (need separate normals for flat shading)
        let capBase = UInt16(vertices.count)
        for i in 0..<segments {
            let angle = Float(i) / Float(segments) * 2.0 * .pi
            let x = cos(angle) * radius
            let z = sin(angle) * radius
            // Bottom cap vertex
            vertices.append(AircraftVertex(
                position: SIMD3<Float>(x, -halfH, z) + offset,
                normal: SIMD3<Float>(0, -1, 0)
            ))
            // Top cap vertex
            vertices.append(AircraftVertex(
                position: SIMD3<Float>(x, halfH, z) + offset,
                normal: SIMD3<Float>(0, 1, 0)
            ))
        }

        // Cap indices
        for i in 0..<UInt16(segments) {
            let next = (i + 1) % UInt16(segments)
            // Bottom (CW from below)
            indices.append(contentsOf: [bottomCenter, capBase + next * 2, capBase + i * 2])
            // Top (CW from above)
            indices.append(contentsOf: [topCenter, capBase + i * 2 + 1, capBase + next * 2 + 1])
        }
    }

    private func appendCone(
        vertices: inout [AircraftVertex], indices: inout [UInt16],
        radius: Float, height: Float, segments: Int = 8,
        offset: SIMD3<Float> = .zero
    ) {
        let base = UInt16(vertices.count)

        // Tip vertex (pointing +Z direction, cone base at offset, tip at offset + (0,0,height))
        let tip = SIMD3<Float>(0, 0, height) + offset
        vertices.append(AircraftVertex(
            position: tip,
            normal: SIMD3<Float>(0, 0, 1)
        ))

        // Base ring vertices
        for i in 0..<segments {
            let angle = Float(i) / Float(segments) * 2.0 * .pi
            let x = cos(angle) * radius
            let y = sin(angle) * radius
            let normal = normalize(SIMD3<Float>(cos(angle), sin(angle), radius / height))
            vertices.append(AircraftVertex(
                position: SIMD3<Float>(x, y, 0) + offset,
                normal: normal
            ))
        }

        // Side triangles
        for i in 0..<UInt16(segments) {
            let next = (i + 1) % UInt16(segments)
            indices.append(contentsOf: [base, base + 1 + i, base + 1 + next])
        }
    }

    private func appendBox(
        vertices: inout [AircraftVertex], indices: inout [UInt16],
        size: SIMD3<Float>, offset: SIMD3<Float> = .zero
    ) {
        let base = UInt16(vertices.count)
        let half = size / 2.0

        // 6 faces, 4 vertices each (24 vertices total for flat shading normals)
        let faces: [(SIMD3<Float>, [SIMD3<Float>])] = [
            // normal, 4 corners
            (SIMD3<Float>(0, 0, 1), [SIMD3<Float>(-half.x, -half.y, half.z), SIMD3<Float>(half.x, -half.y, half.z), SIMD3<Float>(half.x, half.y, half.z), SIMD3<Float>(-half.x, half.y, half.z)]),
            (SIMD3<Float>(0, 0, -1), [SIMD3<Float>(half.x, -half.y, -half.z), SIMD3<Float>(-half.x, -half.y, -half.z), SIMD3<Float>(-half.x, half.y, -half.z), SIMD3<Float>(half.x, half.y, -half.z)]),
            (SIMD3<Float>(0, 1, 0), [SIMD3<Float>(-half.x, half.y, half.z), SIMD3<Float>(half.x, half.y, half.z), SIMD3<Float>(half.x, half.y, -half.z), SIMD3<Float>(-half.x, half.y, -half.z)]),
            (SIMD3<Float>(0, -1, 0), [SIMD3<Float>(-half.x, -half.y, -half.z), SIMD3<Float>(half.x, -half.y, -half.z), SIMD3<Float>(half.x, -half.y, half.z), SIMD3<Float>(-half.x, -half.y, half.z)]),
            (SIMD3<Float>(1, 0, 0), [SIMD3<Float>(half.x, -half.y, half.z), SIMD3<Float>(half.x, -half.y, -half.z), SIMD3<Float>(half.x, half.y, -half.z), SIMD3<Float>(half.x, half.y, half.z)]),
            (SIMD3<Float>(-1, 0, 0), [SIMD3<Float>(-half.x, -half.y, -half.z), SIMD3<Float>(-half.x, -half.y, half.z), SIMD3<Float>(-half.x, half.y, half.z), SIMD3<Float>(-half.x, half.y, -half.z)]),
        ]

        for (normal, corners) in faces {
            let faceBase = UInt16(vertices.count)
            for corner in corners {
                vertices.append(AircraftVertex(position: corner + offset, normal: normal))
            }
            indices.append(contentsOf: [faceBase, faceBase + 1, faceBase + 2,
                                         faceBase, faceBase + 2, faceBase + 3])
        }
    }

    private func appendSphere(
        vertices: inout [AircraftVertex], indices: inout [UInt16],
        radius: Float, segments: Int = 8,
        offset: SIMD3<Float> = .zero
    ) {
        let base = UInt16(vertices.count)
        let rings = segments / 2

        for lat in 0...rings {
            let theta = Float(lat) / Float(rings) * .pi
            let sinT = sin(theta)
            let cosT = cos(theta)

            for lon in 0...segments {
                let phi = Float(lon) / Float(segments) * 2.0 * .pi
                let x = sinT * cos(phi)
                let y = cosT
                let z = sinT * sin(phi)
                let normal = SIMD3<Float>(x, y, z)
                vertices.append(AircraftVertex(
                    position: normal * radius + offset,
                    normal: normal
                ))
            }
        }

        let stride = UInt16(segments + 1)
        for lat in 0..<UInt16(rings) {
            for lon in 0..<UInt16(segments) {
                let tl = base + lat * stride + lon
                let tr = tl + 1
                let bl = tl + stride
                let br = bl + 1
                indices.append(contentsOf: [tl, bl, tr, tr, bl, br])
            }
        }
    }

    // MARK: - Aircraft Category Builders

    private func buildJet(device: MTLDevice) -> AircraftMesh {
        var vertices: [AircraftVertex] = []
        var indices: [UInt16] = []

        // Fuselage: cylinder along Z axis (r=0.4, h=4)
        appendCylinder(vertices: &vertices, indices: &indices,
                       radius: 0.4, height: 4.0)
        // Nose cone
        appendCone(vertices: &vertices, indices: &indices,
                   radius: 0.4, height: 1.2,
                   offset: SIMD3<Float>(0, 0, 2.0))
        // Wings
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(5, 0.15, 1.5))
        // Vertical tail
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(0.15, 1.2, 1.0),
                  offset: SIMD3<Float>(0, 0.6, -1.5))
        // Horizontal stabilizer
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(2.0, 0.1, 0.6),
                  offset: SIMD3<Float>(0, 0.6, -1.8))
        // Left engine
        appendCylinder(vertices: &vertices, indices: &indices,
                       radius: 0.25, height: 0.8,
                       offset: SIMD3<Float>(-1.5, -0.3, 0.5))
        // Right engine
        appendCylinder(vertices: &vertices, indices: &indices,
                       radius: 0.25, height: 0.8,
                       offset: SIMD3<Float>(1.5, -0.3, 0.5))

        return createMesh(device: device, vertices: vertices, indices: indices)
    }

    private func buildWidebody(device: MTLDevice) -> AircraftMesh {
        var vertices: [AircraftVertex] = []
        var indices: [UInt16] = []

        // Larger fuselage
        appendCylinder(vertices: &vertices, indices: &indices,
                       radius: 0.7, height: 5.5)
        // Nose cone
        appendCone(vertices: &vertices, indices: &indices,
                   radius: 0.7, height: 1.5,
                   offset: SIMD3<Float>(0, 0, 2.75))
        // Wider wings
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(8, 0.2, 2.2))
        // Vertical tail
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(0.15, 1.5, 1.2),
                  offset: SIMD3<Float>(0, 0.8, -2.0))
        // Horizontal stabilizer
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(2.5, 0.12, 0.8),
                  offset: SIMD3<Float>(0, 0.8, -2.3))
        // 4 engines
        for x: Float in [-2.5, -1.2, 1.2, 2.5] {
            appendCylinder(vertices: &vertices, indices: &indices,
                           radius: 0.3, height: 1.0,
                           offset: SIMD3<Float>(x, -0.4, 0.5))
        }

        return createMesh(device: device, vertices: vertices, indices: indices)
    }

    private func buildHelicopter(device: MTLDevice) -> AircraftMesh {
        var vertices: [AircraftVertex] = []
        var indices: [UInt16] = []

        // Cabin (sphere)
        appendSphere(vertices: &vertices, indices: &indices,
                     radius: 0.6)
        // Tail boom
        appendCylinder(vertices: &vertices, indices: &indices,
                       radius: 0.15, height: 2.5,
                       offset: SIMD3<Float>(0, 0, -1.5))
        // Left skid
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(0.08, 0.08, 2.0),
                  offset: SIMD3<Float>(-0.5, -0.5, 0))
        // Right skid
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(0.08, 0.08, 2.0),
                  offset: SIMD3<Float>(0.5, -0.5, 0))

        return createMesh(device: device, vertices: vertices, indices: indices)
    }

    private func buildSmallProp(device: MTLDevice) -> AircraftMesh {
        var vertices: [AircraftVertex] = []
        var indices: [UInt16] = []

        // Fuselage
        appendCylinder(vertices: &vertices, indices: &indices,
                       radius: 0.25, height: 2.5)
        // Nose
        appendCone(vertices: &vertices, indices: &indices,
                   radius: 0.3, height: 0.6,
                   offset: SIMD3<Float>(0, 0, 1.25))
        // Wings
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(4, 0.08, 0.8))
        // Tail
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(0.1, 0.8, 0.6),
                  offset: SIMD3<Float>(0, 0.4, -1.0))
        // Horizontal stabilizer
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(1.5, 0.06, 0.4),
                  offset: SIMD3<Float>(0, 0.4, -1.1))

        return createMesh(device: device, vertices: vertices, indices: indices)
    }

    private func buildMilitary(device: MTLDevice) -> AircraftMesh {
        var vertices: [AircraftVertex] = []
        var indices: [UInt16] = []

        // Fuselage (box)
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(0.6, 0.4, 4.5))
        // Nose cone
        appendCone(vertices: &vertices, indices: &indices,
                   radius: 0.35, height: 1.2,
                   offset: SIMD3<Float>(0, 0, 2.25))
        // Delta wings (thin wide box approximation)
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(6, 0.1, 3.0))
        // Left angled tail
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(0.1, 1.0, 0.8),
                  offset: SIMD3<Float>(-0.5, 0.4, -1.8))
        // Right angled tail
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(0.1, 1.0, 0.8),
                  offset: SIMD3<Float>(0.5, 0.4, -1.8))

        return createMesh(device: device, vertices: vertices, indices: indices)
    }

    private func buildRegional(device: MTLDevice) -> AircraftMesh {
        // Same as jet but 0.8x scale
        var vertices: [AircraftVertex] = []
        var indices: [UInt16] = []

        let s: Float = 0.8
        // Fuselage
        appendCylinder(vertices: &vertices, indices: &indices,
                       radius: 0.4 * s, height: 4.0 * s)
        // Nose cone
        appendCone(vertices: &vertices, indices: &indices,
                   radius: 0.4 * s, height: 1.2 * s,
                   offset: SIMD3<Float>(0, 0, 2.0 * s))
        // Wings
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(5 * s, 0.15 * s, 1.5 * s))
        // Vertical tail
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(0.15 * s, 1.2 * s, 1.0 * s),
                  offset: SIMD3<Float>(0, 0.6 * s, -1.5 * s))
        // Horizontal stabilizer
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(2.0 * s, 0.1 * s, 0.6 * s),
                  offset: SIMD3<Float>(0, 0.6 * s, -1.8 * s))
        // Left engine
        appendCylinder(vertices: &vertices, indices: &indices,
                       radius: 0.25 * s, height: 0.8 * s,
                       offset: SIMD3<Float>(-1.5 * s, -0.3 * s, 0.5 * s))
        // Right engine
        appendCylinder(vertices: &vertices, indices: &indices,
                       radius: 0.25 * s, height: 0.8 * s,
                       offset: SIMD3<Float>(1.5 * s, -0.3 * s, 0.5 * s))

        return createMesh(device: device, vertices: vertices, indices: indices)
    }

    // MARK: - Spinning Part Builders

    private func buildRotor(device: MTLDevice) -> AircraftMesh {
        var vertices: [AircraftVertex] = []
        var indices: [UInt16] = []

        // Main rotor: 2 long thin boxes crossed at 90 degrees
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(6.0, 0.05, 0.2),
                  offset: SIMD3<Float>(0, 0.65, 0))
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(0.2, 0.05, 6.0),
                  offset: SIMD3<Float>(0, 0.65, 0))
        // Tail rotor: small box at tail boom tip
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(0.05, 1.2, 0.15),
                  offset: SIMD3<Float>(0, 0.1, -2.75))

        return createMesh(device: device, vertices: vertices, indices: indices)
    }

    private func buildPropeller(device: MTLDevice) -> AircraftMesh {
        var vertices: [AircraftVertex] = []
        var indices: [UInt16] = []

        // Single blade pair at the nose
        appendBox(vertices: &vertices, indices: &indices,
                  size: SIMD3<Float>(0.08, 1.2, 0.08),
                  offset: SIMD3<Float>(0, 0, 1.55))

        return createMesh(device: device, vertices: vertices, indices: indices)
    }

    // MARK: - Buffer Creation

    private func createMesh(device: MTLDevice, vertices: [AircraftVertex], indices: [UInt16]) -> AircraftMesh {
        let vb = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<AircraftVertex>.stride * vertices.count,
            options: .storageModeShared)!
        vb.label = "Aircraft Vertex Buffer"

        let ib = device.makeBuffer(
            bytes: indices,
            length: MemoryLayout<UInt16>.stride * indices.count,
            options: .storageModeShared)!
        ib.label = "Aircraft Index Buffer"

        return AircraftMesh(
            vertexBuffer: vb,
            indexBuffer: ib,
            vertexCount: vertices.count,
            indexCount: indices.count
        )
    }
}
