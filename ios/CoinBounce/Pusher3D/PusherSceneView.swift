import SceneKit
import SwiftUI

// MARK: - 3D 推币台视图（SceneKit）
struct PusherSceneView: UIViewRepresentable {
    let pusher: PusherScene3D
    /// 2D 金币直径与交接线（视图内 y），用于校准 3D 金币大小
    var coinDiameter: CGFloat = 24
    var handoffY: CGFloat = 0
    /// 下落区左右边缘（视图内 x）：交接线上 3D 台面的左右两端对齐到这里
    var fieldLeft: CGFloat = 0
    var fieldRight: CGFloat = 0
    /// 台面前沿在视图里的目标高度（投币按钮上方）
    var frontY: CGFloat? = nil

    /// 尺寸确定后校准金币大小
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
        let pusher = self.pusher, diameter = coinDiameter, handoff = handoffY
        let left = fieldLeft, right = fieldRight > fieldLeft ? fieldRight : nil, front = frontY
        view.onLayout = { [weak view] size in
            guard let view else { return }
            pusher.fit(view: view, viewSize: size, handoffY: handoff, fieldLeft: left, fieldRight: right ?? size.width - left,
                       frontY: front, coinDiameter: diameter)
        }
        view.scene = pusher.scene
        pusher.view = view
        view.delegate = pusher
        view.isPlaying = true
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 60
        view.antialiasingMode = .multisampling2X
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        #if DEBUG
        view.showsStatistics = ProcessInfo.processInfo.arguments.contains("-debugSceneStats")
        #endif
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}
