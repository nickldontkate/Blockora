import SwiftUI

/// XP progress toward the next level (§54), computed live from ProgressionEngine
/// — never a hand-typed percentage.
struct ProgressionHUDView: View {
    let level: Int
    let experience: Double

    private var threshold: Double { ProgressionEngine.experienceToNextLevel(from: level) }
    private var progress: Double { threshold > 0 ? min(1, experience / threshold) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Level \(level)").font(.headline).foregroundStyle(.white)
                Spacer()
                Text("\(Int(experience)) / \(Int(threshold)) XP")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
            ProgressView(value: progress)
                .tint(BlockoraPalette.craneOrange)
        }
    }
}
