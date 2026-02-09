import SwiftUI

struct ContentView: View {
    @State private var flightDataManager = FlightDataManager()
    @State private var selectedAircraft: SelectedAircraftInfo? = nil
    private let enrichmentService = EnrichmentService()

    /// Coordinator reference for follow mode toggle (set after MetalView creates)
    @State private var metalCoordinator: MetalView.Coordinator? = nil

    /// Current theme label for the toggle button
    @State private var themeLabel: String = "DAY"

    /// Whether the airport search panel is visible
    @State private var showSearchPanel: Bool = false

    /// Current camera target for nearby airport distance computation
    @State private var cameraTarget: SIMD3<Float> = .zero

    /// Whether the info panel is visible (on by default)
    @State private var showInfoPanel: Bool = true

    /// Whether the statistics panel is visible
    @State private var showStatsPanel: Bool = false

    /// Statistics collector for time-series charting
    @StateObject private var statisticsCollector = StatisticsCollector()

    /// Live aircraft count from the renderer
    @State private var aircraftCount: Int = 0

    /// Last time the aircraft count was updated
    @State private var lastUpdateTime: Date = Date()

    /// Camera center latitude (for info panel display)
    @State private var centerLat: Double = 47.6

    /// Camera center longitude (for info panel display)
    @State private var centerLon: Double = -122.3

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

            // Top-left controls: theme button + search button
            VStack {
                HStack(spacing: 6) {
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

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSearchPanel.toggle()
                        }
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.leading, 12)
                .padding(.top, 12)

                // Airport search panel (below buttons, top-left area)
                if showSearchPanel {
                    HStack {
                        AirportSearchPanel(cameraTarget: cameraTarget)
                            .padding(.leading, 12)
                            .padding(.top, 4)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        Spacer()
                    }
                }

                Spacer()

                // Bottom row: info panel (left) and stats panel (right)
                HStack(alignment: .bottom) {
                    if showInfoPanel {
                        InfoPanel(
                            aircraftCount: aircraftCount,
                            lastUpdateTime: lastUpdateTime,
                            centerLat: centerLat,
                            centerLon: centerLon
                        )
                        .transition(.opacity)
                        .allowsHitTesting(false)
                    }

                    Spacer()

                    if showStatsPanel {
                        StatisticsPanel(collector: statisticsCollector)
                            .transition(.move(edge: .bottom))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
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
            let savedSource = UserDefaults.standard.string(forKey: "dataSource") ?? "global"
            let mode: FlightDataActor.DataMode = savedSource == "local" ? .local : .global
            flightDataManager.startPolling(mode: mode, center: center)

            // Configure statistics collector
            statisticsCollector.aircraftCountProvider = { [self] in
                aircraftCount
            }
            statisticsCollector.start()
        }
        .onDisappear {
            statisticsCollector.stop()
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
        .onReceive(NotificationCenter.default.publisher(for: .toggleSearch)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                showSearchPanel.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cameraTargetUpdated)) { notification in
            if let pos = notification.userInfo?["target"] as? [Float], pos.count >= 3 {
                cameraTarget = SIMD3<Float>(pos[0], pos[1], pos[2])
                // Update center coordinates for info panel
                centerLat = MapCoordinateSystem.shared.zToLat(pos[2])
                centerLon = MapCoordinateSystem.shared.xToLon(pos[0])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleInfoPanel)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                showInfoPanel.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleStats)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                showStatsPanel.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aircraftCountUpdated)) { notification in
            if let count = notification.userInfo?["count"] as? Int {
                aircraftCount = count
            }
            if let time = notification.userInfo?["time"] as? Date {
                lastUpdateTime = time
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchDataSource)) { notification in
            if let source = notification.userInfo?["source"] as? String {
                let center = (lat: MapCoordinateSystem.shared.centerLat,
                              lon: MapCoordinateSystem.shared.centerLon)
                let mode: FlightDataActor.DataMode = source == "local" ? .local : .global
                flightDataManager.switchMode(to: mode, center: center)
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let toggleFollowMode = Notification.Name("toggleFollowMode")
    static let clearSelection = Notification.Name("clearSelection")
    static let switchDataSource = Notification.Name("switchDataSource")
}
