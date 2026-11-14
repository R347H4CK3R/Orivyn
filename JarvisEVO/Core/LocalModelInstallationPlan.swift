import Foundation

/// Called inside the store's serialized install operation before publication.
enum LocalModelInstallationPlan {
    static func updatedManifest(installing descriptor: LocalModelDescriptor,
                                from manifest: [LocalModelDescriptor]) throws -> [LocalModelDescriptor] {
        // A descriptor ID cannot acquire another record's live file. Check before
        // the transaction replaces any bytes, even if that record is currently corrupt.
        guard !manifest.contains(where: { $0.id != descriptor.id && $0.sharesFileName(with: descriptor) }) else {
            throw LocalModelInstallationPlanError.fileOwnedByAnotherModel
        }
        var updated = manifest
        updated.removeAll { $0.id == descriptor.id }
        updated.append(descriptor)
        return updated
    }
}

enum LocalModelInstallationPlanError: LocalizedError, Equatable {
    case fileOwnedByAnotherModel
    var errorDescription: String? {
        "Another installed model owns this file name. Installation was stopped to preserve it. Choose a different model file or repair the installed model list."
    }
}
