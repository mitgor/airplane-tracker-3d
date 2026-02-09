import Foundation
import AppKit

/// Observable manager that subscribes to aircraft count updates from the Renderer
/// and drives the menu bar status item label and dock badge.
@MainActor
final class MenuBarManager: ObservableObject {

    /// Live aircraft count displayed in the menu bar and dock badge.
    @Published var aircraftCount: Int = 0

    /// Observer token for NotificationCenter subscription.
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .aircraftCountUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let count = notification.userInfo?["count"] as? Int {
                    self.aircraftCount = count
                    DockBadgeManager.shared.updateBadge(count: count)
                }
                if let states = notification.userInfo?["states"] as? [InterpolatedAircraftState] {
                    NotificationManager.shared.evaluateAlerts(for: states)
                }
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
