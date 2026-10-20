import Foundation
import CoreGraphics

/// Road quality gates delivery speed (§19). MVP keeps this to two tiers —
/// bridges/ports/rail/drones are documented future extensions, not built yet.
enum RoadQuality: String, Codable {
    case dirt
    case paved

    var deliverySpeed: Double {
        switch self {
        case .dirt: return 40 // points per second, world space
        case .paved: return 70
        }
    }
}

/// A single visible shipment (§18): a resource crate physically travelling
/// from a producing plot to a destination. Purely a visualization/timing
/// concern — resources are already credited to the player at production time,
/// so a delivery job never itself grants or removes resources.
struct DeliveryJob: Identifiable {
    let id: UUID
    let resource: ResourceType
    let amount: Double
    let originWorldPosition: CGPoint
    let destinationWorldPosition: CGPoint
    let speed: Double

    var travelDuration: TimeInterval {
        let dx = destinationWorldPosition.x - originWorldPosition.x
        let dy = destinationWorldPosition.y - originWorldPosition.y
        let distance = (dx * dx + dy * dy).squareRoot()
        return speed > 0 ? Double(distance) / speed : 0
    }
}

/// Decides when accumulated production is "enough" to send a visible truck,
/// so the world doesn't spawn a crate every single resource tick.
enum LogisticsEngine {
    static let deliveryBatchSize: Double = 25

    static func spawnDelivery(
        for resource: ResourceType,
        accumulated: inout Double,
        origin: CGPoint,
        destination: CGPoint,
        road: RoadQuality
    ) -> DeliveryJob? {
        guard accumulated >= deliveryBatchSize else { return nil }
        let amount = deliveryBatchSize
        accumulated -= amount
        return DeliveryJob(
            id: UUID(),
            resource: resource,
            amount: amount,
            originWorldPosition: origin,
            destinationWorldPosition: destination,
            speed: road.deliverySpeed
        )
    }
}
