import SpriteKit
import SwiftUI
import UIKit

/// Static ambient art behind the interactive SpriteKit world (§16/§36).
final class WorldDecorationNode: SKNode {
    init(sceneSize: CGSize) {
        super.init()

        let background = SKSpriteNode(imageNamed: "BlockoraWorldBackground")
        background.zPosition = -100
        let verticalOffset = sceneSize.height * 0.15
        background.position = CGPoint(x: 0, y: verticalOffset)
        // Shifting the image up to better frame the skyline moves its bottom
        // edge up by the same amount, so plain cover-scaling against
        // `sceneSize` left a gap at the bottom of the screen (the scene's
        // flat background color showing through). Covering
        // `sceneSize.height + 2 * verticalOffset` instead keeps the shifted
        // image's edges outside the viewport on both sides regardless of size.
        let neededHeight = sceneSize.height + 2 * verticalOffset
        let scale = max(sceneSize.width / background.size.width, neededHeight / background.size.height)
        background.size = CGSize(width: background.size.width * scale, height: background.size.height * scale)
        addChild(background)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }
}
