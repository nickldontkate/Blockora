import UIKit

/// Centralized haptic feedback (§56). Kept to UIKit's feedback generators —
/// plenty expressive for snap/place/warning cues without CoreHaptics' overhead.
final class HapticManager {
    static let shared = HapticManager()

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    private init() {}

    func moduleSnap() { selection.selectionChanged() }
    func modulePlaced() { mediumImpact.impactOccurred() }
    func synergyDiscovered() { notification.notificationOccurred(.success) }
    func structuralWarning() { lightImpact.impactOccurred(intensity: 0.6) }
    func structuralCollapse() { heavyImpact.impactOccurred() }
    func contractCompleted() { notification.notificationOccurred(.success) }
    func actionFailed() { notification.notificationOccurred(.error) }
}
