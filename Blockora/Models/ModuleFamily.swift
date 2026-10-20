import Foundation

/// The functional "family" a module belongs to. Drives visuals (§38), synergy
/// pattern matching (§44) and which building classes may use it.
enum ModuleFamily: String, Codable, CaseIterable {
    // Structural staples — usable across every building class.
    case foundation
    case structuralCore
    case office
    case storage
    case solarPanel

    // Farm family (vertical slice 1, §12).
    case farmField
    case greenhouse
    case waterTank
    case processingUnit

    // Power Plant family (vertical slice 2, §51).
    case powerGenerator
    case battery

    // Data Center family (vertical slice 3, §13/§52).
    case server
    case coolingUnit

    var displayName: String {
        switch self {
        case .foundation: return "Foundation"
        case .structuralCore: return "Structural Core"
        case .office: return "Office"
        case .storage: return "Storage"
        case .solarPanel: return "Solar Panel"
        case .farmField: return "Field"
        case .greenhouse: return "Greenhouse"
        case .waterTank: return "Water Tank"
        case .processingUnit: return "Processing Unit"
        case .powerGenerator: return "Power Generator"
        case .battery: return "Battery"
        case .server: return "Server"
        case .coolingUnit: return "Cooling Unit"
        }
    }

    /// Function silhouette used for module icons in the world and tray.
    var iconSymbolName: String {
        switch self {
        case .foundation: return "square.grid.3x3.fill"
        case .structuralCore: return "building.columns.fill"
        case .office: return "person.2.fill"
        case .storage: return "shippingbox.fill"
        case .solarPanel: return "sun.max.fill"
        case .farmField: return "leaf.fill"
        case .greenhouse: return "camera.macro"
        case .waterTank: return "drop.fill"
        case .processingUnit: return "gearshape.2.fill"
        case .powerGenerator: return "bolt.fill"
        case .battery: return "battery.100"
        case .server: return "server.rack"
        case .coolingUnit: return "wind"
        }
    }

    var symbolName: String { iconSymbolName }

    var iconAssetName: String {
        switch self {
        case .foundation: return "ModuleIconFoundation"
        case .structuralCore: return "ModuleIconStructuralCore"
        case .office: return "ModuleIconOffice"
        case .storage: return "ModuleIconStorage"
        case .solarPanel: return "ModuleIconSolarPanel"
        case .farmField: return "ModuleIconFarmField"
        case .greenhouse: return "ModuleIconGreenhouse"
        case .waterTank: return "ModuleIconWaterTank"
        case .processingUnit: return "ModuleIconProcessingUnit"
        case .powerGenerator: return "ModuleIconPowerGenerator"
        case .battery: return "ModuleIconBattery"
        case .server: return "ModuleIconServer"
        case .coolingUnit: return "ModuleIconCoolingUnit"
        }
    }

    var isStructuralStaple: Bool {
        switch self {
        case .foundation, .structuralCore, .office, .storage, .solarPanel: return true
        default: return false
        }
    }
}

/// The functional roles required from a neighboring module before this module
/// can go online (§4). Kept as an option set so future modules can require
/// combinations without new engine code.
struct ConnectionRequirement: OptionSet, Codable, Hashable {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }

    /// Needs to be adjacent (directly or transitively through other powered
    /// modules) to a positive net-energy source.
    static let power = ConnectionRequirement(rawValue: 1 << 0)
    /// Needs to be adjacent to a Structural Core.
    static let core = ConnectionRequirement(rawValue: 1 << 1)
}

enum BuildingClass: String, Codable, CaseIterable {
    case farm
    case powerPlant
    case dataCenter

    var displayName: String {
        switch self {
        case .farm: return "Farm"
        case .powerPlant: return "Power Plant"
        case .dataCenter: return "Data Center"
        }
    }
}

enum WorkerType: String, Codable, CaseIterable {
    case builder
    case engineer
    case electrician
    case technician

    var displayName: String { rawValue.capitalized }
    var symbolName: String {
        switch self {
        case .builder: return "hammer.fill"
        case .engineer: return "wrench.and.screwdriver.fill"
        case .electrician: return "bolt.badge.a.fill"
        case .technician: return "cpu.fill"
        }
    }
}
