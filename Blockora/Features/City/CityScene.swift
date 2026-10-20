import SpriteKit
import SwiftUI

/// The interactive world (§15/§16): plots, buildings, workers and trucks all
/// live here. SwiftUI never draws city content itself — it only overlays HUD
/// chrome on top of this scene, per the "city is not a menu" rule.
final class CityScene: SKScene {
    var session: GameSession!
    var dragState: ConstructionDragState!

    private let worldLayer = SKNode()
    private let cameraNode = SKCameraNode()
    private var decorationNode: SKNode?
    private var buildingNodes: [UUID: BuildingNode] = [:]
    private var plotPadNodes: [UUID: SKNode] = [:]
    private var plotWorldPositions: [UUID: CGPoint] = [:]
    private var plotUnlockedState: [UUID: Bool] = [:]
    private var knownPlotIDs: Set<UUID> = []
    private var lastUpdateTime: TimeInterval?
    private var lastRenderedMode: Bool?
    private var hasSetInitialOverviewCamera = false

    /// Overview-mode pan tracking. Kept in view points (not scene/world
    /// points) since those aren't affected by the camera's own position — the
    /// thing we're busy changing — while we compute the drag.
    private var panStartViewLocation: CGPoint?
    private var panStartCameraX: CGFloat?
    private var didPanThisGesture = false
    /// Below this drag distance (in view points) a touch still counts as a
    /// tap on a plot rather than a pan, so a slightly-shaky tap doesn't get
    /// silently swallowed.
    private static let panTapThreshold: CGFloat = 10

    static let plotSpacing: CGFloat = 260
    static let plotBaseY: CGFloat = -95
    /// Fixed overview zoom (not a fit-every-plot-in scale): keeps a plot's
    /// on-screen size constant and close to the background paving's own tile
    /// scale no matter how many plots the island has grown to. The player
    /// pans sideways (see touchesMoved) to see plots that don't fit on
    /// screen, rather than everything shrinking to make room.
    static let overviewScale: CGFloat = 1.65

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(BlockoraPalette.skyBottom)
        scaleMode = .resizeFill

        addChild(worldLayer)
        camera = cameraNode
        addChild(cameraNode)

        installDecoration()
        syncPlots()
        focusOverview(animated: false)
    }

    /// The backdrop art is sized to exactly cover the screen and parented to
    /// the *camera* rather than `worldLayer`. Children of an SKCameraNode are
    /// automatically immune to the camera's own zoom (its scale both enlarges
    /// them and is divided back out by the viewport transform), so this stays
    /// pinned edge-to-edge at every zoom level instead of shrinking away and
    /// exposing bare scene background when the camera zooms out to fit more
    /// plots (§16/§36: the world must never look empty).
    private func installDecoration() {
        decorationNode?.removeFromParent()
        let decoration = WorldDecorationNode(sceneSize: size)
        decoration.zPosition = -100
        cameraNode.addChild(decoration)
        decorationNode = decoration
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // `didMove(to:)` runs before the SKView has a real frame, so `size` is
        // still (0,0) there — the *first* resize (zero → real screen size) is
        // exactly the one that must not be skipped, or the background art and
        // camera framing both end up permanently sized for an empty scene.
        guard oldSize != size else { return }
        installDecoration()
        if session?.isConstructionModeActive != true { focusOverview(animated: false) }
    }

    /// Rebuilds plot pads whenever the *set* of plot ids changes (first load,
    /// or a full world reset from Settings) — `GameWorld.newGame()` mints
    /// fresh UUIDs each time it runs, so anything cached from an earlier,
    /// throwaway world must never be trusted once the real one loads.
    /// Otherwise just keeps each pad's lock/occupied visuals current.
    private func syncPlots() {
        guard let session else { return }
        let currentIDs = Set(session.world.plots.map(\.id))
        guard currentIDs != knownPlotIDs else {
            updatePlotPadVisuals()
            return
        }

        let newlyAddedIDs = currentIDs.subtracting(knownPlotIDs)

        for node in plotPadNodes.values { node.removeFromParent() }
        plotPadNodes.removeAll()
        plotWorldPositions.removeAll()
        plotUnlockedState.removeAll()
        for node in buildingNodes.values { node.removeFromParent() }
        buildingNodes.removeAll()
        knownPlotIDs = currentIDs

        for (index, plot) in session.world.plots.enumerated() {
            let worldPosition = CGPoint(x: CGFloat(index) * Self.plotSpacing, y: Self.plotBaseY)
            plotWorldPositions[plot.id] = worldPosition
            addPlotPad(plot, at: worldPosition)
        }

        // The plot count just changed (most commonly: the island expanded
        // with a new plot) — pan to bring the new one into view instead of
        // leaving it wherever it landed off-screen. First load has no
        // "newly added" plot to single out, so just settle at the start of the row.
        if session.isConstructionModeActive != true {
            if let newPlotID = newlyAddedIDs.first, hasSetInitialOverviewCamera {
                focusOverview(revealing: newPlotID, animated: true)
            } else {
                focusOverview(animated: true)
            }
        }
    }

    private func addPlotPad(_ plot: Plot, at worldPosition: CGPoint) {
        let pad = makePlotPad(plot: plot)
        pad.position = worldPosition
        pad.isHidden = plot.buildingID != nil
        worldLayer.addChild(pad)
        plotPadNodes[plot.id] = pad
        plotUnlockedState[plot.id] = plot.isUnlocked
    }

    private func updatePlotPadVisuals() {
        guard let session else { return }
        for plot in session.world.plots {
            if plotUnlockedState[plot.id] != plot.isUnlocked, let worldPosition = plotWorldPositions[plot.id] {
                plotPadNodes[plot.id]?.removeFromParent()
                addPlotPad(plot, at: worldPosition)
            }
            plotPadNodes[plot.id]?.isHidden = plot.buildingID != nil
        }
    }

    private func makePlotPad(plot: Plot) -> SKNode {
        // Same square BuildingNode uses for its own ground pad, so a plot's
        // footprint doesn't change shape the moment something gets built on it.
        let pad = SKShapeNode(rectOf: BuildingNode.footprintSize, cornerRadius: 20)
        if !plot.isUnlocked {
            pad.fillColor = SKColor.black.withAlphaComponent(0.35)
            pad.strokeColor = SKColor.white.withAlphaComponent(0.4)
            pad.lineWidth = 2
            let lockBody = SKShapeNode(rectOf: CGSize(width: 38, height: 30), cornerRadius: 7)
            lockBody.fillColor = SKColor(BlockoraPalette.panelBackground)
            lockBody.strokeColor = .white
            lockBody.lineWidth = 2
            lockBody.position = CGPoint(x: 0, y: -6)
            pad.addChild(lockBody)

            let shackle = SKShapeNode(path: CGPath(
                roundedRect: CGRect(x: -13, y: -2, width: 26, height: 26),
                cornerWidth: 13,
                cornerHeight: 13,
                transform: nil
            ))
            shackle.fillColor = .clear
            shackle.strokeColor = .white
            shackle.lineWidth = 4
            shackle.position = CGPoint(x: 0, y: 8)
            pad.addChild(shackle)
        } else {
            pad.fillColor = SKColor.white.withAlphaComponent(0.18)
            pad.strokeColor = SKColor.white.withAlphaComponent(0.6)
            pad.lineWidth = 2
            pad.lineWidth = 2
            let plus = SKLabelNode(text: "+")
            plus.fontSize = 40
            plus.fontColor = .white
            plus.verticalAlignmentMode = .center
            pad.addChild(plus)
        }
        return pad
    }

    // MARK: - Camera

    private func focusOverview(animated: Bool) {
        let x = hasSetInitialOverviewCamera ? cameraNode.position.x : 0
        hasSetInitialOverviewCamera = true
        move(camera: CGPoint(x: clampOverviewCameraX(x), y: 0), scale: Self.overviewScale, animated: animated)
    }

    private func focusOverview(revealing plotID: UUID, animated: Bool) {
        let x = plotWorldPositions[plotID]?.x ?? cameraNode.position.x
        move(camera: CGPoint(x: clampOverviewCameraX(x), y: 0), scale: Self.overviewScale, animated: animated)
    }

    /// Keeps the overview camera from panning past the first/last plot —
    /// there's nothing beyond the row to see, so scrolling further would just
    /// show empty background.
    private func clampOverviewCameraX(_ x: CGFloat) -> CGFloat {
        let plotCount = max(session?.world.plots.count ?? 1, 1)
        let minX: CGFloat = 0
        let maxX = CGFloat(plotCount - 1) * Self.plotSpacing
        guard minX < maxX else { return minX }
        return min(max(x, minX), maxX)
    }

    private func focusConstruction(on plotID: UUID, animated: Bool) {
        guard let base = plotWorldPositions[plotID] else { return }
        // Low y-offset (was 120) so the foundation row sits well above the
        // SwiftUI chrome docked at the bottom of the screen — that chrome
        // grew taller as Construction Mode gained more actions, and the old
        // offset let the ground row render right underneath/behind it.
        let target = CGPoint(x: base.x, y: base.y - 20)
        move(camera: target, scale: 0.85, animated: animated)
    }

    private func move(camera target: CGPoint, scale: CGFloat, animated: Bool) {
        if animated {
            cameraNode.run(.group([
                .move(to: target, duration: 0.45),
                .scale(to: scale, duration: 0.45),
            ]))
        } else {
            cameraNode.position = target
            cameraNode.setScale(scale)
        }
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdateTime = currentTime }
        guard let session else { return }
        let dt = lastUpdateTime.map { currentTime - $0 } ?? 0
        if dt > 0, dt < 1 { session.tick(deltaSeconds: dt) }

        syncPlots()
        syncMode()
        syncBuildings()
        syncDrag()
        processSceneEvents()
    }

    private func syncMode() {
        guard let session else { return }
        let active = session.isConstructionModeActive
        guard active != lastRenderedMode else { return }
        lastRenderedMode = active
        if active, let buildingID = session.activeBuildingID, let building = session.world.buildings[buildingID] {
            focusConstruction(on: building.plotID, animated: true)
        } else {
            focusOverview(animated: true)
        }
    }

    private func syncBuildings() {
        guard let session else { return }
        for (plotID, plot) in zip(session.world.plots.map(\.id), session.world.plots) {
            guard let buildingID = plot.buildingID, let building = session.world.buildings[buildingID] else { continue }
            let node: BuildingNode
            if let existing = buildingNodes[buildingID] {
                node = existing
            } else {
                node = BuildingNode(buildingID: buildingID)
                node.position = plotWorldPositions[plotID] ?? .zero
                worldLayer.addChild(node)
                buildingNodes[buildingID] = node
            }
            guard let report = session.buildingReports[buildingID] else { continue }
            node.sync(building: building, structural: report.structural)
        }

        // A building can now disappear mid-session (demolished, not just
        // never-placed), so its node must be cleaned up the same frame or a
        // ghost structure keeps rendering on an otherwise-empty plot.
        for (buildingID, node) in buildingNodes where session.world.buildings[buildingID] == nil {
            node.removeFromParent()
            buildingNodes.removeValue(forKey: buildingID)
        }
    }

    private func syncDrag() {
        guard let session, let dragState, session.isConstructionModeActive,
              let buildingID = session.activeBuildingID,
              let buildingNode = buildingNodes[buildingID] else {
            return
        }
        guard dragState.isDragging, let definitionID = dragState.draggingDefinitionID, let screenPoint = dragState.screenPoint,
              let definition = ModuleCatalog.definition(for: definitionID) else {
            buildingNode.hideGhost()
            return
        }
        let scenePoint = convertPoint(fromView: screenPoint)
        let localPoint = convert(scenePoint, to: buildingNode)
        let gridPosition = BuildingNode.nearestGridPosition(to: localPoint)
        let preview = session.preview(buildingID: buildingID, definitionID: definitionID, at: gridPosition)
        dragState.hoveredPosition = gridPosition
        dragState.preview = preview
        buildingNode.showGhost(at: gridPosition, definition: definition, isValid: preview?.isValid ?? false)
    }

    private func processSceneEvents() {
        guard let session else { return }
        for event in session.consumeSceneEvents() {
            switch event {
            case .structuralCollapse(let buildingID, let positions):
                buildingNodes[buildingID]?.collapse(positions: positions)
            case .moduleCompleted(let buildingID, let position):
                buildingNodes[buildingID]?.pulseModule(at: position)
            case .delivery(let buildingID, let job):
                spawnTruck(from: buildingID, job: job)
            default:
                break
            }
        }
    }

    private func spawnTruck(from buildingID: UUID, job: DeliveryJob) {
        guard let origin = buildingNodes[buildingID]?.position else { return }
        let destination = CGPoint(x: origin.x, y: Self.plotBaseY - 90)
        let routedJob = DeliveryJob(
            id: job.id, resource: job.resource, amount: job.amount,
            originWorldPosition: origin, destinationWorldPosition: destination, speed: job.speed
        )
        let truck = TruckNode(resource: job.resource)
        worldLayer.addChild(truck)
        truck.drive(job: routedJob) { }
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let session else { return }
        let scenePoint = touch.location(in: worldLayer)

        if session.isConstructionModeActive, let buildingID = session.activeBuildingID, let buildingNode = buildingNodes[buildingID] {
            if dragState?.isDragging == true { return }
            let localPoint = convert(scenePoint, to: buildingNode)
            let position = BuildingNode.nearestGridPosition(to: localPoint)
            let cellDistance = hypot(localPoint.x - CGFloat(position.x) * ModuleNode.cellSize, localPoint.y - CGFloat(position.y) * ModuleNode.cellSize)
            if cellDistance < ModuleNode.cellSize * 0.5, session.world.buildings[buildingID]?.module(at: position) != nil {
                session.removeModule(buildingID: buildingID, at: position)
            }
            return
        }

        // Overview mode now sits at a fixed zoom (not fit-to-all-plots), so a
        // touch here might be the start of a sideways pan rather than a tap —
        // wait for touchesEnded to decide which, based on how far it moved.
        guard let view else { return }
        panStartViewLocation = touch.location(in: view)
        panStartCameraX = cameraNode.position.x
        didPanThisGesture = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let session, !session.isConstructionModeActive,
              let view, let startLocation = panStartViewLocation, let startCameraX = panStartCameraX else { return }
        let currentLocation = touch.location(in: view)
        let dx = currentLocation.x - startLocation.x
        if !didPanThisGesture, abs(dx) > Self.panTapThreshold { didPanThisGesture = true }
        guard didPanThisGesture else { return }
        // Dragging right should slide the *content* right (finger-follow),
        // which means moving the camera left — hence the negative sign.
        cameraNode.position.x = clampOverviewCameraX(startCameraX - dx * cameraNode.xScale)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let session else { return }
        defer { panStartViewLocation = nil; panStartCameraX = nil }
        guard !session.isConstructionModeActive else { return }
        guard !didPanThisGesture else { return }

        let scenePoint = touch.location(in: worldLayer)
        for (plotID, worldPosition) in plotWorldPositions {
            let half = CGPoint(x: BuildingNode.footprintSize.width / 2, y: BuildingNode.footprintSize.height / 2)
            let rect = CGRect(x: worldPosition.x - half.x, y: worldPosition.y - half.y, width: BuildingNode.footprintSize.width, height: BuildingNode.footprintSize.height)
            if rect.contains(scenePoint) {
                session.requestPlotInteraction(plotID)
                return
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        panStartViewLocation = nil
        panStartCameraX = nil
    }
}
