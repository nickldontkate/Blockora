import SwiftUI

struct ProfileView: View {
    let session: GameSession

    var body: some View {
        ZStack {
            BlockoraSheetBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Profile")
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(.white)

                    BlockoraPanel {
                        ProgressionHUDView(level: session.world.player.level, experience: session.world.player.experience)
                    }

                    section("Workforce") {
                        VStack(spacing: 10) {
                    ForEach(session.world.workers) { worker in
                        HStack {
                            Image(systemName: worker.type.symbolName)
                                .foregroundStyle(BlockoraPalette.coinGold)
                                .frame(width: 24)
                            Text(worker.name).font(.subheadline.weight(.bold))
                            Spacer()
                            Text(worker.isAvailable ? "Idle" : "Working")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(worker.isAvailable ? .white.opacity(0.7) : BlockoraPalette.safe)
                        }
                        .foregroundStyle(.white)
                    }
                        }
                }

                    section("Resources") {
                        VStack(spacing: 10) {
                    ForEach(ResourceType.allCases) { resource in
                        HStack {
                            Image(systemName: resource.symbolName)
                                .foregroundStyle(resource == .coins ? BlockoraPalette.coinGold : .white)
                                .frame(width: 24)
                            Text(resource.displayName).font(.subheadline.weight(.bold))
                            Spacer()
                            Text("\(Int(session.world.player.resources[resource] ?? 0))")
                                .font(.caption.weight(.heavy))
                        }
                        .foregroundStyle(.white)
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
            Text(title.uppercased()).font(.caption.weight(.black)).foregroundStyle(BlockoraPalette.coinGold)
            BlockoraPanel(padding: 14) { content() }
        }
    }
}
