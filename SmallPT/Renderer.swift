//
//  Renderer.swift
//  SmallPT
//
//  Created by 谢宜 on 2018/5/21.
//  Copyright © 2018年 xieyi. All rights reserved.
//

// Our platform independent renderer class

import Metal
import MetalKit

class Renderer: NSObject, MTKViewDelegate {
    
    public let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState
    
    weak var gameVC: GameViewController!
    
    let minFrameTime: TimeInterval
    
    init?(metalKitView: MTKView) {
        self.device = metalKitView.device!
        guard let queue = self.device.makeCommandQueue() else { return nil }
        commandQueue = queue
        
        let library = device.makeDefaultLibrary()
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        
        let constants = MTLFunctionConstantValues()
        let bounds = metalKitView.bounds
        let scale = UIScreen.main.scale
        var width = Float(bounds.width * scale)
        var height = Float(bounds.height * scale)
        constants.setConstantValue(&width, type: MTLDataType.float, index: 0)
        constants.setConstantValue(&height, type: MTLDataType.float, index: 1)
        
        minFrameTime = 1 / TimeInterval(metalKitView.preferredFramesPerSecond)
        
        pipelineDescriptor.vertexFunction = library?.makeFunction(name: "vertex_main")
        pipelineDescriptor.fragmentFunction = try! library?.makeFunction(name: "fragment_main", constantValues: constants)
        pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        
        super.init()
    }
    
    var lastFrameTimestamp = Date().timeIntervalSinceReferenceDate
    
    func draw(in view: MTKView) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        guard let passDescriptor = view.currentRenderPassDescriptor else { return }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        let vertexData: [Float] = [ -1, -1, 0, 1, 0, 0,
                                    1, -1, 0, 0, 1, 0,
                                    1,  1, 0, 0, 0, 1,
                                    -1, -1, 0, 1, 0, 0,
                                    -1, 1, 0, 0, 1, 0,
                                    1,  1, 0, 0, 0, 1 ]
        encoder.setVertexBytes(vertexData, length: vertexData.count * MemoryLayout<Float>.stride, index: 0)
        let variables: [Float] = [ Float(arc4random() % 100000), gameVC.touchX, gameVC.touchY]
        encoder.setVertexBytes(variables, length: 3 * MemoryLayout<Float>.stride, index: 1)
        encoder.setRenderPipelineState(pipelineState)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.addCompletedHandler { (_) in
            DispatchQueue.main.async {
                let timestamp = Date().timeIntervalSinceReferenceDate
                let timediff = timestamp - self.lastFrameTimestamp
                if timediff < self.minFrameTime {
                    return
                }
                self.gameVC?.fpsLabel.text = String(format: "%.1f fps\t%.1f ms", 1.0 / timediff, timediff * 1000)
                self.lastFrameTimestamp = timestamp
            }
        }
        commandBuffer.commit()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }
    
}
