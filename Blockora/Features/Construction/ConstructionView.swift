import SwiftUI

/// The SwiftUI chrome around Construction Mode — everything here is an
/// overlay on top of the live SpriteKit world (§15), never a replacement for
/// it: closing this view reveals the same building, mid-assembly, in-world.
struct ConstructionView: View {
    let session: GameSession
    let dragState: ConstructionDragState
    let buildingID: UUID

    @State private var showSaveBlueprintPrompt = false
    @State private var blueprintName = ""
    @State private var showDemolishConfirm = false

    private var building: BuildingInstance? { session.world.buildings[buildingID] }
    private var report: BuildingReport? { session.buildingReports[buildingID] }

    private var stressedCount: Int {
        report?.structural.statuses.values.filter { $0.connectionState != .safe }.count ?? 0
    }

    private var matchingBlueprints: [Blueprint] {
        guard let building else { return [] }
        return session.world.blueprints.filter { $0.buildingClass == building.buildingClass }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if dragState.isDragging, let definitionID = dragState.draggingDefinitionID,
               let definition = ModuleCatalog.definition(for: definitionID), let preview = dragState.preview {
                PlacementPreviewView(definition: definition, preview: preview)
                    .padding(.top, 8)
            } else if let onboardingStep = session.activeOnboardingStep, OnboardingStep.constructionSteps.contains(onboardingStep) {
                // Replaces (rather than adds to) the status row so the
                // tutorial hint never makes Construction Mode's chrome any
                // taller than usual — that's what caused it to overlap the
                // building before (§ construction-mode layout fix).
                OnboardingHintBanner(step: onboardingStep)
                    .padding(.top, 8)
            } else if let report {
                statusRow(report: report)
                    .padding(.top, 8)
            }
            if building?.isEmpty == true, !matchingBlueprints.isEmpty {
                blueprintPicker
                    .padding(.top, 8)
            }
            ModuleTrayView(session: session, dragState: dragState, buildingID: buildingID)
                .padding(.top, 8)
        }
        .padding(.bottom, 10)
        .alert("Save Blueprint", isPresented: $showSaveBlueprintPrompt) {
            TextField("Name", text: $blueprintName)
            Button("Cancel", role: .cancel) { blueprintName = "" }
            Button("Save") {
                session.saveBlueprint(for: buildingID, name: blueprintName)
                blueprintName = ""
            }
        } message: {
            Text("Store this layout so you can build it again later.")
        }
        .alert("Demolish Building?", isPresented: $showDemolishConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Demolish", role: .destructive) { session.demolishBuilding(buildingID) }
        } message: {
            Text("This removes every module here. It can't be undone.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(building?.displayName ?? "Construction")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Drag a module onto the structure to connect it.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 8)
            if building?.isEmpty == false {
                headerIconButton("square.and.arrow.down") { showSaveBlueprintPrompt = true }
                headerIconButton("trash", tint: BlockoraPalette.danger) { showDemolishConfirm = true }
            }
            Button {
                session.exitConstructionMode()
            } label: {
                Text("Done")
            }
            .buttonStyle(BlockoraGameButtonStyle(compact: true))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(BlockoraPalette.panelBackground)
    }

    private func headerIconButton(_ systemImage: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.14), in: Circle())
        }
    }

    /// Structural badge plus, when something needs it, the Reinforce action —
    /// sharing one row instead of a whole extra row keeps Construction Mode's
    /// chrome short enough that the camera still has room to frame the
    /// building above it without the two overlapping (§ visual bug fix).
    private func statusRow(report: BuildingReport) -> some View {
        HStack(spacing: 10) {
            StructuralHealthBadge(report: report)
            if stressedCount > 0 {
                Button {
                    session.reinforceStressedModules(buildingID: buildingID)
                } label: {
                    Label("Reinforce (\(stressedCount))", systemImage: "shield.lefthalf.filled")
                        .font(.caption2.weight(.bold))
                }
                .buttonStyle(BlockoraGameButtonStyle(compact: true))
            }
        }
        .padding(.horizontal, 16)
    }

    private var blueprintPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(matchingBlueprints) { blueprint in
                    Button {
                        session.applyBlueprint(blueprint, to: buildingID)
                    } label: {
                        Label(blueprint.name, systemImage: "square.stack.3d.up")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(BlockoraGameButtonStyle())
                    .opacity(0.85)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
