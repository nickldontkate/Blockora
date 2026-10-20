import Foundation

/// A hired worker available to assign to construction jobs (§9). Workers provide
/// visual life and light strategy, not deep micromanagement.
struct Worker: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var type: WorkerType
    /// nil while idle at the office; set to the module they're walking to / working on.
    var assignedModuleID: UUID?

    var isAvailable: Bool { assignedModuleID == nil }

    init(id: UUID = UUID(), name: String, type: WorkerType, assignedModuleID: UUID? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.assignedModuleID = assignedModuleID
    }
}

/// Resolves whether a module under construction has the crew it needs and, if
/// so, advances its build progress. Deliberately simple: no schedules, no
/// worker fatigue — just "are the right hands assigned right now."
enum WorkerAssignmentEngine {
    /// Returns true if the given worker roster satisfies a module definition's
    /// crew requirement.
    static func isFullyCrewed(module: ModuleInstance, definition: ModuleDefinition, workers: [Worker]) -> Bool {
        var required = definition.workersRequired
        for workerID in module.assignedWorkerIDs {
            guard let worker = workers.first(where: { $0.id == workerID }) else { continue }
            if let remaining = required[worker.type], remaining > 0 {
                required[worker.type] = remaining - 1
            }
        }
        return required.values.allSatisfy { $0 <= 0 }
    }

    /// Advances construction progress for one tick (deltaSeconds) if crewed.
    /// Returns the updated module and whether it just completed this call.
    static func advance(
        module: ModuleInstance,
        definition: ModuleDefinition,
        workers: [Worker],
        deltaSeconds: TimeInterval
    ) -> (module: ModuleInstance, didComplete: Bool) {
        guard !module.isBuilt else { return (module, false) }
        var updated = module
        guard isFullyCrewed(module: module, definition: definition, workers: workers), definition.buildTimeSeconds > 0 else {
            return (updated, false)
        }
        let increment = deltaSeconds / definition.buildTimeSeconds
        let wasBuilt = updated.isBuilt
        updated.constructionProgress = min(1, updated.constructionProgress + increment)
        return (updated, !wasBuilt && updated.isBuilt)
    }
}
