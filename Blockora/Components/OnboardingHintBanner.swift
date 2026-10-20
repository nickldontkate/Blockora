import SwiftUI

/// A persistent (non-auto-dismissing) hint for the first-run tutorial
/// (`OnboardingEngine`). Unlike `SynergyToastView` this doesn't time out — it
/// stays until the player actually does the thing it's asking for, since a
/// timed-out tutorial hint would just leave a new player stuck.
struct OnboardingHintBanner: View {
    let step: OnboardingStep

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: step.iconName)
                .font(.subheadline.weight(.bold))
            Text(step.message)
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(red: 0.16, green: 0.55, blue: 0.92).opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        .padding(.horizontal, 16)
    }
}
