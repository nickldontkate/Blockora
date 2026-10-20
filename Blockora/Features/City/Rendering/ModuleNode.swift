import SpriteKit
import SwiftUI

/// The world-space representation of one placed module: a colored, rounded
/// block with a function-coded icon (§38) and a connection-state border that
/// reads green/orange/red without relying on color alone — a small warning
/// glyph appears too (§57, don't communicate status by color alone).
final class ModuleNode: SKNode {
    static let cellSize: CGFloat = 72

    private let body: SKShapeNode
    private let icon: SKSpriteNode
    private let warningBadge: SKLabelNode
    private let constructionOverlay: SKShapeNode
    private let progressBar: SKShapeNode

    private(set) var moduleID: UUID
    private(set) var gridPosition: GridPosition

    init(instance: ModuleInstance) {
        moduleID = instance.id
        gridPosition = instance.position
        let size = CGSize(width: Self.cellSize - 6, height: Self.cellSize - 6)

        body = SKShapeNode(rectOf: size, cornerRadius: 12)
        icon = SKSpriteNode()
        warningBadge = SKLabelNode(text: "!")
        constructionOverlay = SKShapeNode(rectOf: size, cornerRadius: 12)
        progressBar = SKShapeNode(rectOf: CGSize(width: size.width - 12, height: 6), cornerRadius: 3)

        super.init()

        body.lineWidth = 3
        body.strokeColor = .white
        addChild(body)

        // Kept a few points inside `size` (not equal to it) so the icon never
        // pokes past the rounded corners of its own square cell (§57: every
        // module must read as one clean, self-contained tile).
        icon.size = CGSize(width: size.width - 10, height: size.height - 10)
        addChild(icon)

        warningBadge.fontSize = 16
        warningBadge.fontColor = .white
        warningBadge.verticalAlignmentMode = .center
        warningBadge.horizontalAlignmentMode = .center
        warningBadge.position = CGPoint(x: size.width / 2 - 10, y: size.height / 2 - 10)
        warningBadge.isHidden = true
        addChild(warningBadge)

        constructionOverlay.fillColor = SKColor.black.withAlphaComponent(0.45)
        constructionOverlay.strokeColor = .clear
        constructionOverlay.isHidden = true
        addChild(constructionOverlay)

        progressBar.fillColor = .white
        progressBar.strokeColor = .clear
        progressBar.position = CGPoint(x: 0, y: -size.height / 2 + 10)
        progressBar.isHidden = true
        addChild(progressBar)

        apply(instance: instance)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("use init(instance:)") }

    func apply(instance: ModuleInstance, status: StructuralModuleStatus? = nil) {
        gridPosition = instance.position
        guard let definition = instance.definition else { return }

        let color = SKColor(BlockoraPalette.moduleColor(for: definition.family))
        body.fillColor = color
        icon.texture = ModuleIconTextureFactory.texture(for: definition.family)

        if !instance.isBuilt {
            constructionOverlay.isHidden = false
            progressBar.isHidden = false
            let width = (body.frame.width - 12) * CGFloat(instance.constructionProgress)
            progressBar.path = CGPath(
                roundedRect: CGRect(x: -width / 2, y: -3, width: max(width, 0.001), height: 6),
                cornerWidth: 3, cornerHeight: 3, transform: nil
            )
            body.strokeColor = .white
            warningBadge.isHidden = true
        } else {
            constructionOverlay.isHidden = true
            progressBar.isHidden = true
            let connectionState = status?.connectionState ?? .safe
            let isOnline = status?.isOnline ?? true
            let strokeColor = SKColor(BlockoraPalette.connectionColor(for: connectionState))
            body.strokeColor = strokeColor
            body.lineWidth = connectionState == .safe ? 3 : 5
            warningBadge.isHidden = connectionState != .danger
            body.alpha = isOnline ? 1.0 : 0.55
        }
    }

    func playSnapPulse() {
        let up = SKAction.scale(to: 1.12, duration: 0.08)
        let down = SKAction.scale(to: 1.0, duration: 0.12)
        run(.sequence([up, down]))
    }

    func playCollapseAndRemove() {
        let shake = SKAction.sequence([
            .moveBy(x: 4, y: 0, duration: 0.03), .moveBy(x: -8, y: 0, duration: 0.05), .moveBy(x: 8, y: 0, duration: 0.05), .moveBy(x: -4, y: 0, duration: 0.03),
        ])
        let fall = SKAction.group([
            .moveBy(x: 0, y: -140, duration: 0.5),
            .rotate(byAngle: .pi * 0.6, duration: 0.5),
            .fadeOut(withDuration: 0.5),
        ])
        run(.sequence([shake, fall, .removeFromParent()]))
    }
}
