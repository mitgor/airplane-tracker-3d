import SwiftUI

// MARK: - AircraftDetailPanel

/// SwiftUI detail panel shown when an aircraft is selected.
/// Displays flight data and asynchronously loads enrichment data.
struct AircraftDetailPanel: View {

    let aircraft: SelectedAircraftInfo
    let enrichmentService: EnrichmentService
    let onFollow: () -> Void
    let onClose: () -> Void

    @State private var enrichedAircraft: AircraftEnrichment?
    @State private var routeInfo: RouteEnrichment?
    @State private var isLoadingEnrichment = true

    @AppStorage("unitSystem") private var unitSystem: String = "imperial"

    private var isMetric: Bool { unitSystem == "metric" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: callsign + close button
            HStack {
                Text(aircraft.callsign.isEmpty ? aircraft.hex : aircraft.callsign)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }

            Divider().background(Color.gray)

            // Flight Data section
            sectionHeader("Flight Data")

            dataRow("Altitude", formatAltitude(aircraft.altitude))
            dataRow("Speed", formatSpeed(aircraft.groundSpeed))
            dataRow("Heading", "\(Int(aircraft.heading)) deg")
            dataRow("Vert Rate", formatVerticalRate(aircraft.verticalRate))
            if !aircraft.squawk.isEmpty {
                dataRow("Squawk", aircraft.squawk)
            }

            Divider().background(Color.gray)

            // Position section
            sectionHeader("Position")
            dataRow("Lat", String(format: "%.4f", aircraft.lat))
            dataRow("Lon", String(format: "%.4f", aircraft.lon))

            // Aircraft section (from enrichment)
            if let acInfo = enrichedAircraft, !acInfo.registration.isEmpty {
                Divider().background(Color.gray)
                sectionHeader("Aircraft")
                if !acInfo.registration.isEmpty {
                    dataRow("Reg", acInfo.registration)
                }
                if !acInfo.type.isEmpty {
                    dataRow("Type", acInfo.type)
                }
                if !acInfo.owner.isEmpty {
                    dataRow("Operator", acInfo.owner)
                }
            }

            // Route section (from enrichment)
            if let route = routeInfo, !route.originCode.isEmpty {
                Divider().background(Color.gray)
                sectionHeader("Route")
                HStack(spacing: 4) {
                    Text(route.originCode)
                        .font(.system(.body, design: .monospaced).bold())
                        .foregroundColor(.white)
                    Text("->")
                        .foregroundColor(.gray)
                    Text(route.destinationCode)
                        .font(.system(.body, design: .monospaced).bold())
                        .foregroundColor(.white)
                }
                if !route.originName.isEmpty {
                    Text(route.originName)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                if !route.destinationName.isEmpty {
                    Text(route.destinationName)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            if isLoadingEnrichment {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.gray)
                    Text("Loading details...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            // Follow button
            Button(action: onFollow) {
                HStack {
                    Image(systemName: "scope")
                    Text("Follow")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.6))
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
        )
        .task {
            async let acInfo = enrichmentService.fetchAircraftInfo(hex: aircraft.hex)
            async let rtInfo = enrichmentService.fetchRouteInfo(callsign: aircraft.callsign)
            enrichedAircraft = await acInfo
            routeInfo = await rtInfo
            isLoadingEnrichment = false
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundColor(.gray)
            .textCase(.uppercase)
    }

    private func dataRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
        }
    }

    private func formatAltitude(_ alt: Float) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if isMetric {
            let meters = alt * 0.3048
            let formatted = formatter.string(from: NSNumber(value: meters)) ?? "\(Int(meters))"
            return "\(formatted) m"
        } else {
            let formatted = formatter.string(from: NSNumber(value: alt)) ?? "\(Int(alt))"
            return "\(formatted) ft"
        }
    }

    private func formatSpeed(_ speed: Float) -> String {
        if isMetric {
            let kmh = speed * 1.852
            return "\(Int(kmh)) km/h"
        } else {
            return "\(Int(speed)) kts"
        }
    }

    private func formatVerticalRate(_ rate: Float) -> String {
        let prefix = rate >= 0 ? "+" : ""
        if isMetric {
            let mps = rate * 0.00508
            return "\(prefix)\(String(format: "%.1f", mps)) m/s"
        } else {
            return "\(prefix)\(Int(rate)) ft/min"
        }
    }
}
