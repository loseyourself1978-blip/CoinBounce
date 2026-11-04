import SceneKit
import SwiftUI

// MARK: - 3D 推币台视图（SceneKit）
struct PusherSceneView: UIViewRepresentable {
    let pusher: PusherScene3D
    /// 整屏布局：3D 视图铺满全屏，机器按参考屏幕框搭建，下落区格挡按 2D 界面放置
    let layout: GameLayout

    /// 尺寸确定后按视图搭建机器
    final class CalibratingView: SCNView {
        var onLayout: ((CGSize) -> Void)?
        private var lastSize: CGSize = .zero
        override func layoutSubviews() {
            super.layoutSubviews()
            if bounds.size != lastSize, bounds.width > 0 {
                lastSize = bounds.size
                onLayout?(bounds.size)
            }
        }
    }

    func makeUIView(context: Context) -> SCNView {
        let view = CalibratingView()
        let pusher = self.pusher, layout = self.layout
        view.onLayout = { size in pusher.fit(viewSize: size, layout: layout) }
        view.scene = pusher.scene
        pusher.view = view
        view.delegate = pusher
        view.pointOfView = pusher.cameraNode
        view.isPlaying = true
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 60
        view.antialiasingMode = .multisampling2X
        pusher.updateRenderQuality()   // 发热降级时同时关掉抗锯齿
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        #if DEBUG
        view.showsStatistics = ProcessInfo.processInfo.arguments.contains("-debugSceneStats")
        #endif
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}
