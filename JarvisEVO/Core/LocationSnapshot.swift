import Foundation

struct LocationSnapshot: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let timestamp: Date

    func validated(now: Date) throws -> Self {
        let age = now.timeIntervalSince(timestamp)
        guard latitude.isFinite, longitude.isFinite, accuracy.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude), accuracy >= 0,
              age.isFinite, (-5...60).contains(age) else { throw LocationToolError.invalidResult }
        return self
    }
}

enum LocationToolError: LocalizedError, Equatable {
    case denied, unavailable, invalidResult, timedOut
    var errorDescription: String? {
        switch self {
        case .denied: "Location permission is off or restricted. You can change it in iPhone Settings. Nothing was shared."
        case .unavailable: "Your location is unavailable right now. Try again outdoors or check Location Services in Settings."
        case .invalidResult: "iOS returned an invalid or old location. Nothing was shared. Try again for a fresh result."
        case .timedOut: "The location request timed out and stopped. Nothing was shared. You can try again."
        }
    }
}
