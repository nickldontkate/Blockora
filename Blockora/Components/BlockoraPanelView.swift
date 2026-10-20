import SwiftUI

struct BlockoraPanel<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder let content: Content

    var body: some View {
        // A 9-slice `BlockoraPanelTexture` image was tried here first, but its
        // cap insets (190/260) were sized for a full-screen panel and broke
        // the same way `BlockoraGameButtonStyle`'s did at normal panel sizes
        // (a few hundred points) — see that type's doc comment for the full
        // story. Native shape + fill renders correctly at any size.
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(BlockoraPalette.panelBackground)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(BlockoraPalette.panelBorder, lineWidth: 1))
            }
    }
}

struct BlockoraSheetBackground: View {
    var body: some View {
        // `BlockoraWorldBackground`'s asset catalog entry has no declared
        // scale, so it reports an oversized ~1672x941pt intrinsic size. Bare
        // `.resizable().scaledToFill()` still sized itself off of that instead
        // of the space this view was actually given, leaving both the image
        // and its dark overlay filling only a sliver near their own natural
        // aspect ratio, with plain unmodified sky above and below it and
        // (invisibly, per the same misplaced layout) all of this view's
        // siblings pushed off past the bottom edge. Proposing the real
        // GeometryReader size explicitly — then clipping — pins it correctly
        // regardless of the asset's own reported size.
        GeometryReader { proxy in
            Image("BlockoraWorldBackground")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay(Color(red: 0.02, green: 0.10, blue: 0.24).opacity(0.35))
        }
        .ignoresSafeArea()
    }
}
