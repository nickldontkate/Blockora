import SwiftUI
import SpriteKit

/// Hosts `CityScene` and forwards raw finger position during a tray drag so
/// the scene can move its ghost node (§8). This view intentionally does none
/// of the game rendering itself — it is a thin SpriteKit host, honoring the
/// "city is not a menu, the world is the interface" rule (§15).
struct CityView: UIViewRepresentable {
    let session: GameSession
    let dragState: ConstructionDragState

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        #if DEBUG
        view.showsFPS = false
        view.showsNodeCount = false
        #endif

        let scene = CityScene(size: UIScreen.main.bounds.size)
        scene.session = session
        scene.dragState = dragState
        scene.scaleMode = .resizeFill
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        // GameSession is @Observable and CityScene reads it directly every
        // frame in its own update loop, so no manual diffing is needed here.
    }
}
