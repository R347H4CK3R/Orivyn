import Foundation

/// Validates a removal against the current manifest before any file is touched.
/// The store must apply the plan within its own serialized operation; this pure
/// helper does not provide filesystem transactions or crash recovery.
enum LocalModelRemovalPlan {
    static func updatedManifest(removing descriptor: LocalModelDescriptor,
                                from manifest: [LocalModelDescriptor]) throws -> [LocalModelDescriptor] {
        let matches = manifest.indices.filter { manifest[$0].id == descriptor.id }
        guard !matches.isEmpty else { throw LocalModelRemovalPlanError.staleDescriptor }
        guard matches.count == 1 else { throw LocalModelRemovalPlanError.ambiguousManifest }
        let index = matches[0]
        guard manifest[index] == descriptor else { throw LocalModelRemovalPlanError.staleDescriptor }
        guard !manifest.indices.contains(where: { $0 != index && manifest[$0].sharesFileName(with: descriptor) }) else {
            throw LocalModelRemovalPlanError.ambiguousManifest
        }
        var updated = manifest
        updated.remove(at: index)
        return updated
    }
}

enum LocalModelRemovalPlanError: LocalizedError, Equatable {
    case staleDescriptor, ambiguousManifest
    var errorDescription: String? {
        switch self {
        case .staleDescriptor:
            "The selected model changed or is no longer installed. Refresh the model list and select it again. Nothing was removed."
        case .ambiguousManifest:
            "The installed model list contains conflicting identifiers or shared files. Removal was stopped to protect other models. Repair the model list before retrying."
        }
    }
}
