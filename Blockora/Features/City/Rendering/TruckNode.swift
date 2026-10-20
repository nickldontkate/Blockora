import SpriteKit
import SwiftUI

/// Makes a completed batch of production physically visible (§18): a crate
/// riding a small truck from the producing building toward the delivery point.
final class TruckNode: SKNode {
    init(resource: ResourceType) {
        super.init()

        let bed = SKShapeNode(rectOf: CGSize(width: 34, height: 18), cornerRadius: 4)
        bed.fillColor = SKColor(BlockoraPalette.craneOrange)
        bed.strokeColor = .white
        bed.lineWidth = 1.5
        addChild(bed)

        let crate = SKShapeNode(rectOf: CGSize(width: 14, height: 14), cornerRadius: 2)
        crate.fillColor = SKColor(BlockoraPalette.moduleColor(for: .storage))
        crate.strokeColor = .white
        crate.position = CGPoint(x: -2, y: 12)
        addChild(crate)

        for wheelX in [-10.0, 10.0] {
            let wheel = SKShapeNode(circleOfRadius: 5)
            wheel.fillColor = .black
            wheel.position = CGPoint(x: wheelX, y: -10)
            addChild(wheel)
        }

        let icon = SKLabelNode(text: resource.displayName.prefix(1).uppercased())
        icon.fontSize = 10
        icon.fontColor = .white
        icon.verticalAlignmentMode = .center
        icon.position = crate.position
        addChild(icon)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    func drive(job: DeliveryJob, completion: @escaping () -> Void) {
        position = job.originWorldPosition
        let duration = max(0.4, job.travelDuration)
        let move = SKAction.move(to: job.destinationWorldPosition, duration: duration)
        move.timingMode = .easeInEaseOut
        run(.sequence([move, .run(completion), .fadeOut(withDuration: 0.15), .removeFromParent()]))
    }
}
