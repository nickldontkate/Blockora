import SwiftUI

/// The live numbers shown while dragging a module (§8): structural impact and
/// production delta, updated every frame from `ConstructionDragState`.
struct PlacementPreviewView: View {
    let definition: ModuleDefinition
    let preview: PlacementPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PLACE \(definition.displayName.uppercased())")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.7))

            if preview.productionDelta.isEmpty {
                Text("No production change")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            } else {
                HStack(spacing: 14) {
                    ForEach(ResourceType.allCases.filter { preview.productionDelta[$0] != nil }, id: \.self) { resource in
                        let amount = preview.productionDelta[resource] ?? 0
                        Label("\(amount > 0 ? "+" : "")\(Int(amount))/h", systemImage: resource.symbolName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(amount >= 0 ? BlockoraPalette.safe : BlockoraPalette.danger)
                    }
                }
            }

            HStack(spacing: 6) {
                Text("Structure:")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(Int(preview.structuralHealthBefore * 100))%")
                    .foregroundStyle(.white.opacity(0.7))
                Image(systemName: "arrow.right")
                    .foregroundStyle(.white.opacity(0.5))
                Text("\(Int(preview.structuralHealthAfter * 100))%")
                    .foregroundStyle(preview.structuralHealthAfter < preview.structuralHealthBefore ? BlockoraPalette.warning : BlockoraPalette.safe)
            }
            .font(.caption.weight(.semibold))

            if !preview.isValid {
                Text(preview.reasons.first ?? "Can't place here")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BlockoraPalette.danger)
            }
        }
        .padding(14)
        .frame(maxWidth: 280, alignment: .leading)
        .background(BlockoraPalette.panelBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(preview.isValid ? BlockoraPalette.safe.opacity(0.6) : BlockoraPalette.danger.opacity(0.7), lineWidth: 1.5))
    }
}
