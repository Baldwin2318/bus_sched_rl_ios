import Foundation

enum LaunchCameraPolicy {
    enum Decision: Equatable {
        case centerOnUser
        case restorePersisted
        case none
    }

    static func decision(currentLocationAvailable: Bool, hasPersistedCamera: Bool) -> Decision {
        if currentLocationAvailable {
            return .centerOnUser
        }
        if hasPersistedCamera {
            return .restorePersisted
        }
        return .none
    }
}
