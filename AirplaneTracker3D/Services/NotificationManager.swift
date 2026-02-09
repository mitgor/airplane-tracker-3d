import Foundation
import UserNotifications

/// Manages macOS notifications for aircraft alerts (emergency squawks, watched callsigns).
/// Handles permission requests, alert evaluation with cooldown deduplication, and foreground delivery.
@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published var isAuthorized = false

    /// Evaluate aircraft states for alert conditions. Stub -- fully implemented with alert logic.
    func evaluateAlerts(for states: [InterpolatedAircraftState]) {
        // Will be fully implemented in Task 2
    }
}
