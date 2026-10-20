import SwiftUI

/// A glossy yellow/orange pill button matching the reference art's palette.
///
/// This was originally a 9-slice `BlockoraButtonTexture` image, but
/// `resizable(capInsets:)` proved unreliable at the sizes this app actually
/// needs it at (a ~44pt-tall compact tab icon or a List-row "Accept" button):
/// the fixed cap regions are specified in the source image's own coordinate
/// space, and whenever a button's rendered size undercuts them the 9-slice
/// collapses into a squashed sliver instead of a pill — reproduced even after
/// correcting the asset's scale metadata and shrinking the insets repeatedly.
/// A native shape+gradient reproduces the same look and renders correctly at
/// any size, in any container (List rows included), with no image at all.
struct BlockoraGameButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .caption2.weight(.heavy) : .subheadline.weight(.heavy))
            .foregroundStyle(Color(red: 0.42, green: 0.16, blue: 0.02))
            .padding(.horizontal, compact ? 8 : 18)
            .padding(.vertical, compact ? 7 : 10)
            .frame(minHeight: compact ? 48 : 44)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.87, blue: 0.25),
                                Color(red: 1.0, green: 0.63, blue: 0.08),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(
                        Capsule()
                            .fill(Color.white.opacity(0.55))
                            .mask(alignment: .top) {
                                LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
                                    .frame(maxHeight: .infinity, alignment: .top)
                            }
                            .padding(3)
                    )
                    .overlay(Capsule().strokeBorder(Color(red: 0.16, green: 0.55, blue: 0.92), lineWidth: 2.5))
                    .brightness(configuration.isPressed ? -0.08 : 0)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
