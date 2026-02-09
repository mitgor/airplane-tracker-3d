import Foundation

/// Timer-based time-series data collector that samples aircraft count every 5 seconds.
/// Maintains a rolling window of data points (default 120 = 10 minutes) for charting.
@MainActor
final class StatisticsCollector: ObservableObject {

    // MARK: - Types

    struct DataPoint: Identifiable {
        let id = UUID()
        let timestamp: Date
        let aircraftCount: Int
    }

    // MARK: - Published State

    @Published var dataPoints: [DataPoint] = []

    // MARK: - Configuration

    /// Maximum number of data points to retain (120 = 10 minutes at 5s intervals).
    private let maxPoints: Int = 120

    /// Sampling interval in seconds.
    private let interval: TimeInterval = 5.0

    // MARK: - External Data Providers

    /// Closure to read the current aircraft count. Set by ContentView.
    var aircraftCountProvider: (() -> Int)?

    // MARK: - Timer

    private var timer: Timer?

    // MARK: - Lifecycle

    /// Start collecting data points at the configured interval.
    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sample()
            }
        }
    }

    /// Stop the collection timer.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Sampling

    private func sample() {
        let count = aircraftCountProvider?() ?? 0
        let point = DataPoint(timestamp: Date(), aircraftCount: count)
        dataPoints.append(point)

        // Trim to rolling window
        if dataPoints.count > maxPoints {
            dataPoints.removeFirst(dataPoints.count - maxPoints)
        }
    }
}
