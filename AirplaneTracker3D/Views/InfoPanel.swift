import SwiftUI

/// Compact overlay panel showing live aircraft count, last update time,
/// and center map coordinates. Positioned bottom-left of the 3D view.
struct InfoPanel: View {

    let aircraftCount: Int
    let lastUpdateTime: Date
    let centerLat: Double
    let centerLon: Double

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "airplane")
                    .font(.system(size: 11, weight: .bold))
                Text("\(aircraftCount)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }

            HStack(spacing: 4) {
                Text("Updated:")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(Self.timeFormatter.string(from: lastUpdateTime))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }

            Text(String(format: "%.2f, %.2f", centerLat, centerLon))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}
