import SwiftUI
import Charts

/// Panel displaying a Swift Charts line graph of aircraft count over time.
/// Uses data collected by StatisticsCollector at 5-second intervals.
struct StatisticsPanel: View {

    @ObservedObject var collector: StatisticsCollector

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with title and close button
            HStack {
                Text("Statistics")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                Spacer()
                Button(action: {
                    NotificationCenter.default.post(name: .toggleStats, object: nil)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            if collector.dataPoints.isEmpty {
                Text("Collecting data...")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aircraft Count")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))

                    Chart {
                        ForEach(collector.dataPoints) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Count", point.aircraftCount)
                            )
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))

                            AreaMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Count", point.aircraftCount)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue.opacity(0.3), .blue.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .minute)) { _ in
                            AxisGridLine()
                                .foregroundStyle(.white.opacity(0.1))
                            AxisValueLabel(format: .dateTime.hour().minute())
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine()
                                .foregroundStyle(.white.opacity(0.1))
                            AxisValueLabel()
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .frame(height: 120)
                }
            }
        }
        .padding(10)
        .frame(width: 260)
        .background(Color.black.opacity(0.85))
        .cornerRadius(10)
    }
}
