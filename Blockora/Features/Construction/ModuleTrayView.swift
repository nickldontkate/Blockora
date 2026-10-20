import SwiftUI

/// Bottom-sheet module picker. Scrolling and placement use different zones:
/// drag from the icon, scroll from the card text or sheet body.
struct ModuleTrayView: View {
    let session: GameSession
    let dragState: ConstructionDragState
    let buildingID: UUID
    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        BlockoraPanel(padding: 10) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 10) {
                ForEach(session.availableModules(for: buildingID)) { definition in
                    ModuleTrayCard(
                        definition: definition,
                        canAfford: session.world.player.resources.canAfford(definition.placementCost),
                        isDragging: dragState.draggingDefinitionID == definition.id,
                        onDragChanged: { value in dragChanged(value, definition: definition) },
                        onDragEnded: { dragEnded(definition: definition) }
                    )
                }
            }
                .padding(2)
            }
            .frame(maxHeight: 220)
        }
        .padding(.horizontal, 12)
    }

    private func dragChanged(_ value: DragGesture.Value, definition: ModuleDefinition) {
        if !dragState.isDragging {
            dragState.begin(definitionID: definition.id)
            HapticManager.shared.moduleSnap()
        }
        dragState.screenPoint = value.location
    }

    private func dragEnded(definition: ModuleDefinition) {
        if let position = dragState.hoveredPosition, dragState.preview?.isValid == true {
            session.placeModule(buildingID: buildingID, definitionID: definition.id, at: position)
        } else {
            HapticManager.shared.actionFailed()
        }
        dragState.end()
    }
}

private struct ModuleTrayCard: View {
    let definition: ModuleDefinition
    let canAfford: Bool
    let isDragging: Bool
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            ModuleIconView(family: definition.family, size: 58)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .global)
                        .onChanged(onDragChanged)
                        .onEnded { _ in onDragEnded() }
                )

            Text(definition.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(Int(definition.placementCost[.coins] ?? 0)) coins")
                .font(.caption2)
                .foregroundStyle(canAfford ? .white.opacity(0.75) : BlockoraPalette.danger)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .opacity(isDragging ? 0.35 : (canAfford ? 1 : 0.5))
        .scaleEffect(isDragging ? 0.92 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
    }
}
