import Foundation
import CoreGraphics
import Observation

/// The live state of a tray-to-grid drag (§8). SwiftUI's `ConstructionView`
/// writes `screenPoint` as the finger moves; `CityScene` reads it every frame,
/// converts it into a grid cell, and writes back `hoveredPosition`/`preview`
/// so the SwiftUI overlay can show the same numbers the world is highlighting.
@MainActor
@Observable
final class ConstructionDragState {
    var isDragging = false
    var draggingDefinitionID: String?
    /// Finger position in the SKView's own coordinate space (points, origin top-left).
    var screenPoint: CGPoint?
    var hoveredPosition: GridPosition?
    var preview: PlacementPreview?

    func begin(definitionID: String) {
        draggingDefinitionID = definitionID
        isDragging = true
    }

    func end() {
        isDragging = false
        draggingDefinitionID = nil
        screenPoint = nil
        hoveredPosition = nil
        preview = nil
    }
}
