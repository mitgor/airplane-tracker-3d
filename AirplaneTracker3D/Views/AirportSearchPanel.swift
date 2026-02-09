import SwiftUI

/// Airport search and nearby browsing panel.
/// Provides two modes via a segmented picker:
/// - Search: TextField with autocomplete filtering by name/IATA/ICAO
/// - Nearby: Airports sorted by distance from current camera position
/// Tapping any airport result triggers a fly-to camera animation via NotificationCenter.
struct AirportSearchPanel: View {

    @StateObject private var viewModel = AirportSearchViewModel()

    /// Current camera target passed from ContentView for nearby distance computation
    var cameraTarget: SIMD3<Float> = .zero

    /// Tracks the selected mode: 0 = Search, 1 = Nearby
    @State private var selectedMode: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("AIRPORTS")
                    .font(.caption.bold())
                    .foregroundColor(.gray)
                    .textCase(.uppercase)
                Spacer()
                Button(action: {
                    NotificationCenter.default.post(name: .toggleSearch, object: nil)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }

            // Mode picker
            Picker("Mode", selection: $selectedMode) {
                Text("Search").tag(0)
                Text("Nearby").tag(1)
            }
            .pickerStyle(.segmented)

            if selectedMode == 0 {
                searchContent
            } else {
                nearbyContent
            }
        }
        .padding()
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
        )
        .allowsHitTesting(true)
        .onChange(of: cameraTarget) { _, newValue in
            viewModel.cameraTarget = newValue
        }
    }

    // MARK: - Search Mode

    @ViewBuilder
    private var searchContent: some View {
        TextField("Search airports...", text: $viewModel.searchText)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13))

        if viewModel.filteredAirports.isEmpty && !viewModel.searchText.isEmpty {
            Text("No results")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.top, 4)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.filteredAirports, id: \.icao) { airport in
                        airportRow(airport: airport)
                    }
                }
            }
            .frame(maxHeight: 280)
        }
    }

    // MARK: - Nearby Mode

    @ViewBuilder
    private var nearbyContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(viewModel.nearbyAirports, id: \.airport.icao) { entry in
                    nearbyRow(airport: entry.airport, distance: entry.distance)
                }
            }
        }
        .frame(maxHeight: 340)
    }

    // MARK: - Row Views

    private func airportRow(airport: AirportData) -> some View {
        Button(action: {
            viewModel.flyTo(airport: airport)
        }) {
            HStack(spacing: 8) {
                Text(airport.iata ?? airport.icao)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 40, alignment: .leading)

                Text(airport.name)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    private func nearbyRow(airport: AirportData, distance: Float) -> some View {
        Button(action: {
            viewModel.flyTo(airport: airport)
        }) {
            HStack(spacing: 8) {
                Text(airport.iata ?? airport.icao)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 40, alignment: .leading)

                Text(airport.name)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Text(formatDistance(distance))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.7))
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formatDistance(_ worldUnits: Float) -> String {
        if worldUnits < 10 {
            return String(format: "%.1f", worldUnits)
        } else {
            return "\(Int(worldUnits))"
        }
    }
}
