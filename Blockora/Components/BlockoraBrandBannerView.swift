import SwiftUI

struct BlockoraBrandBannerView: View {
    var body: some View {
        Image("BlockoraWelcomeArt")
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .aspectRatio(1972 / 798, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.28), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 8)
        .padding(.horizontal, 14)
    }
}
