import SwiftUI

struct ModuleIconView: View {
    let family: ModuleFamily
    var size: CGFloat = 56

    var body: some View {
        Image(family.iconAssetName)
            .resizable()
            .scaledToFit()
            .padding(size * 0.04)
        .frame(width: size, height: size)
    }
}
