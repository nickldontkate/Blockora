import SpriteKit
import SwiftUI

/// A small, readable worker figure (§9) — not decoration: it appears while a
/// module is under construction and walks off once the job completes.
final class WorkerNode: SKNode {
    init(type: WorkerType) {
        super.init()

        let body = SKShapeNode(rectOf: CGSize(width: 14, height: 20), cornerRadius: 4)
        body.fillColor = SKColor(red: 0.25, green: 0.35, blue: 0.55, alpha: 1)
        body.strokeColor = .white
        body.lineWidth = 1.5
        body.position = CGPoint(x: 0, y: 10)
        addChild(body)

        let helmet = SKShapeNode(ellipseOf: CGSize(width: 16, height: 10))
        helmet.fillColor = SKColor(BlockoraPalette.craneOrange)
        helmet.strokeColor = .white
        helmet.position = CGPoint(x: 0, y: 22)
        addChild(helmet)

        let bob = SKAction.repeatForever(.sequence([
            .moveBy(x: 0, y: 3, duration: 0.35), .moveBy(x: 0, y: -3, duration: 0.35),
        ]))
        run(bob)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    func walk(to point: CGPoint, duration: TimeInterval, completion: (() -> Void)? = nil) {
        let move = SKAction.move(to: point, duration: duration)
        move.timingMode = .easeInEaseOut
        if let completion {
            run(.sequence([move, .run(completion)]))
        } else {
            run(move)
        }
    }
}
