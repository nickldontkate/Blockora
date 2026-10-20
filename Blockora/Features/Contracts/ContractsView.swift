import SwiftUI

/// City Contracts (§22) — demand fulfilment, not trading (§21). Every action
/// here calls straight into GameSession/EconomyEngine; nothing on this screen
/// is a static mockup.
struct ContractsView: View {
    let session: GameSession

    var body: some View {
        ZStack {
            BlockoraSheetBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Contracts")
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(.white)
                        .shadow(color: .blue.opacity(0.8), radius: 2, x: 0, y: 2)

                    let activeEvents = WorldEventEngine.activeEvents(session.world.worldEvents, at: Date())
                    if !activeEvents.isEmpty {
                        section("Active Events") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(activeEvents) { event in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.title)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(.white)
                                        Text(event.flavorText)
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.72))
                                    }
                                }
                            }
                        }
                    }

                    section("Market Demand") {
                        VStack(spacing: 10) {
                            ForEach(MarketDemand.current(events: session.world.worldEvents, at: Date()), id: \.resource) { level in
                                HStack {
                                    ResourceIcon(resource: level.resource)
                                    Text(level.resource.displayName)
                                        .font(.subheadline.weight(.bold))
                                    Spacer()
                                    Text(level.label)
                                        .font(.caption.weight(.heavy))
                                        .foregroundStyle(level.multiplier > 1 ? BlockoraPalette.safe : .white.opacity(0.75))
                                }
                                .foregroundStyle(.white)
                            }
                        }
                    }

                    section("City Contracts") {
                        VStack(spacing: 12) {
                            ForEach(session.world.contracts) { contract in
                                ContractRow(session: session, contract: contract)
                            }
                        }
                    }
                }
                .padding(22)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.black))
                .foregroundStyle(BlockoraPalette.coinGold)
            BlockoraPanel(padding: 14) { content() }
        }
    }
}

private struct ContractRow: View {
    let session: GameSession
    let contract: Contract

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(contract.title)
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
            Text(contract.flavorText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))

            HStack(spacing: 12) {
                ForEach(Array(contract.requiredResources.keys), id: \.self) { resource in
                    resourceAmount(resource, contract.requiredResources[resource] ?? 0)
                }
                Image(systemName: "arrow.right")
                    .foregroundStyle(.white.opacity(0.65))
                ForEach(Array(contract.rewardResources.keys), id: \.self) { resource in
                    resourceAmount(resource, contract.rewardResources[resource] ?? 0, prefix: "+")
                }
            }

            actionButton
        }
        .padding(12)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private func resourceAmount(_ resource: ResourceType, _ amount: Double, prefix: String = "") -> some View {
        HStack(spacing: 4) {
            ResourceIcon(resource: resource, size: 18)
            Text("\(prefix)\(Int(amount))")
                .font(.caption.weight(.heavy))
                .foregroundStyle(prefix.isEmpty ? .white : BlockoraPalette.safe)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch contract.status {
        case .available:
            Button("Accept") { session.acceptContract(contract.id) }
                .buttonStyle(BlockoraGameButtonStyle())
        case .accepted:
            let canComplete = EconomyEngine.canComplete(contract, playerResources: session.world.player.resources)
            Button(canComplete ? "Deliver" : "Need more resources") { session.completeContract(contract.id) }
                .buttonStyle(BlockoraGameButtonStyle())
                .disabled(!canComplete)
        case .completed:
            Text("Completed").font(.caption.weight(.heavy)).foregroundStyle(BlockoraPalette.safe)
        case .expired:
            Text("Expired").font(.caption.weight(.heavy)).foregroundStyle(.white.opacity(0.6))
        }
    }
}

private struct ResourceIcon: View {
    let resource: ResourceType
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: resource.symbolName)
            .font(.system(size: size * 0.58, weight: .black))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(iconColor, in: RoundedRectangle(cornerRadius: size * 0.22))
    }

    private var iconColor: Color {
        switch resource {
        case .coins: return BlockoraPalette.coinGold
        case .food: return BlockoraPalette.safe
        case .energy: return Color(red: 0.10, green: 0.55, blue: 1)
        case .goods: return BlockoraPalette.craneOrange
        case .data: return Color(red: 0.18, green: 0.72, blue: 1)
        case .blocks: return Color(red: 0.50, green: 0.62, blue: 1)
        }
    }
}
