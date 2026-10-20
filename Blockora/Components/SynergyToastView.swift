import SwiftUI

/// Transient banner for discovery moments (§5/§33): synergies, contracts,
/// level-ups. Auto-dismisses; never blocks input to the world underneath.
struct SynergyToastView: View {
    let event: GameEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.bold))
                if let subtitle { Text(subtitle).font(.caption) }
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(accentColor, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8, y: 4)
        .padding(.horizontal, 16)
    }

    private var iconName: String {
        switch event {
        case .synergyDiscovered: return "sparkles"
        case .contractCompleted: return "checkmark.seal.fill"
        case .levelUp: return "arrow.up.circle.fill"
        case .worldEventStarted: return "globe.americas.fill"
        default: return "bell.fill"
        }
    }

    private var accentColor: Color {
        switch event {
        case .synergyDiscovered: return Color(red: 0.55, green: 0.35, blue: 0.85)
        case .contractCompleted: return BlockoraPalette.safe
        case .levelUp: return BlockoraPalette.craneOrange
        case .worldEventStarted: return Color(red: 0.15, green: 0.5, blue: 0.85)
        default: return BlockoraPalette.panelBackground
        }
    }

    private var title: String {
        switch event {
        case .synergyDiscovered(let occurrence):
            return "New Synergy: \(SynergyCodex.definition(for: occurrence.definitionID)?.displayName ?? "")"
        case .contractCompleted(let contract):
            return "Contract Complete: \(contract.title)"
        case .levelUp(let level):
            return "Level Up! You're now Level \(level)"
        case .worldEventStarted(let worldEvent):
            return "World Event: \(worldEvent.title)"
        default:
            return ""
        }
    }

    private var subtitle: String? {
        switch event {
        case .synergyDiscovered(let occurrence):
            return SynergyCodex.definition(for: occurrence.definitionID)?.flavorText
        case .contractCompleted(let contract):
            return "+\(Int(contract.rewardResources[.coins] ?? 0)) coins"
        case .worldEventStarted(let worldEvent):
            return worldEvent.flavorText
        default:
            return nil
        }
    }
}
