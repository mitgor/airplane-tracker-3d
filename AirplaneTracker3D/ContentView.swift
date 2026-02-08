import SwiftUI

struct ContentView: View {
    @State private var flightDataManager = FlightDataManager()

    var body: some View {
        MetalView(flightDataManager: flightDataManager)
            .ignoresSafeArea()
            .onAppear {
                let center = (lat: MapCoordinateSystem.shared.centerLat,
                              lon: MapCoordinateSystem.shared.centerLon)
                flightDataManager.startPolling(mode: .global, center: center)
            }
    }
}
