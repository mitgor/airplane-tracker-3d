import SwiftUI

/// Tabbed SwiftUI Settings view with @AppStorage-bound controls for theme, units,
/// data source, trail rendering, altitude exaggeration, and notification alerts.
/// All values persist across app restarts via UserDefaults.
struct SettingsView: View {

    // MARK: - Appearance Settings

    @AppStorage("selectedTheme") private var selectedTheme: String = "day"
    @AppStorage("unitSystem") private var unitSystem: String = "imperial"

    // MARK: - Rendering Settings

    @AppStorage("trailLength") private var trailLength: Double = 500.0
    @AppStorage("showAirspace") private var showAirspace: Bool = true
    @AppStorage("showAirspaceClassB") private var showAirspaceClassB: Bool = true
    @AppStorage("showAirspaceClassC") private var showAirspaceClassC: Bool = true
    @AppStorage("showAirspaceClassD") private var showAirspaceClassD: Bool = true
    @AppStorage("trailWidth") private var trailWidth: Double = 3.0
    @AppStorage("altitudeExaggeration") private var altitudeExaggeration: Double = 1.0

    // MARK: - Data Settings

    @AppStorage("dataSource") private var dataSource: String = "global"

    // MARK: - Notification Settings

    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false
    @AppStorage("alertOnEmergencySquawk") private var alertOnEmergencySquawk: Bool = true
    @AppStorage("watchedCallsigns") private var watchedCallsigns: String = ""

    @ObservedObject private var notificationManager = NotificationManager.shared

    var body: some View {
        TabView {
            appearanceTab
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            renderingTab
                .tabItem {
                    Label("Rendering", systemImage: "cube.transparent")
                }

            notificationsTab
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
        }
        .frame(width: 400, height: 450)
        .onChange(of: selectedTheme) { _, newTheme in
            NotificationCenter.default.post(
                name: .setTheme,
                object: nil,
                userInfo: ["theme": newTheme]
            )
        }
        .onChange(of: dataSource) { _, newSource in
            NotificationCenter.default.post(
                name: .switchDataSource,
                object: nil,
                userInfo: ["source": newSource]
            )
        }
    }

    // MARK: - Appearance Tab

    private var appearanceTab: some View {
        Form {
            Picker("Theme", selection: $selectedTheme) {
                Text("Day").tag("day")
                Text("Night").tag("night")
                Text("Retro").tag("retro")
            }
            .pickerStyle(.segmented)

            Picker("Unit System", selection: $unitSystem) {
                Text("Imperial (ft, kts)").tag("imperial")
                Text("Metric (m, km/h)").tag("metric")
            }
        }
        .padding()
    }

    // MARK: - Rendering Tab

    private var renderingTab: some View {
        Form {
            Picker("Data Source", selection: $dataSource) {
                Text("Global (airplanes.live)").tag("global")
                Text("Local (dump1090)").tag("local")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Trail Length: \(Int(trailLength)) points")
                    .font(.caption)
                Slider(value: $trailLength, in: 50...4000, step: 50)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Trail Width: \(String(format: "%.1f", trailWidth)) px")
                    .font(.caption)
                Slider(value: $trailWidth, in: 1...10, step: 0.5)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Altitude Exaggeration: \(String(format: "%.1f", altitudeExaggeration))x")
                    .font(.caption)
                Slider(value: $altitudeExaggeration, in: 0.5...5.0, step: 0.5)
            }

            Section("Airspace Volumes") {
                Toggle("Show Airspace", isOn: $showAirspace)
                if showAirspace {
                    Toggle("Class B", isOn: $showAirspaceClassB)
                        .foregroundColor(.blue)
                    Toggle("Class C", isOn: $showAirspaceClassC)
                        .foregroundColor(.purple)
                    Toggle("Class D", isOn: $showAirspaceClassD)
                        .foregroundColor(.cyan)
                }
            }
        }
        .padding()
    }

    // MARK: - Notifications Tab

    private var notificationsTab: some View {
        Form {
            Toggle("Enable Notifications", isOn: $notificationsEnabled)

            if notificationsEnabled {
                HStack {
                    if notificationManager.isAuthorized {
                        Text("Permission: Granted")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else {
                        Text("Permission: Not Granted")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Spacer()
                        Button("Request Permission") {
                            Task {
                                await notificationManager.requestPermission()
                            }
                        }
                    }
                }

                Toggle("Alert on Emergency Squawk (7500/7600/7700)", isOn: $alertOnEmergencySquawk)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Watched Callsigns (comma-separated):")
                        .font(.caption)
                    TextField("e.g. UAL123, DAL456", text: $watchedCallsigns)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding()
        .task {
            await notificationManager.checkAuthorization()
        }
    }
}
