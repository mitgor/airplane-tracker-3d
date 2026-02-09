import AppKit

/// Manages the macOS dock icon badge label showing live aircraft count.
@MainActor
final class DockBadgeManager {
    static let shared = DockBadgeManager()

    /// Update the dock icon badge with the current aircraft count.
    /// Shows the count as a red badge when > 0, clears when 0.
    func updateBadge(count: Int) {
        NSApplication.shared.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    /// Remove the dock icon badge entirely.
    func clearBadge() {
        NSApplication.shared.dockTile.badgeLabel = nil
    }
}
