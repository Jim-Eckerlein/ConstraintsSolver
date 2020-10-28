import Metal
import MetalKit
import simd

protocol FrameDelegate {
    func onFrame(dt: Float, t: Float)
}

class Renderer: NSObject, MTKViewDelegate {
    
    var frameDelegate: FrameDelegate? = .none
    var startTime = Float(CACurrentMediaTime())
    var lastFrameTime = Float(CACurrentMediaTime())
    
    public let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState
    var depthState: MTLDepthStencilState
    
    var aspectRatio: Float = 1
    var viewOrbitAzimuth: Float = .pi * 2 / 3
    var viewOrbitElevation: Float = .pi * 1 / 8
    var viewOrbitRadius = Float(4)
    var viewPanning = simd_float3()
    
    var geometries: [Geometry] = []
    
    var vertexBuffer: MTLBuffer
    var vertices: UnsafeMutablePointer<Vertex>
    var grid: Geometry
    
    var currentVertexCount = 0
    static let maximalVertexCount = 1024
    
    init(metalKitView: MTKView) {
        device = metalKitView.device!
        commandQueue = device.makeCommandQueue()!
        
        metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
        metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        metalKitView.sampleCount = 1
        
        let library = device.makeDefaultLibrary()!
        
        let vertexFunction = library.makeFunction(name: "vertexShader")
        let fragmentFunction = library.makeFunction(name: "fragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.sampleCount = metalKitView.sampleCount
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Unable to compile render pipeline state: \(error)")
        }
        
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        
        depthState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
        
        vertexBuffer = device.makeBuffer(length: Renderer.maximalVertexCount * MemoryLayout<Vertex>.stride, options: .cpuCacheModeWriteCombined)!
        vertices = vertexBuffer.contents().bindMemory(to: Vertex.self, capacity: Renderer.maximalVertexCount)
        
        let gridSideLength = 20
        let gridVertexCount = (gridSideLength + 1) * 4
        grid = Geometry(name: "Grid", vertices: UnsafeMutableBufferPointer(start: vertices, count: gridVertexCount))
        currentVertexCount += gridVertexCount
        
        for i in 0...gridSideLength {
            let fixed = Float(gridSideLength / 2)
            let offset = Float(i - gridSideLength / 2)
            
            grid[4 * i].position.x = offset
            grid[4 * i].position.y = fixed
            grid[4 * i].color = Color.white.rgb
            grid[4 * i].normal = .e3
            grid[4 * i + 1].position.x = offset
            grid[4 * i + 1].position.y = -fixed
            grid[4 * i + 1].color = Color.white.rgb
            grid[4 * i + 1].normal = .e3
            
            grid[4 * i + 2].position.x = fixed
            grid[4 * i + 2].position.y = offset
            grid[4 * i + 2].color = Color.white.rgb
            grid[4 * i + 2].normal = .e3
            grid[4 * i + 3].position.x = -fixed
            grid[4 * i + 3].position.y = offset
            grid[4 * i + 3].color = Color.white.rgb
            grid[4 * i + 3].normal = .e3
        }
        
        super.init()
    }
    
    func draw(in view: MTKView) {
        if let frameDelegate = frameDelegate {
            let currentTime = Float(CACurrentMediaTime())
            frameDelegate.onFrame(dt: currentTime - lastFrameTime, t: currentTime - startTime)
            lastFrameTime = currentTime
        }
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        let renderPassDescriptor = view.currentRenderPassDescriptor!
        renderPassDescriptor.colorAttachments[0].clearColor = .init(red: 0.01, green: 0.01, blue: 0.01, alpha: 0.0)
        
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        
        renderEncoder.label = "Primary Render Encoder"
        
        renderEncoder.setCullMode(.back)
        renderEncoder.setFrontFacing(.counterClockwise)
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)
        
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: Int(BufferIndexVertices))
        
        var viewTransform = Transform.look(azimuth: viewOrbitAzimuth, elevation: viewOrbitElevation, radius: viewOrbitRadius)
        viewTransform.translation -= viewPanning
        
        var uniforms = Uniforms(
            rotation: .identity,
            translation: .zero,
            viewRotation: simd_float3x3(viewTransform.rotation),
            viewTranslation: viewTransform.translation,
            viewPosition: viewTransform.inverse().apply(to: simd_float3()),
            projection: projectionMatrix()
        )
        
        renderEncoder.pushDebugGroup("Draw Geometries")
        
        renderEncoder.pushDebugGroup("Draw Grid")
        
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: Int(BufferIndexUniforms))
        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: Int(BufferIndexUniforms))

        renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: grid.vertices.count)
        
        renderEncoder.popDebugGroup()
        
        for geometry in geometries {
            renderEncoder.pushDebugGroup("Draw Geometry '\(geometry.name)'")
            
            uniforms.rotation = simd_float3x3(geometry.transform.rotation)
            uniforms.translation = geometry.transform.translation
            
            renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: Int(BufferIndexUniforms))
            renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: Int(BufferIndexUniforms))

            let vertexStart = geometry.vertices.baseAddress! - vertices
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: vertexStart, vertexCount: geometry.vertices.count)
            
            renderEncoder.popDebugGroup()
        }
        
        renderEncoder.popDebugGroup()
        
        renderEncoder.endEncoding()
        
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        aspectRatio = Float(size.width / size.height)
    }
    
    func projectionMatrix() -> simd_float4x4 {
        let fovY = Float(1.0472)
        let ys = 1 / tanf(fovY * 0.5)
        let xs = ys / aspectRatio
        let nearZ = Float(0.1)
        let farZ = Float(100)
        let zs = farZ / (nearZ - farZ)
        
        return simd_float4x4(columns: (
            simd_float4(xs, 0, 0, 0),
            simd_float4(0, ys, 0, 0),
            simd_float4(0, 0, zs, -1),
            simd_float4(0, 0, zs * nearZ, 0)
        ))
    }
    
    func makeGeometry(name: String, vertexCount: Int) -> Geometry {
        if currentVertexCount + vertexCount >= Renderer.maximalVertexCount {
            fatalError("Vertex buffer is out of memory")
        }
        
        let pointer = UnsafeMutableBufferPointer(start: vertices.advanced(by: currentVertexCount), count: vertexCount)
        currentVertexCount += vertexCount
        
        let geometry = Geometry(name: name, vertices: pointer)
        geometries.append(geometry)
        return geometry
    }
}
