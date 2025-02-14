//
//  ContentView.swift
//  Metal_LoopBlinn
//
//  Created by randomyang on 2025/1/22.
//

import SwiftUI
import MetalKit

// MARK: - Metal Render View
struct MetalView: UIViewRepresentable {
    var transformMatrix: matrix_float4x4 // Transform matrix
    var vertices: [Vertex] // 新增vertices参数
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = context.coordinator.device
        mtkView.delegate = context.coordinator
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.enableSetNeedsDisplay = true
        mtkView.isOpaque = false
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.updateTransform(matrix: transformMatrix)
        uiView.setNeedsDisplay()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self, vertices: vertices) // 传入vertices
    }
}

// Vertex data structure
struct Vertex {
    var position: SIMD3<Float>
    var uv: SIMD2<Float>
    var sign: Float
    var color: SIMD4<Float>
}

// MARK: - Metal Coordinator
extension MetalView {
    class Coordinator: NSObject, MTKViewDelegate {
        var parent: MetalView
        var device: MTLDevice!
        var commandQueue: MTLCommandQueue!
        var pipelineState: MTLRenderPipelineState!
        var vertexBuffer: MTLBuffer!
        var transformBuffer: MTLBuffer!
        var vertices: [Vertex]
        init(_ parent: MetalView, vertices: [Vertex]) {
            self.parent = parent
            self.vertices = vertices // 保存vertices
            super.init()
            initializeMetal()
        }
        
        // MARK: Metal Initialization
        func initializeMetal() {
            // 1. Create device and command queue
            guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal is not available") }
            self.device = device
            self.commandQueue = device.makeCommandQueue()
            
            // 2. Create render pipeline
            let library = device.makeDefaultLibrary()
            let vertexFunction = library?.makeFunction(name: "vertexShader")
            let fragmentFunction = library?.makeFunction(name: "fragmentShader_Quadratic")
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            // 添加混合模式配置
            let colorAttachment = pipelineDescriptor.colorAttachments[0]!
            colorAttachment.isBlendingEnabled = true
            colorAttachment.rgbBlendOperation = .add
            colorAttachment.alphaBlendOperation = .add
            colorAttachment.sourceRGBBlendFactor = .sourceAlpha
            colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
            colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            
            // 3. Configure vertex descriptor
            // Manual offset calculation due to memory alignment
            let vertexDescriptor = MTLVertexDescriptor()
            vertexDescriptor.attributes[0].format = .float3
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            
            vertexDescriptor.attributes[1].format = .float2
            vertexDescriptor.attributes[1].offset = 16 //MemoryLayout<SIMD3<Float>>.stride
            vertexDescriptor.attributes[1].bufferIndex = 0
            
            vertexDescriptor.attributes[2].format = .float
            vertexDescriptor.attributes[2].offset = 24 // MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<SIMD2<Float>>.stride
            vertexDescriptor.attributes[2].bufferIndex = 0
            
            vertexDescriptor.attributes[3].format = .float4
            vertexDescriptor.attributes[3].offset = 32 // MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<SIMD2<Float>>.stride + MemoryLayout<Float>.stride
            vertexDescriptor.attributes[3].bufferIndex = 0
            
            vertexDescriptor.layouts[0].stride = 48 // MemoryLayout<Vertex>.stride
            
            // for debug
//            print("Position offset: \(vertexDescriptor.attributes[0].offset)")
//            print("UV offset: \(vertexDescriptor.attributes[1].offset)")
//            print("Sign offset: \(vertexDescriptor.attributes[2].offset)")
//            print("Color offset: \(vertexDescriptor.attributes[3].offset)")
//            print(MemoryLayout<Vertex>.stride)
            
            pipelineDescriptor.vertexDescriptor = vertexDescriptor
            
            // 4. Create pipeline state
            do {
                pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            } catch {
                fatalError("Failed to create pipeline state: \(error)")
            }
            
            // 5. Create vertex buffer - 使用传入的vertices
            vertexBuffer = device.makeBuffer(
                bytes: vertices,
                length: MemoryLayout<Vertex>.stride * vertices.count,
                options: .storageModeShared
            )
            
            // 6. Create transform matrix buffer
            transformBuffer = device.makeBuffer(
                length: MemoryLayout<matrix_float4x4>.stride,
                options: .storageModeShared
            )
        }
        
        // MARK: Update Transform Matrix
        func updateTransform(matrix: matrix_float4x4) {
            let matrixPtr = transformBuffer.contents().assumingMemoryBound(to: matrix_float4x4.self)
            matrixPtr.pointee = matrix
        }
        
        // MARK: Rendering
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
            
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
            renderEncoder.setRenderPipelineState(pipelineState)
            
            // Calculate viewport to maintain aspect ratio
            let viewportSize = view.drawableSize
            let aspectRatio = viewportSize.width / viewportSize.height
            var viewport = MTLViewport()
            
           if aspectRatio > 1 {
                // Width greater than height
                let width = viewportSize.height
                let x = (viewportSize.width - width) / 2
                viewport = MTLViewport(originX: Double(x), originY: 0,
                                     width: Double(width), height: Double(viewportSize.height),
                                     znear: 0.0, zfar: 1.0)
            } else {
                // Height greater than width
                let height = viewportSize.width
                let y = (viewportSize.height - height) / 2
                viewport = MTLViewport(originX: 0, originY: Double(y),
                                     width: Double(viewportSize.width), height: Double(height),
                                     znear: 0.0, zfar: 1.0)
            }
            
            renderEncoder.setViewport(viewport)
            
            // Bind vertex and transform buffers
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(transformBuffer, offset: 0, index: 1)
            
            // Draw triangles
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
            renderEncoder.endEncoding()
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

import SwiftUI

struct ContentView: View {
    // MARK: Gesture States
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var scaleAnchor: CGPoint = .zero  // Scale anchor point state
    
    // MARK: Transform Matrix Calculation
    private var transformMatrix: matrix_float4x4 {
        // 1. Move to scale anchor
        let toAnchor = matrix_float4x4(
            translation: [
                Float(-scaleAnchor.x),
                Float(-scaleAnchor.y),
                0
            ]
        )
        
        // 2. Apply scale
        let scaleMatrix = matrix_float4x4(
            scale: [Float(scale), Float(scale), 1]
        )
        
        // 3. Move back to original position
        let fromAnchor = matrix_float4x4(
            translation: [
                Float(scaleAnchor.x),
                Float(scaleAnchor.y),
                0
            ]
        )
        
        // 4. Apply translation
        let translation = matrix_float4x4(
            translation: [
                Float(offset.width),
                Float(-offset.height),
                0
            ]
        )
        
        // Combine transforms in order: move to anchor, scale, move back, apply translation
        return translation * fromAnchor * scaleMatrix * toAnchor
    }

    let scaleSensitivity: CGFloat = 0.005
    let dragSensitivity: CGFloat = 0.005
    
    let vertices: [Vertex] = [
        // inner
        Vertex(position: [-0.5, -0.25, 0], uv: [0, 0], sign: 1, color: [1, 0, 0, 1]),
        Vertex(position: [0, 0, 0], uv: [0.5, 0], sign: 1, color: [1, 0, 0, 1]),
        Vertex(position: [0.5, -0.25, 0], uv: [1, 1], sign: 1, color: [1, 0, 0, 1])
    ]
    
    let vertices2: [Vertex] = [
        // outer
        Vertex(position: [-0.5, -0.25, 0], uv: [0, 0], sign: -1, color: [0, 1, 0, 1]),
        Vertex(position: [0, 0, 0], uv: [0.5, 0], sign: -1, color: [0, 1, 0, 1]),
        Vertex(position: [0.5, -0.25, 0], uv: [1, 1], sign: -1, color: [0, 1, 0, 1])
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Metal Loop-Blinn")
                .font(.title3)
                .padding()
            // MARK: Metal View
            MetalView(transformMatrix: transformMatrix, vertices: vertices)
            MetalView(transformMatrix: transformMatrix, vertices: vertices2)
            // MARK: Status Display
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Translation:")
                        .font(.caption)
                    Spacer()
                    Text("\(String(format: "%.3f", offset.width)), \(String(format: "%.3f", offset.height))")
                        .font(.caption)
                        .monospaced()
                }
                .frame(maxWidth: .infinity)
                HStack {
                    Text("Scale:")
                        .font(.caption)
                    Spacer() 
                    Text("\(String(format: "%.3f", scale))")
                        .font(.caption)
                        .monospaced()
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
        // MARK: Drag Gesture
        .gesture(
            DragGesture()
                .onChanged { value in
                    self.offset = CGSize(
                        width: self.lastOffset.width + value.translation.width * dragSensitivity,
                        height: self.lastOffset.height + value.translation.height * dragSensitivity
                    )
                }
                .onEnded { value in
                    self.offset = CGSize(
                        width: self.lastOffset.width + value.translation.width * dragSensitivity,
                        height: self.lastOffset.height + value.translation.height * dragSensitivity
                    )
                    self.lastOffset = self.offset
                }
        )
        // MARK: Scale Gesture
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    // todo: dynamic scale center
                    self.scaleAnchor = CGPoint(
                        x: 0,
                        y: 0
                    )
                    self.scale = self.lastScale * value
                }
                .onEnded { value in
                    self.lastScale = self.scale
                }
        )
        .overlay(
            Image(systemName: "hand.draw")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .padding(),
            alignment: .bottomTrailing
        )
    }
}

// MARK: Matrix Extensions
extension matrix_float4x4 {
    // Translation matrix
    init(translation: SIMD3<Float>) {
        self.init(
            [1, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 0, 1, 0],
            [translation.x, translation.y, translation.z, 1]
        )
    }
    
    // Scale matrix
    init(scale: SIMD3<Float>) {
        self.init(
            [scale.x, 0, 0, 0],
            [0, scale.y, 0, 0],
            [0, 0, scale.z, 0],
            [0, 0, 0, 1]
        )
    }
    
    // Matrix multiplication operator overload
    static func * (lhs: matrix_float4x4, rhs: matrix_float4x4) -> matrix_float4x4 {
        return matrix_multiply(lhs, rhs)
    }
}

// MARK: Preview
#Preview {
    ContentView()
}
