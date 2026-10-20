import SwiftUI

/// The cooperative global build (§31). Progress here is tracked locally and
/// clearly labeled as such (§59: no fake production values) — contributing
/// spends real resources and moves a real bar, but the total isn't yet shared
/// across players until the city connects to the Blockora servers.
struct WorldProjectView: View {
    let session: GameSession

    private var project: WorldProjectState { session.world.worldProject ?? .skybridge() }

    var body: some View {
        NavigationStack {
            ZStack {
                BlockoraSheetBackground()
                ScrollView {
                    VStack(spacing: 20) {
                        Image(systemName: "building.columns.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(BlockoraPalette.craneOrange)
                        Text(project.name)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        Text(project.flavorText)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        if project.isComplete {
                            Text("Complete! Thanks for building.")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(BlockoraPalette.safe)
                        }

                        BlockoraPanel(padding: 16) {
                            VStack(spacing: 14) {
                                ForEach(Array(project.goal.keys), id: \.self) { resource in
                                    ContributionRow(session: session, project: project, resource: resource)
                                }
                            }
                        }
                        .padding(.horizontal, 16)

                        Text("Local progress for now — this will sync with every player's city once Blockora connects to its servers.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.vertical, 24)
                }
            }
            .navigationTitle("World Project")
        }
    }
}

private struct ContributionRow: View {
    let session: GameSession
    let project: WorldProjectState
    let resource: ResourceType

    private var ratio: Double { WorldProjectEngine.ratio(project, for: resource) }
    private var goalAmount: Double { project.goal[resource] ?? 0 }
    private var contributedAmount: Double { project.contributed[resource] ?? 0 }
    private var available: Double { session.world.player.resources[resource] ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: resource.symbolName)
                Text(resource.displayName).font(.subheadline.weight(.bold))
                Spacer()
                Text("\(Int(contributedAmount)) / \(Int(goalAmount))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .foregroundStyle(.white)

            ProgressView(value: ratio)
                .tint(BlockoraPalette.craneOrange)

            if !project.isComplete {
                HStack(spacing: 8) {
                    ForEach([50.0, 200.0], id: \.self) { amount in
                        let canGive = available >= amount
                        Button("+\(Int(amount))") {
                            session.contributeToWorldProject(resource, amount: amount)
                        }
                        .font(.caption.weight(.bold))
                        .buttonStyle(BlockoraGameButtonStyle())
                        .disabled(!canGive)
                        .opacity(canGive ? 1 : 0.5)
                    }
                }
            }
        }
    }
}
