import SceneKit
import SwiftUI

// MARK: - 3D 推币台视图（SceneKit）
struct PusherSceneView: UIViewRepresentable {
    let pusher: PusherScene3D

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = pusher.scene
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
