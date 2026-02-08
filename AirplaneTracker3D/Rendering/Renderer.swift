import MetalKit
import simd

final class Renderer: NSObject {

    // MARK: - Metal State

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState

    // MARK: - Textured Tile Pipeline States

    let texturedPipelineState: MTLRenderPipelineState
    let placeholderPipelineState: MTLRenderPipelineState

    // MARK: - Triple Buffering

    static let maxFramesInFlight = 3
    private let frameSemaphore = DispatchSemaphore(value: maxFramesInFlight)
    private var uniformBuffers: [MTLBuffer] = []
    private var currentBufferIndex = 0

    // MARK: - Geometry

    private let tileQuadVertexBuffer: MTLBuffer
    private let tileQuadVertexCount: Int = 6

    // MARK: - Tile Map

    let tileManager: MapTileManager
    private let coordSystem = MapCoordinateSystem.shared

    /// Per-tile model matrix buffer (reused each frame)
    private let modelMatrixBuffer: MTLBuffer

    // MARK: - Camera

    var camera = OrbitCamera()

    // MARK: - Timing

    private var lastFrameTime: CFTimeInterval = 0

    // MARK: - Zoom Tracking

    private var currentZoom: Int = 8
    private var lastZoom: Int = 8

    // MARK: - Init

    init(metalView: MTKView) {
        guard let device = metalView.device else {
            fatalError("MTKView has no Metal device")
        }
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create command queue")
        }
        self.commandQueue = queue

        // --- Shader Library ---
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to load default Metal library")
        }

        // --- Original colored vertex pipeline (kept for future use) ---
        let vertexFunction = library.makeFunction(name: "vertex_main")
        let fragmentFunction = library.makeFunction(name: "fragment_main")

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = Int(BufferIndexVertices.rawValue)
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = Int(BufferIndexVertices.rawValue)
        vertexDescriptor.layouts[Int(BufferIndexVertices.rawValue)].stride = MemoryLayout<Vertex>.stride
        vertexDescriptor.layouts[Int(BufferIndexVertices.rawValue)].stepRate = 1
        vertexDescriptor.layouts[Int(BufferIndexVertices.rawValue)].stepFunction = .perVertex

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        pipelineDescriptor.rasterSampleCount = metalView.sampleCount

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }

        // --- Textured tile vertex descriptor ---
        let texturedVertexDescriptor = MTLVertexDescriptor()
        // position: float3 at offset 0
        texturedVertexDescriptor.attributes[0].format = .float3
        texturedVertexDescriptor.attributes[0].offset = 0
        texturedVertexDescriptor.attributes[0].bufferIndex = Int(BufferIndexVertices.rawValue)
        // texCoord: float2 at offset 16 (float3 is padded to 16 bytes in stride)
        texturedVertexDescriptor.attributes[1].format = .float2
        texturedVertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        texturedVertexDescriptor.attributes[1].bufferIndex = Int(BufferIndexVertices.rawValue)
        // layout
        texturedVertexDescriptor.layouts[Int(BufferIndexVertices.rawValue)].stride = MemoryLayout<TexturedVertex>.stride
        texturedVertexDescriptor.layouts[Int(BufferIndexVertices.rawValue)].stepRate = 1
        texturedVertexDescriptor.layouts[Int(BufferIndexVertices.rawValue)].stepFunction = .perVertex

        // --- Textured pipeline state ---
        let texturedPipelineDesc = MTLRenderPipelineDescriptor()
        texturedPipelineDesc.vertexFunction = library.makeFunction(name: "vertex_textured")
        texturedPipelineDesc.fragmentFunction = library.makeFunction(name: "fragment_textured")
        texturedPipelineDesc.vertexDescriptor = texturedVertexDescriptor
        texturedPipelineDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        texturedPipelineDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        texturedPipelineDesc.rasterSampleCount = metalView.sampleCount

        do {
            texturedPipelineState = try device.makeRenderPipelineState(descriptor: texturedPipelineDesc)
        } catch {
            fatalError("Failed to create textured pipeline state: \(error)")
        }

        // --- Placeholder pipeline state ---
        let placeholderPipelineDesc = MTLRenderPipelineDescriptor()
        placeholderPipelineDesc.vertexFunction = library.makeFunction(name: "vertex_textured")
        placeholderPipelineDesc.fragmentFunction = library.makeFunction(name: "fragment_placeholder")
        placeholderPipelineDesc.vertexDescriptor = texturedVertexDescriptor
        placeholderPipelineDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        placeholderPipelineDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        placeholderPipelineDesc.rasterSampleCount = metalView.sampleCount

        do {
            placeholderPipelineState = try device.makeRenderPipelineState(descriptor: placeholderPipelineDesc)
        } catch {
            fatalError("Failed to create placeholder pipeline state: \(error)")
        }

        // --- Depth Stencil State ---
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = true
        guard let dss = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            fatalError("Failed to create depth stencil state")
        }
        depthStencilState = dss

        // --- Triple-buffered Uniform Buffers ---
        let uniformSize = MemoryLayout<Uniforms>.stride
        for _ in 0..<Renderer.maxFramesInFlight {
            guard let buffer = device.makeBuffer(length: uniformSize, options: .storageModeShared) else {
                fatalError("Failed to create uniform buffer")
            }
            buffer.label = "Uniform Buffer"
            uniformBuffers.append(buffer)
        }

        // --- Tile Quad Geometry ---
        // Unit quad at Y=0, from (0,0,0) to (1,0,1) with texture coordinates.
        // Two triangles, 6 vertices. Clockwise winding when viewed from above (+Y).
        // Metal texture coordinate origin is top-left: (0,0) = top-left, (1,1) = bottom-right.
        // Tile y=0 is north (top), so texCoord.v=0 should be at the min-Z (north) edge
        // and texCoord.v=1 at the max-Z (south) edge.
        let tileVertices: [TexturedVertex] = [
            // Triangle 1: top-left, top-right, bottom-right (north edge first)
            TexturedVertex(position: SIMD3<Float>(0, 0, 0), texCoord: SIMD2<Float>(0, 0)),
            TexturedVertex(position: SIMD3<Float>(1, 0, 0), texCoord: SIMD2<Float>(1, 0)),
            TexturedVertex(position: SIMD3<Float>(1, 0, 1), texCoord: SIMD2<Float>(1, 1)),

            // Triangle 2: top-left, bottom-right, bottom-left
            TexturedVertex(position: SIMD3<Float>(0, 0, 0), texCoord: SIMD2<Float>(0, 0)),
            TexturedVertex(position: SIMD3<Float>(1, 0, 1), texCoord: SIMD2<Float>(1, 1)),
            TexturedVertex(position: SIMD3<Float>(0, 0, 1), texCoord: SIMD2<Float>(0, 1)),
        ]

        guard let vb = device.makeBuffer(bytes: tileVertices,
                                          length: MemoryLayout<TexturedVertex>.stride * tileVertices.count,
                                          options: .storageModeShared) else {
            fatalError("Failed to create tile quad vertex buffer")
        }
        vb.label = "Tile Quad Vertices"
        tileQuadVertexBuffer = vb

        // --- Per-tile model matrix buffer (reused) ---
        guard let mmb = device.makeBuffer(length: MemoryLayout<simd_float4x4>.stride, options: .storageModeShared) else {
            fatalError("Failed to create model matrix buffer")
        }
        mmb.label = "Tile Model Matrix"
        modelMatrixBuffer = mmb

        // --- Tile Manager ---
        tileManager = MapTileManager(device: device)

        super.init()
    }

    // MARK: - Tile Rendering Helpers

    /// Build a model matrix that transforms the unit quad to the tile's world-space bounds.
    private func tileModelMatrix(for tile: TileCoordinate) -> simd_float4x4 {
        let bounds = TileCoordinate.tileBounds(tile: tile)

        // Convert geographic bounds to world-space
        let minX = coordSystem.lonToX(bounds.minLon)
        let maxX = coordSystem.lonToX(bounds.maxLon)
        // Note: latToZ has negative Z for north, so maxLat -> smaller Z
        let minZ = coordSystem.latToZ(bounds.maxLat) // north edge -> smaller Z value
        let maxZ = coordSystem.latToZ(bounds.minLat) // south edge -> larger Z value

        let scaleX = maxX - minX
        let scaleZ = maxZ - minZ

        // Scale and translate the unit quad (0,0)-(1,1) to world bounds
        var matrix = matrix_identity_float4x4
        // Scale
        matrix.columns.0.x = scaleX
        matrix.columns.2.z = scaleZ
        // Translate
        matrix.columns.3.x = minX
        matrix.columns.3.z = minZ

        return matrix
    }

    /// Determine tile radius based on zoom level (fewer tiles at high zoom for performance).
    private func tileRadius(forZoom zoom: Int) -> Int {
        switch zoom {
        case 6...7: return 4
        case 8: return 5
        case 9: return 5
        case 10: return 5
        case 11: return 4
        case 12: return 3
        default: return 4
        }
    }
}

// MARK: - MTKViewDelegate

extension Renderer: MTKViewDelegate {

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        camera.aspectRatio = Float(size.width / size.height)
    }

    func draw(in view: MTKView) {
        autoreleasepool {
            // Wait for an available buffer slot (triple buffering)
            frameSemaphore.wait()

            // Timing
            let now = CACurrentMediaTime()
            let deltaTime: Float
            if lastFrameTime == 0 {
                deltaTime = 1.0 / 60.0
            } else {
                deltaTime = Float(now - lastFrameTime)
            }
            lastFrameTime = now

            // Update camera
            camera.update(deltaTime: deltaTime)

            // Update aspect ratio
            let drawableSize = view.drawableSize
            if drawableSize.width > 0 && drawableSize.height > 0 {
                camera.aspectRatio = Float(drawableSize.width / drawableSize.height)
            }

            // Update uniforms
            let uniformBuffer = uniformBuffers[currentBufferIndex]
            let uniforms = uniformBuffer.contents().bindMemory(to: Uniforms.self, capacity: 1)
            uniforms.pointee.modelMatrix = matrix_identity_float4x4
            uniforms.pointee.viewMatrix = camera.viewMatrix
            uniforms.pointee.projectionMatrix = camera.projectionMatrix

            // Determine tile zoom level and visible tiles
            currentZoom = tileManager.zoomLevel(forCameraDistance: camera.distance)
            let centerLat = coordSystem.zToLat(camera.target.z)
            let centerLon = coordSystem.xToLon(camera.target.x)
            let radius = tileRadius(forZoom: currentZoom)
            let visibleTiles = TileCoordinate.visibleTiles(
                centerLat: centerLat,
                centerLon: centerLon,
                zoom: currentZoom,
                radius: radius
            )

            // Command buffer
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                frameSemaphore.signal()
                return
            }
            commandBuffer.label = "Frame Command Buffer"

            // Render pass
            guard let renderPassDescriptor = view.currentRenderPassDescriptor else {
                frameSemaphore.signal()
                return
            }

            // Set clear color to sky blue
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
                red: 0.529, green: 0.808, blue: 0.922, alpha: 1.0
            )

            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                frameSemaphore.signal()
                return
            }
            encoder.label = "Tile Map Encoder"

            encoder.setDepthStencilState(depthStencilState)
            encoder.setFrontFacing(.clockwise)
            encoder.setCullMode(.none) // Render both sides for robustness

            // Bind shared buffers for textured tiles
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
            encoder.setVertexBuffer(tileQuadVertexBuffer, offset: 0, index: Int(BufferIndexVertices.rawValue))

            // Draw each visible tile
            let modelMatrixPtr = modelMatrixBuffer.contents().bindMemory(to: simd_float4x4.self, capacity: 1)

            for tile in visibleTiles {
                // Compute model matrix for this tile
                let modelMatrix = tileModelMatrix(for: tile)
                modelMatrixPtr.pointee = modelMatrix
                encoder.setVertexBuffer(modelMatrixBuffer, offset: 0, index: Int(BufferIndexModelMatrix.rawValue))

                // Check for cached texture
                if let texture = tileManager.texture(for: tile) {
                    // Textured tile
                    encoder.setRenderPipelineState(texturedPipelineState)
                    encoder.setFragmentTexture(texture, index: Int(TextureIndexColor.rawValue))
                } else {
                    // Placeholder (gray) while loading
                    encoder.setRenderPipelineState(placeholderPipelineState)
                }

                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tileQuadVertexCount)
            }

            encoder.endEncoding()

            // Present and commit
            if let drawable = view.currentDrawable {
                commandBuffer.present(drawable)
            }

            let semaphore = frameSemaphore
            commandBuffer.addCompletedHandler { _ in
                semaphore.signal()
            }
            commandBuffer.commit()

            // Advance ring buffer index
            currentBufferIndex = (currentBufferIndex + 1) % Renderer.maxFramesInFlight

            // Track zoom changes
            lastZoom = currentZoom
        }
    }
}
