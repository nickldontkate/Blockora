import SwiftUI

/// Building-wide structural summary (§6). Never color-only: a label and,
/// once any module is stressed, an explicit word ("Stable"/"Stressed"/
/// "Overload") ride alongside the color (§57).
struct StructuralHealthBadge: View {
    let report: BuildingReport

    private var worstState: ConnectionState {
        report.structural.statuses.values.map(\.connectionState).max { lhs, rhs in
            rank(lhs) < rank(rhs)
        } ?? .safe
    }

    private func rank(_ state: ConnectionState) -> Int {
        switch state {
        case .safe: return 0
        case .warning: return 1
        case .danger: return 2
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: worstState == .safe ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
            Text("\(Int(report.structural.overallHealthPercent * 100))% \(worstState.displayName)")
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(BlockoraPalette.connectionColor(for: worstState).opacity(0.85), in: Capsule())
    }
}
