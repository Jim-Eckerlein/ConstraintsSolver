import Metal
import MetalKit
import simd

protocol FrameDelegate {
    func onFrame(dt: Double, t: Double)
}

class Renderer: NSObject, MTKViewDelegate {
    var frameDelegate: FrameDelegate? = .none
    private var startTime = Double(CACurrentMediaTime())
    private var lastFrameTime = Double(CACurrentMediaTime())
    
    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState
    private var depthState: MTLDepthStencilState
    
    let fovY = 1.0472
    let zNear = 0.1
    let zFar = 100.0
    var aspectRatio = 1.0
    var camera = Camera()
    
    fileprivate let grid: Grid
    private var geometries: [(Geometry, MTLBuffer)] = []
    
    init(mtkView: MTKView) {
        device = mtkView.device!
        commandQueue = device.makeCommandQueue()!
        
        mtkView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
        mtkView.colorPixelFormat = MTLPixelFormat.bgra8Unorm
        mtkView.sampleCount = 4
        mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0)
        
        let library = device.makeDefaultLibrary()!
        let vertexFunction = library.makeFunction(name: "vertexShader")
        let fragmentFunction = library.makeFunction(name: "fragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.sampleCount = mtkView.sampleCount
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = mtkView.depthStencilPixelFormat
        
        pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        
        depthState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
        
        grid = Grid(device: device, sections: 25)
        
        super.init()
    }
    
    func draw(in view: MTKView) {
        if let frameDelegate = frameDelegate {
            let currentTime = Double(CACurrentMediaTime())
            let deltaTime = currentTime - lastFrameTime
            if deltaTime > 0 {
                frameDelegate.onFrame(dt: deltaTime, t: currentTime - startTime)
            }
            lastFrameTime = currentTime
        }
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        let renderPassDescriptor = view.currentRenderPassDescriptor!
        
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        
        renderEncoder.label = "Primary Render Encoder"
        
        renderEncoder.setCullMode(.back)
        renderEncoder.setFrontFacing(.counterClockwise)
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)
        
        var uniforms = Uniforms()
        uniforms.view = camera.viewMatrix.singlePrecision
        uniforms.projection = projectionMatrix.singlePrecision
        
        renderEncoder.pushDebugGroup("Draw Geometries")
        
        for (geometry, buffer) in geometries {
            renderEncoder.pushDebugGroup("Draw Geometry '\(geometry.name)'")
            
            uniforms.model = geometry.transform.matrix.singlePrecision
            
            renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: Int(BufferIndexUniforms))
            renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: Int(BufferIndexUniforms))
            
            renderEncoder.setVertexBuffer(buffer, offset: 0, index: Int(BufferIndexVertices))

            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: geometry.vertices.count)
            
            renderEncoder.popDebugGroup()
        }
        
        grid.render(into: renderEncoder, uniforms: &uniforms)
        
        renderEncoder.popDebugGroup()
        
        renderEncoder.endEncoding()
        
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        aspectRatio = Double(size.width / size.height)
    }
    
    private var projectionMatrix: simd_double4x4 {
        let tanHalfFovy = tan(0.5 * fovY)

        var perspectiveMatrix = simd_double4x4(1)
        perspectiveMatrix[0][0] = 1 / (aspectRatio * tanHalfFovy)
        perspectiveMatrix[1][1] = 1 / (tanHalfFovy)
        perspectiveMatrix[2][2] = zFar / (zNear - zFar)
        perspectiveMatrix[2][3] = -1
        perspectiveMatrix[3][2] = -(zFar * zNear) / (zFar - zNear)
        
        return perspectiveMatrix
    }
    
    func insertGeometry(_ newGeometry: Geometry) {
        for (geometry, buffer) in geometries {
            if (geometry === newGeometry) {
                if (newGeometry.vertices.count != buffer.length / MemoryLayout<Vertex>.stride) {
                    fatalError("Cannot update geometry when the vertex count is different")
                }
                buffer.contents().copyMemory(from: newGeometry.vertices, byteCount: newGeometry.vertices.count * MemoryLayout<Vertex>.stride)
            }
        }
        
        let buffer = device.makeBuffer(bytes: newGeometry.vertices, length: newGeometry.vertices.count * MemoryLayout<Vertex>.stride, options: .cpuCacheModeWriteCombined)!
        geometries.append((newGeometry, buffer))
    }
}

fileprivate class Grid {
    let buffer: MTLBuffer
    private let vertexCount: Int
    
    init(device: MTLDevice, sections: Int) {
        var vertices: [Vertex] = []
        
        let color = simd_float3(repeating: 0.8)
        let normal = simd_float3(0, 0, 1)
        
        let fullExtent = 2 * sections + 1
        for ix in 0..<fullExtent {
            for iy in 0..<fullExtent {
                let x = Float(ix - sections) / 2
                let y = Float(iy - sections) / 2
                
                vertices.append(Vertex(position: simd_float3(x, -y, 0), normal: normal, color: color))
                vertices.append(Vertex(position: simd_float3(x, y, 0), normal: normal, color: color))
                vertices.append(Vertex(position: simd_float3(x, y, 0), normal: normal, color: color))
                vertices.append(Vertex(position: simd_float3(-x, y, 0), normal: normal, color: color))
            }
        }
        
        vertexCount = vertices.count
        buffer = device.makeBuffer(bytes: &vertices, length: vertices.count * MemoryLayout<Vertex>.stride, options: .cpuCacheModeWriteCombined)!
    }
    
    func render(into encoder: MTLRenderCommandEncoder, uniforms: inout Uniforms) {
        encoder.pushDebugGroup("Draw Grid Geometry")
        uniforms.model = simd_float4x4(1)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: Int(BufferIndexUniforms))
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: Int(BufferIndexUniforms))
        encoder.setVertexBuffer(buffer, offset: 0, index: Int(BufferIndexVertices))
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: vertexCount)
        encoder.popDebugGroup()
    }
}

extension simd_double4x4 {
    var singlePrecision: simd_float4x4 {
        simd_float4x4(columns: (
            simd_float4(Float(self[0, 0]), Float(self[0, 1]), Float(self[0, 2]), Float(self[0, 3])),
            simd_float4(Float(self[1, 0]), Float(self[1, 1]), Float(self[1, 2]), Float(self[1, 3])),
            simd_float4(Float(self[2, 0]), Float(self[2, 1]), Float(self[2, 2]), Float(self[2, 3])),
            simd_float4(Float(self[3, 0]), Float(self[3, 1]), Float(self[3, 2]), Float(self[3, 3]))
        ))
    }
}
