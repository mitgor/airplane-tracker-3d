import MetalKit
import simd
import QuartzCore

final class Renderer: NSObject {

    // MARK: - Metal State

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState

    // MARK: - Textured Tile Pipeline States

    let texturedPipelineState: MTLRenderPipelineState
    let placeholderPipelineState: MTLRenderPipelineState
    let retroTexturedPipeline: MTLRenderPipelineState

    // MARK: - Aircraft Rendering Pipeline States

    let aircraftPipeline: MTLRenderPipelineState
    let glowPipeline: MTLRenderPipelineState
    let glowDepthStencilState: MTLDepthStencilState
    let meshLibrary: AircraftMeshLibrary
    let instanceManager: AircraftInstanceManager
    let glowTexture: MTLTexture

    // MARK: - Trail Rendering Pipeline States

    let trailPipeline: MTLRenderPipelineState
    let trailManager: TrailManager
    private let lineWidthBuffer: MTLBuffer
    private let resolutionBuffer: MTLBuffer

    // MARK: - Terrain Pipeline States

    let terrainTileManager: TerrainTileManager
    let terrainPipeline: MTLRenderPipelineState
    let terrainPlaceholderPipeline: MTLRenderPipelineState
    let retroTerrainPipeline: MTLRenderPipelineState
    let retroTerrainPlaceholderPipeline: MTLRenderPipelineState

    // MARK: - Label & Altitude Line Pipeline States

    let labelPipeline: MTLRenderPipelineState
    let altLinePipeline: MTLRenderPipelineState
    let labelManager: LabelManager

    // MARK: - Airport Labels

    let airportLabelManager: AirportLabelManager

    // MARK: - Theme

    let themeManager = ThemeManager()

    // MARK: - Selection

    let selectionManager = SelectionManager()

    /// Flight data manager set externally after init (from ContentView/MetalView)
    var flightDataManager: FlightDataManager?

    /// Fly-to camera animator set externally from MetalView Coordinator
    var flyToAnimator: FlyToAnimator?

    /// Frame counter for throttling camera target broadcasts
    private var frameCounter: Int = 0

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

        // --- Retro textured pipeline (green-tint fragment for flat tiles) ---
        let retroTexturedPipelineDesc = MTLRenderPipelineDescriptor()
        retroTexturedPipelineDesc.vertexFunction = library.makeFunction(name: "vertex_textured")
        retroTexturedPipelineDesc.fragmentFunction = library.makeFunction(name: "fragment_retro_textured")
        retroTexturedPipelineDesc.vertexDescriptor = texturedVertexDescriptor
        retroTexturedPipelineDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        retroTexturedPipelineDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        retroTexturedPipelineDesc.rasterSampleCount = metalView.sampleCount

        do {
            retroTexturedPipeline = try device.makeRenderPipelineState(descriptor: retroTexturedPipelineDesc)
        } catch {
            fatalError("Failed to create retro textured pipeline: \(error)")
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

        // --- Aircraft Mesh Library ---
        meshLibrary = AircraftMeshLibrary(device: device)

        // --- Aircraft Pipeline State ---
        let aircraftVertexDesc = MTLVertexDescriptor()
        // position: float3 at attribute 0
        aircraftVertexDesc.attributes[0].format = .float3
        aircraftVertexDesc.attributes[0].offset = 0
        aircraftVertexDesc.attributes[0].bufferIndex = Int(BufferIndexVertices.rawValue)
        // normal: float3 at attribute 1
        aircraftVertexDesc.attributes[1].format = .float3
        aircraftVertexDesc.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride  // 16 bytes (padded)
        aircraftVertexDesc.attributes[1].bufferIndex = Int(BufferIndexVertices.rawValue)
        // layout for vertices
        aircraftVertexDesc.layouts[Int(BufferIndexVertices.rawValue)].stride = MemoryLayout<AircraftVertex>.stride
        aircraftVertexDesc.layouts[Int(BufferIndexVertices.rawValue)].stepRate = 1
        aircraftVertexDesc.layouts[Int(BufferIndexVertices.rawValue)].stepFunction = .perVertex

        let aircraftPipelineDesc = MTLRenderPipelineDescriptor()
        aircraftPipelineDesc.vertexFunction = library.makeFunction(name: "aircraft_vertex")
        aircraftPipelineDesc.fragmentFunction = library.makeFunction(name: "aircraft_fragment")
        aircraftPipelineDesc.vertexDescriptor = aircraftVertexDesc
        aircraftPipelineDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        aircraftPipelineDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        aircraftPipelineDesc.rasterSampleCount = metalView.sampleCount

        do {
            aircraftPipeline = try device.makeRenderPipelineState(descriptor: aircraftPipelineDesc)
        } catch {
            fatalError("Failed to create aircraft pipeline: \(error)")
        }

        // --- Glow Pipeline State (additive blending) ---
        let glowPipelineDesc = MTLRenderPipelineDescriptor()
        glowPipelineDesc.vertexFunction = library.makeFunction(name: "glow_vertex")
        glowPipelineDesc.fragmentFunction = library.makeFunction(name: "glow_fragment")
        glowPipelineDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        glowPipelineDesc.colorAttachments[0].isBlendingEnabled = true
        glowPipelineDesc.colorAttachments[0].rgbBlendOperation = .add
        glowPipelineDesc.colorAttachments[0].alphaBlendOperation = .add
        glowPipelineDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        glowPipelineDesc.colorAttachments[0].destinationRGBBlendFactor = .one
        glowPipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        glowPipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = .one
        glowPipelineDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        glowPipelineDesc.rasterSampleCount = metalView.sampleCount

        do {
            glowPipeline = try device.makeRenderPipelineState(descriptor: glowPipelineDesc)
        } catch {
            fatalError("Failed to create glow pipeline: \(error)")
        }

        // --- Glow Depth Stencil State (read depth, no write) ---
        let glowDepthDesc = MTLDepthStencilDescriptor()
        glowDepthDesc.depthCompareFunction = .lessEqual
        glowDepthDesc.isDepthWriteEnabled = false
        guard let glowDSS = device.makeDepthStencilState(descriptor: glowDepthDesc) else {
            fatalError("Failed to create glow depth stencil state")
        }
        glowDepthStencilState = glowDSS

        // --- Glow Texture ---
        guard let gt = AircraftMeshLibrary.createGlowTexture(device: device) else {
            fatalError("Failed to create glow texture")
        }
        glowTexture = gt

        // --- Instance Manager ---
        instanceManager = AircraftInstanceManager(device: device, meshLibrary: meshLibrary)

        // --- Trail Manager ---
        trailManager = TrailManager(device: device)

        // --- Trail Pipeline State (alpha blending for fading trail tails) ---
        let trailPipelineDesc = MTLRenderPipelineDescriptor()
        trailPipelineDesc.vertexFunction = library.makeFunction(name: "trail_vertex")
        trailPipelineDesc.fragmentFunction = library.makeFunction(name: "trail_fragment")
        trailPipelineDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        trailPipelineDesc.colorAttachments[0].isBlendingEnabled = true
        trailPipelineDesc.colorAttachments[0].rgbBlendOperation = .add
        trailPipelineDesc.colorAttachments[0].alphaBlendOperation = .add
        trailPipelineDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        trailPipelineDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        trailPipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        trailPipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        trailPipelineDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        trailPipelineDesc.rasterSampleCount = metalView.sampleCount
        // No vertex descriptor needed -- reading raw buffer by vertexID

        do {
            trailPipeline = try device.makeRenderPipelineState(descriptor: trailPipelineDesc)
        } catch {
            fatalError("Failed to create trail pipeline: \(error)")
        }

        // --- Trail auxiliary buffers ---
        guard let lwb = device.makeBuffer(length: MemoryLayout<Float>.stride, options: .storageModeShared) else {
            fatalError("Failed to create line width buffer")
        }
        lwb.label = "Trail Line Width"
        lwb.contents().bindMemory(to: Float.self, capacity: 1).pointee = 3.0
        lineWidthBuffer = lwb

        guard let rb = device.makeBuffer(length: MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared) else {
            fatalError("Failed to create resolution buffer")
        }
        rb.label = "Trail Resolution"
        resolutionBuffer = rb

        // --- Label Manager ---
        labelManager = LabelManager(device: device)

        // --- Label Pipeline State (alpha blending for text billboards) ---
        let labelPipelineDesc = MTLRenderPipelineDescriptor()
        labelPipelineDesc.vertexFunction = library.makeFunction(name: "label_vertex")
        labelPipelineDesc.fragmentFunction = library.makeFunction(name: "label_fragment")
        labelPipelineDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        labelPipelineDesc.colorAttachments[0].isBlendingEnabled = true
        labelPipelineDesc.colorAttachments[0].rgbBlendOperation = .add
        labelPipelineDesc.colorAttachments[0].alphaBlendOperation = .add
        labelPipelineDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        labelPipelineDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        labelPipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        labelPipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        labelPipelineDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        labelPipelineDesc.rasterSampleCount = metalView.sampleCount

        do {
            labelPipeline = try device.makeRenderPipelineState(descriptor: labelPipelineDesc)
        } catch {
            fatalError("Failed to create label pipeline: \(error)")
        }

        // --- Altitude Line Pipeline State (alpha blending for dashed lines) ---
        let altLinePipelineDesc = MTLRenderPipelineDescriptor()
        altLinePipelineDesc.vertexFunction = library.makeFunction(name: "altline_vertex")
        altLinePipelineDesc.fragmentFunction = library.makeFunction(name: "altline_fragment")
        altLinePipelineDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        altLinePipelineDesc.colorAttachments[0].isBlendingEnabled = true
        altLinePipelineDesc.colorAttachments[0].rgbBlendOperation = .add
        altLinePipelineDesc.colorAttachments[0].alphaBlendOperation = .add
        altLinePipelineDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        altLinePipelineDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        altLinePipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        altLinePipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        altLinePipelineDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        altLinePipelineDesc.rasterSampleCount = metalView.sampleCount

        do {
            altLinePipeline = try device.makeRenderPipelineState(descriptor: altLinePipelineDesc)
        } catch {
            fatalError("Failed to create altitude line pipeline: \(error)")
        }

        // --- Terrain Tile Manager ---
        terrainTileManager = TerrainTileManager(device: device)

        // --- Terrain Vertex Descriptor ---
        // TerrainVertex layout: position(float3) at 0, texCoord(float2) at 16, normal(float3) at 32
        // Total stride: 48 bytes (simd_float3 has 16-byte alignment on Apple platforms)
        let terrainVertexDesc = MTLVertexDescriptor()
        terrainVertexDesc.attributes[0].format = .float3
        terrainVertexDesc.attributes[0].offset = 0
        terrainVertexDesc.attributes[0].bufferIndex = Int(BufferIndexVertices.rawValue)
        terrainVertexDesc.attributes[1].format = .float2
        terrainVertexDesc.attributes[1].offset = 16  // after simd_float3 (padded to 16)
        terrainVertexDesc.attributes[1].bufferIndex = Int(BufferIndexVertices.rawValue)
        terrainVertexDesc.attributes[2].format = .float3
        terrainVertexDesc.attributes[2].offset = 32  // after 16 + simd_float2(8) = 24, padded to 32 for simd_float3 alignment
        terrainVertexDesc.attributes[2].bufferIndex = Int(BufferIndexVertices.rawValue)
        terrainVertexDesc.layouts[Int(BufferIndexVertices.rawValue)].stride = MemoryLayout<TerrainVertex>.stride
        terrainVertexDesc.layouts[Int(BufferIndexVertices.rawValue)].stepRate = 1
        terrainVertexDesc.layouts[Int(BufferIndexVertices.rawValue)].stepFunction = .perVertex

        // --- Terrain Pipeline State (textured terrain with lighting) ---
        let terrainPipelineDesc = MTLRenderPipelineDescriptor()
        terrainPipelineDesc.vertexFunction = library.makeFunction(name: "terrain_vertex")
        terrainPipelineDesc.fragmentFunction = library.makeFunction(name: "terrain_fragment")
        terrainPipelineDesc.vertexDescriptor = terrainVertexDesc
        terrainPipelineDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        terrainPipelineDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        terrainPipelineDesc.rasterSampleCount = metalView.sampleCount

        do {
            terrainPipeline = try device.makeRenderPipelineState(descriptor: terrainPipelineDesc)
        } catch {
            fatalError("Failed to create terrain pipeline: \(error)")
        }

        // --- Terrain Placeholder Pipeline State (untextured terrain with lighting) ---
        let terrainPlaceholderPipelineDesc = MTLRenderPipelineDescriptor()
        terrainPlaceholderPipelineDesc.vertexFunction = library.makeFunction(name: "terrain_vertex")
        terrainPlaceholderPipelineDesc.fragmentFunction = library.makeFunction(name: "terrain_fragment_placeholder")
        terrainPlaceholderPipelineDesc.vertexDescriptor = terrainVertexDesc
        terrainPlaceholderPipelineDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        terrainPlaceholderPipelineDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        terrainPlaceholderPipelineDesc.rasterSampleCount = metalView.sampleCount

        do {
            terrainPlaceholderPipeline = try device.makeRenderPipelineState(descriptor: terrainPlaceholderPipelineDesc)
        } catch {
            fatalError("Failed to create terrain placeholder pipeline: \(error)")
        }

        // --- Retro Terrain Pipeline (green-tint terrain fragment) ---
        let retroTerrainPipelineDesc = MTLRenderPipelineDescriptor()
        retroTerrainPipelineDesc.vertexFunction = library.makeFunction(name: "terrain_vertex")
        retroTerrainPipelineDesc.fragmentFunction = library.makeFunction(name: "fragment_retro_terrain")
        retroTerrainPipelineDesc.vertexDescriptor = terrainVertexDesc
        retroTerrainPipelineDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        retroTerrainPipelineDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        retroTerrainPipelineDesc.rasterSampleCount = metalView.sampleCount

        do {
            retroTerrainPipeline = try device.makeRenderPipelineState(descriptor: retroTerrainPipelineDesc)
        } catch {
            fatalError("Failed to create retro terrain pipeline: \(error)")
        }

        // --- Retro Terrain Placeholder Pipeline ---
        let retroTerrainPlaceholderPipelineDesc = MTLRenderPipelineDescriptor()
        retroTerrainPlaceholderPipelineDesc.vertexFunction = library.makeFunction(name: "terrain_vertex")
        retroTerrainPlaceholderPipelineDesc.fragmentFunction = library.makeFunction(name: "fragment_retro_terrain_placeholder")
        retroTerrainPlaceholderPipelineDesc.vertexDescriptor = terrainVertexDesc
        retroTerrainPlaceholderPipelineDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        retroTerrainPlaceholderPipelineDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        retroTerrainPlaceholderPipelineDesc.rasterSampleCount = metalView.sampleCount

        do {
            retroTerrainPlaceholderPipeline = try device.makeRenderPipelineState(descriptor: retroTerrainPlaceholderPipelineDesc)
        } catch {
            fatalError("Failed to create retro terrain placeholder pipeline: \(error)")
        }

        // --- Airport Label Manager ---
        airportLabelManager = AirportLabelManager(device: device)

        super.init()

        // Apply initial theme to label manager
        applyThemeToLabels(themeManager.config)

        // Set up theme change callback
        themeManager.onThemeChanged = { [weak self] theme in
            self?.handleThemeChange(theme)
        }
    }

    // MARK: - Theme Change Handling

    /// Respond to theme change: clear caches, re-rasterize labels, switch tile URLs.
    private func handleThemeChange(_ theme: Theme) {
        let config = themeManager.config

        // Switch map tile URL provider and clear tile cache
        tileManager.switchTheme(theme)

        // Re-rasterize labels with new theme colors
        applyThemeToLabels(config)
        labelManager.invalidateCache()

        // Re-rasterize airport labels
        airportLabelManager.updateTheme(config)
    }

    /// Apply theme config to label manager text/bg colors.
    private func applyThemeToLabels(_ config: ThemeConfig) {
        labelManager.textColor = config.labelTextColor
        labelManager.bgColor = config.labelBgColor
        labelManager.altLineColor = config.altLineColor
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

    // MARK: - Aircraft Rendering

    /// Encode instanced aircraft body draw calls (one per category with non-zero count).
    private func encodeAircraft(encoder: MTLRenderCommandEncoder, uniformBuffer: MTLBuffer) {
        encoder.setRenderPipelineState(aircraftPipeline)
        encoder.setDepthStencilState(depthStencilState)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))

        let instanceStride = MemoryLayout<AircraftInstanceData>.stride
        let instBuffer = instanceManager.instanceBuffer(at: currentBufferIndex)

        for category in AircraftCategory.allCases {
            guard let range = instanceManager.categoryRanges[category], range.count > 0 else { continue }
            let mesh = instanceManager.meshLibrary.mesh(for: category)

            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0,
                                     index: Int(BufferIndexVertices.rawValue))
            encoder.setVertexBuffer(instBuffer, offset: range.offset * instanceStride,
                                     index: Int(BufferIndexInstances.rawValue))

            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: mesh.indexCount,
                indexType: .uint16,
                indexBuffer: mesh.indexBuffer,
                indexBufferOffset: 0,
                instanceCount: range.count
            )
        }
    }

    /// Encode instanced spinning part draw calls (rotors for helicopters, propellers for small props).
    private func encodeSpinningParts(encoder: MTLRenderCommandEncoder, uniformBuffer: MTLBuffer) {
        let instanceStride = MemoryLayout<AircraftInstanceData>.stride
        let spinBuf = instanceManager.spinBuffer(at: currentBufferIndex)

        // Helicopter rotors
        if instanceManager.helicopterCount > 0, let rotorMesh = instanceManager.meshLibrary.rotorMesh {
            encoder.setRenderPipelineState(aircraftPipeline)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
            encoder.setVertexBuffer(rotorMesh.vertexBuffer, offset: 0,
                                     index: Int(BufferIndexVertices.rawValue))
            encoder.setVertexBuffer(spinBuf, offset: instanceManager.helicopterSpinOffset * instanceStride,
                                     index: Int(BufferIndexInstances.rawValue))
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: rotorMesh.indexCount,
                indexType: .uint16,
                indexBuffer: rotorMesh.indexBuffer,
                indexBufferOffset: 0,
                instanceCount: instanceManager.helicopterCount
            )
        }

        // Propellers
        if instanceManager.propCount > 0, let propMesh = instanceManager.meshLibrary.propellerMesh {
            encoder.setRenderPipelineState(aircraftPipeline)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
            encoder.setVertexBuffer(propMesh.vertexBuffer, offset: 0,
                                     index: Int(BufferIndexVertices.rawValue))
            encoder.setVertexBuffer(spinBuf, offset: instanceManager.propSpinOffset * instanceStride,
                                     index: Int(BufferIndexInstances.rawValue))
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: propMesh.indexCount,
                indexType: .uint16,
                indexBuffer: propMesh.indexBuffer,
                indexBufferOffset: 0,
                instanceCount: instanceManager.propCount
            )
        }
    }

    // MARK: - Trail Rendering

    /// Encode trail polyline rendering with screen-space extrusion.
    private func encodeTrails(encoder: MTLRenderCommandEncoder, uniformBuffer: MTLBuffer, drawableSize: CGSize) {
        let vertexCount = trailManager.trailVertexCount(at: currentBufferIndex)
        guard vertexCount > 0 else { return }

        encoder.setRenderPipelineState(trailPipeline)
        encoder.setDepthStencilState(glowDepthStencilState)  // depth-read, no-write (semi-transparent)

        // Bind uniforms
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))

        // Bind trail vertex data
        encoder.setVertexBuffer(trailManager.trailBuffer(at: currentBufferIndex), offset: 0,
                                 index: Int(BufferIndexTrailVertices.rawValue))

        // Update and bind line width
        lineWidthBuffer.contents().bindMemory(to: Float.self, capacity: 1).pointee = trailManager.lineWidth
        encoder.setVertexBuffer(lineWidthBuffer, offset: 0, index: Int(BufferIndexModelMatrix.rawValue))

        // Update and bind resolution
        let resolution = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
        resolutionBuffer.contents().bindMemory(to: SIMD2<Float>.self, capacity: 1).pointee = resolution
        encoder.setVertexBuffer(resolutionBuffer, offset: 0, index: Int(BufferIndexInstances.rawValue))

        // Draw as triangle strip
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexCount)

        // Restore depth stencil state
        encoder.setDepthStencilState(depthStencilState)
    }

    // MARK: - Altitude Line Rendering

    /// Encode dashed altitude reference lines from aircraft to ground.
    private func encodeAltitudeLines(encoder: MTLRenderCommandEncoder, uniformBuffer: MTLBuffer) {
        let vertexCount = labelManager.altLineVertexCount(at: currentBufferIndex)
        guard vertexCount > 0 else { return }

        encoder.setRenderPipelineState(altLinePipeline)
        encoder.setDepthStencilState(depthStencilState)

        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
        encoder.setVertexBuffer(labelManager.altLineBuffer(at: currentBufferIndex), offset: 0,
                                 index: Int(BufferIndexAltLineVertices.rawValue))

        // Draw as lines (2 vertices per aircraft = one line segment each)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: vertexCount)
    }

    // MARK: - Label Rendering

    /// Encode billboard label sprites with alpha blending.
    private func encodeLabels(encoder: MTLRenderCommandEncoder, uniformBuffer: MTLBuffer) {
        let labelCount = labelManager.labelVertexCount(at: currentBufferIndex)
        guard labelCount > 0 else { return }

        encoder.setRenderPipelineState(labelPipeline)
        encoder.setDepthStencilState(glowDepthStencilState) // depth-read, no-write

        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
        encoder.setVertexBuffer(labelManager.labelBuffer(at: currentBufferIndex), offset: 0,
                                 index: Int(BufferIndexLabelInstances.rawValue))

        if let atlas = labelManager.textureAtlas {
            encoder.setFragmentTexture(atlas, index: 0)
        }

        encoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 6,
            instanceCount: labelCount
        )
    }

    // MARK: - Airport Label Rendering

    /// Encode airport ground label sprites with alpha blending.
    private func encodeAirportLabels(encoder: MTLRenderCommandEncoder, uniformBuffer: MTLBuffer) {
        let count = airportLabelManager.labelCount(at: currentBufferIndex)
        guard count > 0 else { return }

        encoder.setRenderPipelineState(labelPipeline)
        encoder.setDepthStencilState(glowDepthStencilState) // depth-read, no-write

        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
        encoder.setVertexBuffer(airportLabelManager.labelBuffer(at: currentBufferIndex), offset: 0,
                                 index: Int(BufferIndexLabelInstances.rawValue))

        if let atlas = airportLabelManager.textureAtlas {
            encoder.setFragmentTexture(atlas, index: 0)
        }

        encoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 6,
            instanceCount: count
        )
    }

    // MARK: - Glow Rendering

    /// Encode glow billboard sprites with additive blending.
    private func encodeGlow(encoder: MTLRenderCommandEncoder, uniformBuffer: MTLBuffer) {
        guard instanceManager.totalAircraftCount > 0 else { return }

        encoder.setRenderPipelineState(glowPipeline)
        encoder.setDepthStencilState(glowDepthStencilState)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
        encoder.setVertexBuffer(instanceManager.glowBuffer(at: currentBufferIndex), offset: 0,
                                 index: Int(BufferIndexGlowInstances.rawValue))
        encoder.setFragmentTexture(glowTexture, index: 0)

        encoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 6,
            instanceCount: instanceManager.totalAircraftCount
        )

        // Restore original depth stencil state for subsequent passes
        encoder.setDepthStencilState(depthStencilState)
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

            // Theme config for this frame
            let config = themeManager.config
            let isRetro = config.isWireframe

            // Timing
            let now = CACurrentMediaTime()
            let deltaTime: Float
            if lastFrameTime == 0 {
                deltaTime = 1.0 / 60.0
            } else {
                deltaTime = Float(now - lastFrameTime)
            }
            lastFrameTime = now

            // Read configurable settings from UserDefaults (written by SettingsView @AppStorage)
            let settingsTrailLength = UserDefaults.standard.integer(forKey: "trailLength")
            if settingsTrailLength > 0 {
                trailManager.maxTrailLength = settingsTrailLength
            }
            let settingsTrailWidth = UserDefaults.standard.double(forKey: "trailWidth")
            if settingsTrailWidth > 0 {
                trailManager.lineWidth = Float(settingsTrailWidth)
            }

            // Update camera
            camera.update(deltaTime: deltaTime)

            // Update fly-to animation (after camera update, before rendering)
            flyToAnimator?.update(camera: camera, deltaTime: deltaTime)

            // Broadcast camera target periodically for nearby airports (every ~30 frames)
            frameCounter += 1
            if frameCounter % 30 == 0 {
                let target = camera.target
                let targetArray: [Float] = [target.x, target.y, target.z]
                NotificationCenter.default.post(
                    name: .cameraTargetUpdated,
                    object: nil,
                    userInfo: ["target": targetArray]
                )
            }

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
            uniforms.pointee.cameraPosition = camera.position

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

            // Set clear color from theme
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
                red: config.clearColor.r, green: config.clearColor.g, blue: config.clearColor.b, alpha: 1.0
            )

            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                frameSemaphore.signal()
                return
            }
            encoder.label = "Tile Map Encoder"

            encoder.setDepthStencilState(depthStencilState)
            encoder.setFrontFacing(.clockwise)
            encoder.setCullMode(.none) // Render both sides for robustness

            // Wireframe mode for terrain and aircraft in retro theme
            if isRetro {
                encoder.setTriangleFillMode(.lines)
            }

            // Bind shared uniforms
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))

            // Draw each visible tile -- terrain mesh with elevation, or flat fallback
            let modelMatrixPtr = modelMatrixBuffer.contents().bindMemory(to: simd_float4x4.self, capacity: 1)

            for tile in visibleTiles {
                let mapTexture = tileManager.texture(for: tile)
                let terrainMesh = terrainTileManager.terrainMesh(for: tile)

                if let mesh = terrainMesh {
                    // Terrain mesh available -- render with elevation
                    encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: Int(BufferIndexVertices.rawValue))
                    encoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))

                    if let texture = mapTexture {
                        if isRetro {
                            encoder.setRenderPipelineState(retroTerrainPipeline)
                        } else {
                            encoder.setRenderPipelineState(terrainPipeline)
                        }
                        encoder.setFragmentTexture(texture, index: Int(TextureIndexColor.rawValue))
                    } else {
                        if isRetro {
                            encoder.setRenderPipelineState(retroTerrainPlaceholderPipeline)
                        } else {
                            encoder.setRenderPipelineState(terrainPlaceholderPipeline)
                        }
                    }

                    encoder.drawIndexedPrimitives(
                        type: .triangle,
                        indexCount: mesh.indexCount,
                        indexType: .uint32,
                        indexBuffer: mesh.indexBuffer,
                        indexBufferOffset: 0
                    )
                } else {
                    // No terrain mesh yet -- fall back to flat tile quad
                    encoder.setVertexBuffer(tileQuadVertexBuffer, offset: 0, index: Int(BufferIndexVertices.rawValue))

                    let modelMatrix = tileModelMatrix(for: tile)
                    modelMatrixPtr.pointee = modelMatrix
                    encoder.setVertexBuffer(modelMatrixBuffer, offset: 0, index: Int(BufferIndexModelMatrix.rawValue))

                    if let texture = mapTexture {
                        if isRetro {
                            encoder.setRenderPipelineState(retroTexturedPipeline)
                        } else {
                            encoder.setRenderPipelineState(texturedPipelineState)
                        }
                        encoder.setFragmentTexture(texture, index: Int(TextureIndexColor.rawValue))
                    } else {
                        encoder.setRenderPipelineState(placeholderPipelineState)
                    }

                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tileQuadVertexCount)
                }
            }

            // --- Aircraft Rendering ---
            let rawStates = flightDataManager?.interpolatedStates(at: now) ?? []

            // Apply altitude exaggeration from settings
            let altExag = Float(UserDefaults.standard.double(forKey: "altitudeExaggeration"))
            let states: [InterpolatedAircraftState]
            if altExag > 0 && altExag != 1.0 {
                states = rawStates.map { var s = $0; s.position.y *= altExag; return s }
            } else {
                states = rawStates
            }

            // Post aircraft count periodically (~1 second at 60fps)
            if frameCounter % 60 == 0 {
                NotificationCenter.default.post(
                    name: .aircraftCountUpdated,
                    object: nil,
                    userInfo: ["count": states.count, "time": Date(), "states": states]
                )
            }

            // Update airport labels every frame (distance-culled)
            airportLabelManager.update(bufferIndex: currentBufferIndex,
                                       cameraPosition: camera.position,
                                       themeConfig: config)

            if !states.isEmpty {
                // Follow camera: track selected aircraft position
                if let pos = selectionManager.selectedPosition(from: states) {
                    camera.followTarget = selectionManager.isFollowing ? pos : nil
                } else {
                    camera.followTarget = nil
                }

                // Tint color for retro mode
                let tint: SIMD4<Float>? = isRetro ? config.aircraftTint : nil

                instanceManager.update(states: states, bufferIndex: currentBufferIndex,
                                       deltaTime: deltaTime, time: Float(now),
                                       selectedHex: selectionManager.selectedHex,
                                       tintColor: tint)

                // Update trail buffers with current aircraft positions
                let trailTint: SIMD4<Float>? = isRetro ? config.trailTint : nil
                trailManager.update(states: states, bufferIndex: currentBufferIndex, tintColor: trailTint)

                // Update label and altitude line buffers
                labelManager.update(states: states, bufferIndex: currentBufferIndex,
                                     cameraPosition: camera.position)

                // Encode altitude lines (right after tiles, before aircraft)
                encodeAltitudeLines(encoder: encoder, uniformBuffer: uniformBuffer)

                // Encode aircraft bodies (one instanced draw per category)
                // Note: wireframe fill mode is already set for retro
                encodeAircraft(encoder: encoder, uniformBuffer: uniformBuffer)

                // Encode spinning parts (rotors + propellers)
                encodeSpinningParts(encoder: encoder, uniformBuffer: uniformBuffer)

                // Restore fill mode for everything below (trails, labels, glow)
                if isRetro {
                    encoder.setTriangleFillMode(.fill)
                }

                // Encode trail polylines (after aircraft, before glow)
                encodeTrails(encoder: encoder, uniformBuffer: uniformBuffer, drawableSize: drawableSize)

                // Encode billboard labels (after trails, before glow)
                encodeLabels(encoder: encoder, uniformBuffer: uniformBuffer)

                // Encode airport labels
                encodeAirportLabels(encoder: encoder, uniformBuffer: uniformBuffer)

                // Encode glow sprites (additive blend)
                encodeGlow(encoder: encoder, uniformBuffer: uniformBuffer)
            } else {
                // Restore fill mode even when no aircraft
                if isRetro {
                    encoder.setTriangleFillMode(.fill)
                }

                // Still render airport labels when no aircraft visible
                encodeAirportLabels(encoder: encoder, uniformBuffer: uniformBuffer)
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
