import SpriteKit
import SwiftUI

/// Renders one building's whole module grid and keeps it in sync with
/// `BuildingInstance` + `StructuralReport` every frame. This is the visual
/// proof of §58/§59 — a screenshot of this node is a custom modular structure,
/// never a single falling floor.
final class BuildingNode: SKNode {
    private(set) var buildingID: UUID
    private var moduleNodes: [GridPosition: ModuleNode] = [:]
    private let basePad: SKShapeNode
    private let gridLinesNode: SKNode
    private let ghostNode: SKShapeNode
    private let ghostIcon: SKLabelNode

    /// The plot's own footprint — deliberately a true square (not the old
    /// 240×150 rectangle, which didn't match the square grid cells sitting on
    /// top of it at all) so the "lot allocated for construction" reads as one
    /// consistent square shape, in and out of Construction Mode alike.
    /// `CityScene` draws the same size for a plot's empty/locked pad.
    static let footprintSize = CGSize(width: 220, height: 220)

    init(buildingID: UUID) {
        self.buildingID = buildingID
        basePad = SKShapeNode(rectOf: Self.footprintSize, cornerRadius: 20)
        gridLinesNode = SKNode()
        ghostNode = SKShapeNode(rectOf: CGSize(width: ModuleNode.cellSize - 6, height: ModuleNode.cellSize - 6), cornerRadius: 12)
        ghostIcon = SKLabelNode()
        super.init()

        basePad.zPosition = -10
        addChild(basePad)

        // Every buildable position gets its own faint square outline so the
        // grid reads as discrete tiles (§57) instead of open, ambiguous space
        // before a module ever gets dropped on it.
        gridLinesNode.zPosition = -9
        addChild(gridLinesNode)
        buildGridLines()

        ghostNode.lineWidth = 3
        ghostNode.alpha = 0.6
        ghostNode.isHidden = true
        ghostIcon.verticalAlignmentMode = .center
        ghostIcon.fontSize = 26
        ghostIcon.fontColor = .white
        ghostNode.addChild(ghostIcon)
        addChild(ghostNode)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    static func scenePoint(for position: GridPosition) -> CGPoint {
        CGPoint(x: CGFloat(position.x) * ModuleNode.cellSize, y: CGFloat(position.y) * ModuleNode.cellSize)
    }

    static func nearestGridPosition(to point: CGPoint) -> GridPosition {
        GridPosition(
            x: Int((point.x / ModuleNode.cellSize).rounded()),
            y: Int((point.y / ModuleNode.cellSize).rounded())
        )
    }

    func sync(building: BuildingInstance, structural: StructuralReport) {
        syncBasePad(for: building.buildingClass)

        var seen = Set<GridPosition>()
        for (position, instance) in building.modules {
            seen.insert(position)
            let status = structural.status(at: position)
            if let node = moduleNodes[position] {
                node.apply(instance: instance, status: status)
            } else {
                let node = ModuleNode(instance: instance)
                node.apply(instance: instance, status: status)
                node.position = Self.scenePoint(for: position)
                node.setScale(0.4)
                node.alpha = 0
                addChild(node)
                node.run(.group([.scale(to: 1, duration: 0.18), .fadeIn(withDuration: 0.12)]))
                moduleNodes[position] = node
            }
        }
        for (position, node) in moduleNodes where !seen.contains(position) {
            node.removeFromParent()
            moduleNodes.removeValue(forKey: position)
        }
    }

    func collapse(positions: Set<GridPosition>) {
        for position in positions {
            moduleNodes[position]?.playCollapseAndRemove()
            moduleNodes.removeValue(forKey: position)
        }
        let shake = SKAction.sequence([
            .moveBy(x: 5, y: 0, duration: 0.03), .moveBy(x: -10, y: 0, duration: 0.05), .moveBy(x: 5, y: 0, duration: 0.03),
        ])
        run(shake)
    }

    func pulseModule(at position: GridPosition) {
        moduleNodes[position]?.playSnapPulse()
    }

    func showGhost(at position: GridPosition, definition: ModuleDefinition, isValid: Bool) {
        ghostNode.isHidden = false
        ghostNode.position = Self.scenePoint(for: position)
        ghostNode.fillColor = SKColor(BlockoraPalette.moduleColor(for: definition.family)).withAlphaComponent(0.55)
        ghostNode.strokeColor = SKColor(isValid ? BlockoraPalette.safe : BlockoraPalette.danger)
        ghostIcon.text = ""
    }

    func hideGhost() {
        ghostNode.isHidden = true
    }

    var occupiedPositions: Set<GridPosition> { Set(moduleNodes.keys) }

    private func buildGridLines() {
        let bounds = ConstructionEngine.gridBounds
        let inset: CGFloat = 5
        let size = CGSize(width: ModuleNode.cellSize - inset, height: ModuleNode.cellSize - inset)
        for x in bounds.x {
            for y in bounds.y {
                let square = SKShapeNode(rectOf: size, cornerRadius: 10)
                square.position = Self.scenePoint(for: GridPosition(x: x, y: y))
                square.fillColor = .clear
                square.strokeColor = SKColor.white.withAlphaComponent(0.22)
                square.lineWidth = 1.5
                gridLinesNode.addChild(square)
            }
        }
    }

    private func syncBasePad(for buildingClass: BuildingClass) {
        switch buildingClass {
        case .farm:
            basePad.fillColor = SKColor(BlockoraPalette.island).withAlphaComponent(0.55)
            basePad.strokeColor = SKColor.white.withAlphaComponent(0.55)
            basePad.lineWidth = 2
        case .powerPlant:
            basePad.fillColor = SKColor(red: 0.25, green: 0.27, blue: 0.30, alpha: 0.72)
            basePad.strokeColor = SKColor(BlockoraPalette.craneOrange)
            basePad.lineWidth = 4
        case .dataCenter:
            basePad.fillColor = SKColor(red: 0.12, green: 0.23, blue: 0.45, alpha: 0.72)
            basePad.strokeColor = SKColor(red: 0.35, green: 0.78, blue: 1, alpha: 0.9)
            basePad.lineWidth = 4
        }
    }
}
