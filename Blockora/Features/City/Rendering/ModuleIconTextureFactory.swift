import SpriteKit
import SwiftUI
import UIKit

enum ModuleIconTextureFactory {
    private static var cache: [ModuleFamily: SKTexture] = [:]

    static func texture(for family: ModuleFamily) -> SKTexture {
        if let cached = cache[family] { return cached }
        let texture = SKTexture(imageNamed: family.iconAssetName)
        texture.filteringMode = .linear
        cache[family] = texture
        return texture
    }
}
