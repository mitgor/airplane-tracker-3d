import Foundation
import UserNotifications
import SwiftUI

/// Manages macOS notifications for aircraft alerts (emergency squawks, watched callsigns).
/// Handles permission requests, alert evaluation with cooldown deduplication, and foreground delivery.
@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published var isAuthorized = false

    @AppStorage("notificationsEnabled") var notificationsEnabled = false
    @AppStorage("alertOnEmergencySquawk") var alertOnEmergencySquawk = true
    @AppStorage("watchedCallsigns") private var watchedCallsignsRaw: String = ""

    /// Parsed set of watched callsigns (uppercased, trimmed).
    var watchedCallsigns: Set<String> {
        let parts = watchedCallsignsRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
        return Set(parts)
    }

    /// Tracks recently fired alerts to prevent spam. Key: "hex-conditionType"
    private var firedAlerts: [String: Date] = [:]

    /// Cooldown interval between repeated alerts for the same aircraft + condition.
    private let cooldownInterval: TimeInterval = 300  // 5 minutes

    /// Emergency squawk code meanings.
    private static let squawkMeanings: [String: String] = [
        "7700": "EMERGENCY",
        "7600": "RADIO FAILURE",
        "7500": "HIJACK"
    ]

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Request notification permission from macOS.
    func requestPermission() async {
        do {
            isAuthorized = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            isAuthorized = false
        }
    }

    /// Check current authorization status without requesting.
    func checkAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    /// Evaluate aircraft states against active alert conditions.
    /// Called every ~1 second from MenuBarManager when new aircraft data arrives.
    func evaluateAlerts(for states: [InterpolatedAircraftState]) {
        guard notificationsEnabled, isAuthorized else { return }

        let now = Date()

        // Clean expired cooldowns
        firedAlerts = firedAlerts.filter { now.timeIntervalSince($0.value) < cooldownInterval }

        let emergencySquawks: Set<String> = ["7500", "7600", "7700"]
        let watched = watchedCallsigns

        for aircraft in states {
            // Emergency squawk detection
            if alertOnEmergencySquawk, emergencySquawks.contains(aircraft.squawk) {
                let key = "\(aircraft.hex)-squawk-\(aircraft.squawk)"
                if firedAlerts[key] == nil {
                    firedAlerts[key] = now

                    let meaning = NotificationManager.squawkMeanings[aircraft.squawk] ?? "ALERT"
                    let callsignDisplay = aircraft.callsign.trimmingCharacters(in: .whitespaces).isEmpty
                        ? aircraft.hex
                        : aircraft.callsign.trimmingCharacters(in: .whitespaces)

                    sendNotification(
                        title: "Squawk \(aircraft.squawk) - \(meaning)",
                        body: "\(callsignDisplay) at \(Int(aircraft.altitude)) ft",
                        identifier: key
                    )
                }
            }

            // Watched callsign detection
            if !watched.isEmpty {
                let trimmedCallsign = aircraft.callsign.trimmingCharacters(in: .whitespaces).uppercased()
                if !trimmedCallsign.isEmpty, watched.contains(trimmedCallsign) {
                    let key = "\(aircraft.hex)-callsign"
                    if firedAlerts[key] == nil {
                        firedAlerts[key] = now

                        sendNotification(
                            title: "Watched Aircraft",
                            body: "\(trimmedCallsign) spotted at \(Int(aircraft.altitude)) ft",
                            identifier: key
                        )
                    }
                }
            }
        }
    }

    /// Send a local macOS notification with the given title and body.
    private func sendNotification(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notification banners even when the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
