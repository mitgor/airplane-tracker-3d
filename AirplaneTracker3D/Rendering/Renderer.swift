import MetalKit
import simd

final class Renderer: NSObject {

    // MARK: - Metal State

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState

    // MARK: - Triple Buffering

    static let maxFramesInFlight = 3
    private let frameSemaphore = DispatchSemaphore(value: maxFramesInFlight)
    private var uniformBuffers: [MTLBuffer] = []
    private var currentBufferIndex = 0

    // MARK: - Geometry

    private let groundVertexBuffer: MTLBuffer
    private let groundVertexCount: Int

    // MARK: - Camera

    var camera = OrbitCamera()

    // MARK: - Timing

    private var lastFrameTime: CFTimeInterval = 0

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
        let vertexFunction = library.makeFunction(name: "vertex_main")
        let fragmentFunction = library.makeFunction(name: "fragment_main")

        // --- Vertex Descriptor ---
        let vertexDescriptor = MTLVertexDescriptor()
        // position: float3 at offset 0
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = Int(BufferIndexVertices.rawValue)
        // color: float4 at offset 12 (after float3)
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = Int(BufferIndexVertices.rawValue)
        // layout
        vertexDescriptor.layouts[Int(BufferIndexVertices.rawValue)].stride = MemoryLayout<Vertex>.stride
        vertexDescriptor.layouts[Int(BufferIndexVertices.rawValue)].stepRate = 1
        vertexDescriptor.layouts[Int(BufferIndexVertices.rawValue)].stepFunction = .perVertex

        // --- Pipeline State ---
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

        // --- Depth Stencil State ---
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
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

        // --- Ground Plane Geometry ---
        // Two triangles forming a quad from -500 to +500 in X and Z at Y=0
        let gray = SIMD4<Float>(0.2, 0.2, 0.2, 1.0) // dark gray #333333
        let vertices: [Vertex] = [
            Vertex(position: SIMD3<Float>(-500, 0,  500), color: gray),
            Vertex(position: SIMD3<Float>( 500, 0,  500), color: gray),
            Vertex(position: SIMD3<Float>( 500, 0, -500), color: gray),

            Vertex(position: SIMD3<Float>(-500, 0,  500), color: gray),
            Vertex(position: SIMD3<Float>( 500, 0, -500), color: gray),
            Vertex(position: SIMD3<Float>(-500, 0, -500), color: gray),
        ]
        groundVertexCount = vertices.count
        guard let vb = device.makeBuffer(bytes: vertices,
                                         length: MemoryLayout<Vertex>.stride * vertices.count,
                                         options: .storageModeShared) else {
            fatalError("Failed to create ground vertex buffer")
        }
        vb.label = "Ground Vertices"
        groundVertexBuffer = vb

        super.init()
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
            encoder.label = "Ground Plane Encoder"

            encoder.setRenderPipelineState(pipelineState)
            encoder.setDepthStencilState(depthStencilState)
            encoder.setFrontFacing(.clockwise)
            encoder.setCullMode(.back)

            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
            encoder.setVertexBuffer(groundVertexBuffer, offset: 0, index: Int(BufferIndexVertices.rawValue))
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: groundVertexCount)

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
        }
    }
}
