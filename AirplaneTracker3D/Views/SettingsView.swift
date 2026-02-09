import SwiftUI

/// Tabbed SwiftUI Settings view with @AppStorage-bound controls for theme, units,
/// data source, trail rendering, and altitude exaggeration. All values persist
/// across app restarts via UserDefaults.
struct SettingsView: View {

    // MARK: - Appearance Settings

    @AppStorage("selectedTheme") private var selectedTheme: String = "day"
    @AppStorage("unitSystem") private var unitSystem: String = "imperial"

    // MARK: - Rendering Settings

    @AppStorage("trailLength") private var trailLength: Double = 500.0
    @AppStorage("trailWidth") private var trailWidth: Double = 3.0
    @AppStorage("altitudeExaggeration") private var altitudeExaggeration: Double = 1.0

    // MARK: - Data Settings

    @AppStorage("dataSource") private var dataSource: String = "global"

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
        }
        .frame(width: 400, height: 300)
        .onChange(of: selectedTheme) { _, newTheme in
            NotificationCenter.default.post(
                name: .setTheme,
                object: nil,
                userInfo: ["theme": newTheme]
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
        }
        .padding()
    }
}
