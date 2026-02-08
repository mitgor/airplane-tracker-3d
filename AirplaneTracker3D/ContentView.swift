import SwiftUI

struct ContentView: View {
    @State private var flightDataManager = FlightDataManager()
    @State private var selectedAircraft: SelectedAircraftInfo? = nil
    private let enrichmentService = EnrichmentService()

    /// Coordinator reference for follow mode toggle (set after MetalView creates)
    @State private var metalCoordinator: MetalView.Coordinator? = nil

    /// Current theme label for the toggle button
    @State private var themeLabel: String = "DAY"

    var body: some View {
        ZStack(alignment: .trailing) {
            MetalView(
                flightDataManager: flightDataManager,
                onAircraftSelected: { info in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedAircraft = info
                    }
                }
            )
            .ignoresSafeArea()

            // Theme toggle button (top-left corner)
            VStack {
                HStack {
                    Button(action: {
                        NotificationCenter.default.post(name: .cycleTheme, object: nil)
                    }) {
                        Text(themeLabel)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 12)
                    .padding(.top, 12)

                    Spacer()
                }
                Spacer()
            }

            if let aircraft = selectedAircraft {
                AircraftDetailPanel(
                    aircraft: aircraft,
                    enrichmentService: enrichmentService,
                    onFollow: {
                        // Post notification for follow toggle (picked up by MetalView coordinator)
                        NotificationCenter.default.post(
                            name: .toggleFollowMode, object: nil
                        )
                    },
                    onClose: {
                        // Clear follow mode and deselect
                        NotificationCenter.default.post(
                            name: .clearSelection, object: nil
                        )
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedAircraft = nil
                        }
                    }
                )
                .frame(width: 280)
                .padding()
                .transition(.move(edge: .trailing))
            }
        }
        .onAppear {
            let center = (lat: MapCoordinateSystem.shared.centerLat,
                          lon: MapCoordinateSystem.shared.centerLon)
            flightDataManager.startPolling(mode: .global, center: center)
        }
        .onReceive(NotificationCenter.default.publisher(for: .themeChanged)) { notification in
            if let theme = notification.object as? Theme {
                switch theme {
                case .day: themeLabel = "DAY"
                case .night: themeLabel = "NIGHT"
                case .retro: themeLabel = "RETRO"
                }
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let toggleFollowMode = Notification.Name("toggleFollowMode")
    static let clearSelection = Notification.Name("clearSelection")
}
