import AppKit
import simd

// MARK: - Theme

/// Visual themes for the 3D flight tracker.
enum Theme: String, CaseIterable {
    case day, night, retro
}

// MARK: - ThemeConfig

/// Pure data struct describing visual parameters for a theme.
/// No Metal references -- safe to use from any thread.
struct ThemeConfig {
    let clearColor: (r: Double, g: Double, b: Double)
    let placeholderColor: SIMD4<Float>
    let isWireframe: Bool
    let aircraftTint: SIMD4<Float>
    let trailTint: SIMD4<Float>
    let labelTextColor: NSColor
    let labelBgColor: NSColor
    let airportLabelColor: SIMD4<Float>
    let altLineColor: SIMD4<Float>
    let airspaceClassBColor: SIMD4<Float>
    let airspaceClassCColor: SIMD4<Float>
    let airspaceClassDColor: SIMD4<Float>
}

// MARK: - ThemeManager

/// Manages the current visual theme and provides color configurations.
/// Posts `.themeChanged` notification and calls `onThemeChanged` callback when theme changes.
/// Persists theme selection to UserDefaults.
final class ThemeManager {

    /// Callback invoked on theme change (used by Renderer for immediate response).
    var onThemeChanged: ((Theme) -> Void)?

    /// Current theme. Setting this posts a notification and invokes the callback.
    var current: Theme {
        didSet {
            guard current != oldValue else { return }
            UserDefaults.standard.set(current.rawValue, forKey: "selectedTheme")
            NotificationCenter.default.post(name: .themeChanged, object: current)
            onThemeChanged?(current)
        }
    }

    /// Active theme configuration (computed from current theme).
    var config: ThemeConfig {
        return ThemeManager.configs[current]!
    }

    // MARK: - Init

    init() {
        if let saved = UserDefaults.standard.string(forKey: "selectedTheme"),
           let theme = Theme(rawValue: saved) {
            current = theme
        } else {
            current = .day
        }
    }

    // MARK: - Theme Cycling

    /// Advance to the next theme in day -> night -> retro -> day cycle.
    func cycleTheme() {
        let all = Theme.allCases
        guard let idx = all.firstIndex(of: current) else { return }
        let nextIdx = (idx + 1) % all.count
        current = all[nextIdx]
    }

    // MARK: - Theme Configurations

    static let configs: [Theme: ThemeConfig] = [
        .day: ThemeConfig(
            clearColor: (r: 0.529, g: 0.808, b: 0.922),
            placeholderColor: SIMD4<Float>(0.831, 0.867, 0.831, 1.0),
            isWireframe: false,
            aircraftTint: SIMD4<Float>(1, 1, 1, 1),
            trailTint: SIMD4<Float>(1, 1, 1, 1),
            labelTextColor: .white,
            labelBgColor: NSColor(red: 0, green: 0, blue: 0, alpha: 0.6),
            airportLabelColor: SIMD4<Float>(0.0, 0.4, 0.8, 1.0),
            altLineColor: SIMD4<Float>(0.5, 0.5, 0.5, 0.3),
            airspaceClassBColor: SIMD4<Float>(0.27, 0.40, 1.0, 0.06),
            airspaceClassCColor: SIMD4<Float>(0.60, 0.27, 1.0, 0.06),
            airspaceClassDColor: SIMD4<Float>(0.27, 0.67, 1.0, 0.06)
        ),
        .night: ThemeConfig(
            clearColor: (r: 0.039, g: 0.039, b: 0.102),
            placeholderColor: SIMD4<Float>(0.102, 0.165, 0.227, 1.0),
            isWireframe: false,
            aircraftTint: SIMD4<Float>(1, 1, 1, 1),
            trailTint: SIMD4<Float>(1, 1, 1, 1),
            labelTextColor: NSColor(red: 0, green: 1, blue: 1, alpha: 1),
            labelBgColor: NSColor(red: 0, green: 0, blue: 0.2, alpha: 0.7),
            airportLabelColor: SIMD4<Float>(0.4, 0.733, 1.0, 1.0),
            altLineColor: SIMD4<Float>(0.5, 0.5, 0.5, 0.3),
            airspaceClassBColor: SIMD4<Float>(0.33, 0.47, 1.0, 0.08),
            airspaceClassCColor: SIMD4<Float>(0.67, 0.33, 1.0, 0.08),
            airspaceClassDColor: SIMD4<Float>(0.33, 0.73, 1.0, 0.08)
        ),
        .retro: ThemeConfig(
            clearColor: (r: 0.0, g: 0.031, b: 0.0),
            placeholderColor: SIMD4<Float>(0.0, 0.067, 0.0, 1.0),
            isWireframe: true,
            aircraftTint: SIMD4<Float>(0, 1, 0, 1),
            trailTint: SIMD4<Float>(0, 1, 0, 1),
            labelTextColor: NSColor(red: 0, green: 1, blue: 0, alpha: 1),
            labelBgColor: NSColor(red: 0, green: 0.1, blue: 0, alpha: 0.6),
            airportLabelColor: SIMD4<Float>(0, 1, 0, 1),
            altLineColor: SIMD4<Float>(0, 1, 0, 0.3),
            airspaceClassBColor: SIMD4<Float>(0.0, 1.0, 0.0, 0.03),
            airspaceClassCColor: SIMD4<Float>(0.0, 1.0, 0.0, 0.03),
            airspaceClassDColor: SIMD4<Float>(0.0, 1.0, 0.0, 0.03)
        ),
    ]

    // MARK: - Tile URLs

    /// Build a tile URL for the given tile coordinate and theme.
    /// Day: CartoDB Positron, Night: CartoDB Dark Matter, Retro: OSM (green-tinted via shader).
    static func tileURL(for tile: TileCoordinate, theme: Theme) -> URL {
        let subdomains = ["a", "b", "c"]
        let subdomain = subdomains[abs(tile.x) % 3]

        switch theme {
        case .day:
            return URL(string: "https://\(subdomain).basemaps.cartocdn.com/light_all/\(tile.zoom)/\(tile.x)/\(tile.y).png")!
        case .night:
            return URL(string: "https://\(subdomain).basemaps.cartocdn.com/dark_all/\(tile.zoom)/\(tile.x)/\(tile.y).png")!
        case .retro:
            return URL(string: "https://\(subdomain).tile.openstreetmap.org/\(tile.zoom)/\(tile.x)/\(tile.y).png")!
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let themeChanged = Notification.Name("themeChanged")
    static let cycleTheme = Notification.Name("cycleTheme")
    static let setTheme = Notification.Name("setTheme")
    static let resetCamera = Notification.Name("resetCamera")
    static let toggleAutoRotate = Notification.Name("toggleAutoRotate")
    static let toggleInfoPanel = Notification.Name("toggleInfoPanel")
    static let toggleStats = Notification.Name("toggleStats")
    static let aircraftCountUpdated = Notification.Name("aircraftCountUpdated")
}
