import SwiftUI
import AppKit

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
    @State private var photoURL: String?

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

            // External links section
            Divider().background(Color.gray)
            sectionHeader("Links")
            HStack(spacing: 12) {
                if !aircraft.callsign.isEmpty {
                    linkButton("FlightAware", url: "https://flightaware.com/live/flight/\(aircraft.callsign.trimmingCharacters(in: .whitespaces))")
                }
                linkButton("ADS-B Exchange", url: "https://globe.adsbexchange.com/?icao=\(aircraft.hex)")
                linkButton("Planespotters", url: "https://www.planespotters.net/hex/\(aircraft.hex)")
            }

            // Aircraft photo section
            if let urlStr = photoURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: 120)
                            .clipped()
                            .cornerRadius(8)
                    case .failure:
                        EmptyView()
                    case .empty:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(maxWidth: .infinity, maxHeight: 120)
                            .overlay(ProgressView().tint(.gray))
                    @unknown default:
                        EmptyView()
                    }
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
            async let photoInfo = enrichmentService.fetchPhotoURL(hex: aircraft.hex)
            enrichedAircraft = await acInfo
            routeInfo = await rtInfo
            photoURL = await photoInfo
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

    private func linkButton(_ title: String, url: String) -> some View {
        Button(action: {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        }) {
            Text(title)
                .font(.caption)
                .foregroundColor(.blue)
                .underline()
        }
        .buttonStyle(.plain)
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
