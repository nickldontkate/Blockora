import SwiftUI

/// The synergy Codex (§5) plus saved Blueprints (§28). Undiscovered synergies
/// stay obfuscated ("??? + ??? = ???") until the player actually builds them.
struct BlueprintCodexView: View {
    let session: GameSession

    var body: some View {
        ZStack {
            BlockoraSheetBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Codex")
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(.white)

                    sheetSection("Synergy Codex") {
                        VStack(alignment: .leading, spacing: 10) {
                    ForEach(SynergyCodex.all.filter { $0.unlockLevel <= session.world.player.level }) { definition in
                        let discovered = session.world.player.discoveredSynergyIDs.contains(definition.id)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(SynergyCodex.codexLine(for: definition, discovered: discovered))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            if discovered {
                                Text(definition.flavorText).font(.caption).foregroundStyle(.white.opacity(0.72))
                            }
                        }
                        .padding(10)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    }
                        }
                }

                    sheetSection("Saved Blueprints") {
                    if session.world.blueprints.isEmpty {
                        Text("Complete a design you like, then save it as a Blueprint to reuse later.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                        ForEach(session.world.blueprints) { blueprint in
                            VStack(alignment: .leading) {
                                Text(blueprint.name).font(.headline).foregroundStyle(.white)
                                Text("\(Int(blueprint.summary.efficiencyPercent))% efficient · \(blueprint.summary.synergyCount) synergies")
                                    .font(.caption).foregroundStyle(.white.opacity(0.72))
                            }
                        }
                        Text("Start a new, empty building of the same type to load one of these from Construction Mode.")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
                }
                .padding(22)
            }
        }
    }

    private func sheetSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.black)).foregroundStyle(BlockoraPalette.coinGold)
            BlockoraPanel(padding: 14) { content() }
        }
    }
}
