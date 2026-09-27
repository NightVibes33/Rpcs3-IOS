import SwiftUI
import UIKit
import QuartzCore
import Metal

final class RPCS3MetalView: UIView {
    var layoutHandler: ((RPCS3MetalView) -> Void)?

    override class var layerClass: AnyClass { CAMetalLayer.self }

    var metalLayer: CAMetalLayer {
        layer as! CAMetalLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .black
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.contentsScale = UIScreen.main.scale
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? UIScreen.main.scale
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: max(1, bounds.width * scale),
            height: max(1, bounds.height * scale)
        )
        layoutHandler?(self)
    }
}

struct RPCS3MetalSurface: UIViewRepresentable {
    @ObservedObject var controller: CoreController

    func makeUIView(context: Context) -> RPCS3MetalView {
        let view = RPCS3MetalView(frame: .zero)
        view.layoutHandler = { [weak controller] view in
            controller?.registerMetalView(view)
        }
        controller.registerMetalView(view)
        return view
    }

    func updateUIView(_ uiView: RPCS3MetalView, context: Context) {
        controller.registerMetalView(uiView)
    }
}
