import SwiftUI

struct ContentView: View {
    @State private var flightDataManager = FlightDataManager()
    @State private var selectedAircraft: SelectedAircraftInfo? = nil
    private let enrichmentService = EnrichmentService()

    /// Coordinator reference for follow mode toggle (set after MetalView creates)
    @State private var metalCoordinator: MetalView.Coordinator? = nil

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
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let toggleFollowMode = Notification.Name("toggleFollowMode")
    static let clearSelection = Notification.Name("clearSelection")
}
