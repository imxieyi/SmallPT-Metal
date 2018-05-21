//
//  GameViewController.swift
//  SmallPT
//
//  Created by 谢宜 on 2018/5/21.
//  Copyright © 2018年 xieyi. All rights reserved.
//

import UIKit
import MetalKit

// Our iOS specific view controller
class GameViewController: UIViewController {

    var renderer: Renderer!
    var mtkView: MTKView!
    
    var touchX: Float = 0.0
    var touchY: Float = 0.0

    @IBOutlet weak var fpsLabel: UILabel!
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = view as? MTKView else {
            print("View of Gameview controller is not an MTKView")
            return
        }

        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported")
            return
        }
        
        mtkView.device = defaultDevice
        mtkView.backgroundColor = UIColor.black

        guard let newRenderer = Renderer(metalKitView: mtkView) else {
            print("Renderer cannot be initialized")
            return
        }

        renderer = newRenderer
        renderer.gameVC = self

        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)

        mtkView.delegate = renderer
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchX = Float((touches.first?.location(in: view).x)! * UIScreen.main.scale)
        touchY = Float((touches.first?.location(in: view).y)! * UIScreen.main.scale)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchX = Float((touches.first?.location(in: view).x)! * UIScreen.main.scale)
        touchY = Float((touches.first?.location(in: view).y)! * UIScreen.main.scale)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchX = Float((touches.first?.location(in: view).x)! * UIScreen.main.scale)
        touchY = Float((touches.first?.location(in: view).y)! * UIScreen.main.scale)
    }
    
}
