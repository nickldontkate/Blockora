import SwiftUI

/// Top HUD resource strip (§39). Kept to the resources that matter for the
/// current build order; Coins always shown first since it's the universal sink.
struct ResourceBarView: View {
    let resources: ResourceBag
    let level: Int

    private let displayOrder: [ResourceType] = [.coins, .food, .energy, .goods, .data, .blocks]

    var body: some View {
        HStack(spacing: 10) {
            levelBadge
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(displayOrder, id: \.self) { resource in
                        ResourcePill(resource: resource, amount: resources[resource] ?? 0)
                    }
                }
                .padding(.trailing, 4)
            }
            // All 6 pills plus the level badge don't fit on an iPhone-width
            // screen even scrolled all the way, so at rest the last pill sits
            // hard against the clip edge — its digit gets sliced clean off,
            // which at a glance reads as a stray "!" rather than a number
            // (confirmed by cropping an actual screenshot). A trailing fade
            // signals "there's more, swipe" instead of looking like a glitch.
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            // `BlockoraPanelTexture`'s cap insets (190/260) are sized for a
            // full-panel-sized target, not a ~50pt-tall HUD strip — same
            // failure mode as `BlockoraGameButtonStyle` originally had (see
            // its doc comment): the non-stretchable caps alone dwarf this
            // bar, so the 9-slice renders as good as invisible. Native shape
            // matches the rest of the HUD and always renders correctly.
            Capsule()
                .fill(BlockoraPalette.panelBackground)
                .overlay(Capsule().stroke(BlockoraPalette.panelBorder, lineWidth: 1))
        }
        .padding(.horizontal, 12)
    }

    private var levelBadge: some View {
        Text("Lv \(level)")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(BlockoraPalette.craneOrange, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.65), lineWidth: 1))
    }
}

private struct ResourcePill: View {
    let resource: ResourceType
    let amount: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: resource.symbolName)
                .foregroundStyle(resource == .coins ? BlockoraPalette.coinGold : .white)
            Text(formatted(amount))
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.18), lineWidth: 1))
        .animation(.default, value: amount)
    }

    private func formatted(_ value: Double) -> String {
        if value >= 1000 { return String(format: "%.1fK", value / 1000) }
        return String(Int(value))
    }
}
