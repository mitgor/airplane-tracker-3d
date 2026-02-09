import Foundation

/// Configurable alert condition for aircraft notifications.
/// Supports emergency squawk detection and watched callsign matching.
struct AlertCondition: Codable, Identifiable {
    let id: UUID
    var type: AlertType
    var isEnabled: Bool

    enum AlertType: Codable {
        case callsign(String)
        case emergencySquawk  // covers 7500, 7600, 7700
    }

    init(type: AlertType, isEnabled: Bool = true) {
        self.id = UUID()
        self.type = type
        self.isEnabled = isEnabled
    }
}
