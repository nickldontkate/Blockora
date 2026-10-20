import SwiftUI

/// Centralized palette matching the Blockora reference art: bright sky, warm
/// turquoise water, saturated toy-like construction colors (§36). Everything
/// in the HUD and the SpriteKit world should pull from here rather than
/// inventing one-off colors.
enum BlockoraPalette {
    static let skyTop = Color(red: 0.42, green: 0.74, blue: 0.98)
    static let skyBottom = Color(red: 0.66, green: 0.87, blue: 0.98)
    static let water = Color(red: 0.20, green: 0.75, blue: 0.78)
    static let waterDeep = Color(red: 0.09, green: 0.52, blue: 0.62)
    static let island = Color(red: 0.42, green: 0.78, blue: 0.36)
    static let islandEdge = Color(red: 0.86, green: 0.76, blue: 0.52)
    static let roadGray = Color(red: 0.55, green: 0.56, blue: 0.58)
    static let craneOrange = Color(red: 0.98, green: 0.58, blue: 0.16)
    static let coinGold = Color(red: 1.0, green: 0.79, blue: 0.15)

    static let panelBackground = Color(red: 0.06, green: 0.16, blue: 0.34).opacity(0.82)
    static let panelBorder = Color.white.opacity(0.18)

    static let safe = Color(red: 0.24, green: 0.78, blue: 0.42)
    static let warning = Color(red: 0.98, green: 0.62, blue: 0.14)
    static let danger = Color(red: 0.92, green: 0.26, blue: 0.26)

    static func moduleColor(for family: ModuleFamily) -> Color {
        switch family {
        case .foundation: return Color(red: 0.55, green: 0.42, blue: 0.30)
        case .structuralCore: return Color(red: 0.42, green: 0.46, blue: 0.53)
        case .office: return Color(red: 0.93, green: 0.58, blue: 0.28)
        case .storage: return Color(red: 0.72, green: 0.52, blue: 0.30)
        case .solarPanel: return Color(red: 0.98, green: 0.75, blue: 0.20)
        case .farmField: return Color(red: 0.47, green: 0.75, blue: 0.30)
        case .greenhouse: return Color(red: 0.35, green: 0.80, blue: 0.55)
        case .waterTank: return Color(red: 0.30, green: 0.66, blue: 0.92)
        case .processingUnit: return Color(red: 0.85, green: 0.55, blue: 0.35)
        case .powerGenerator: return Color(red: 0.95, green: 0.45, blue: 0.30)
        case .battery: return Color(red: 0.40, green: 0.55, blue: 0.95)
        case .server: return Color(red: 0.28, green: 0.52, blue: 0.95)
        case .coolingUnit: return Color(red: 0.55, green: 0.85, blue: 0.92)
        }
    }

    static func connectionColor(for state: ConnectionState) -> Color {
        switch state {
        case .safe: return safe
        case .warning: return warning
        case .danger: return danger
        }
    }
}

extension Color {
    static let blockoraSkyTop = BlockoraPalette.skyTop
}
