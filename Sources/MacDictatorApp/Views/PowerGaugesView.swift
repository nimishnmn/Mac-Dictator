import SwiftUI
import MacDictatorCore

public struct PowerGaugesView: View {
    @ObservedObject var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 6) {
            // CPU Gauge Card
            PowerCard(
                title: "CPU",
                value: state.reading.cpuPowerWatts,
                limit: state.config.cpuLimitWatts,
                isGovernorActive: state.config.isGovernorEnabled,
                utilization: state.reading.cpuUtilization,
                color: Color.cyan,
                icon: "cpu"
            )

            // GPU Gauge Card
            PowerCard(
                title: "GPU",
                value: state.reading.gpuPowerWatts,
                limit: state.config.gpuLimitWatts,
                isGovernorActive: state.config.isGovernorEnabled,
                utilization: state.reading.gpuUtilization,
                color: Color.purple,
                icon: "circle.grid.cross"
            )

            // Total System Card with Mode Toggle & Raw Gas Gauge Visibility
            TotalSystemCard(
                systemWatts: state.reading.systemTotalWatts,
                socWatts: state.reading.socTotalWatts,
                isBattery: state.reading.isBatteryPowered,
                rawBatteryWatts: state.reading.rawBatteryWatts,
                rawBatteryAgeSeconds: state.reading.rawBatteryAgeSeconds,
                isDirectGaugeMode: state.useDirectBatteryGauge,
                onToggleMode: {
                    state.toggleTelemetryMode()
                }
            )
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PowerCard: View {
    let title: String
    let value: Double
    let limit: Double
    let isGovernorActive: Bool
    let utilization: Double
    let color: Color
    let icon: String

    private var percentageOfLimit: Double {
        limit > 0 ? (value / limit) : 0.0
    }

    private var statusColor: Color {
        if !isGovernorActive { return color }
        if percentageOfLimit >= 1.0 { return .red }
        if percentageOfLimit >= 0.85 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                Label(title, systemImage: icon)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 1)
                if isGovernorActive {
                    Text(String(format: "%.0fW", limit))
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(statusColor.opacity(0.15))
                        .foregroundColor(statusColor)
                        .cornerRadius(2.5)
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(String(format: "%.2f", value))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("W")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 1)
                Text(String(format: "%.0f%%", utilization))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }

            // Power meter bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 3)

                    let fillWidth = min(geo.size.width, geo.size.width * CGFloat(percentageOfLimit))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(
                            LinearGradient(
                                colors: [color, statusColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, fillWidth), height: 3)
                }
            }
            .frame(height: 3)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isGovernorActive && percentageOfLimit >= 1.0 ? Color.red.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct TotalSystemCard: View {
    let systemWatts: Double
    let socWatts: Double
    let isBattery: Bool
    let rawBatteryWatts: Double?
    let rawBatteryAgeSeconds: Int?
    let isDirectGaugeMode: Bool
    let onToggleMode: () -> Void

    var body: some View {
        Button(action: onToggleMode) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 2) {
                    Label("TOTAL", systemImage: isBattery ? "battery.75" : "bolt.fill")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 1)
                    if isBattery {
                        Text(isDirectGaugeMode ? "GAUGE" : "LIVE")
                            .font(.system(size: 6.5, weight: .bold))
                            .foregroundColor(isDirectGaugeMode ? .cyan : .orange)
                            .padding(.horizontal, 2.5)
                            .padding(.vertical, 0.5)
                            .background((isDirectGaugeMode ? Color.cyan : Color.orange).opacity(0.15))
                            .cornerRadius(2)
                            .lineLimit(1)
                            .fixedSize()
                    } else {
                        Text("AC")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(2.5)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }

                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(String(format: "%.2f", systemWatts))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("W")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 1)
                }

                HStack(spacing: 2) {
                    if isBattery, let raw = rawBatteryWatts, let age = rawBatteryAgeSeconds {
                        if isDirectGaugeMode {
                            Text(String(format: "SoC: %.1fW • %ds", socWatts, age))
                                .font(.system(size: 7.5, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        } else {
                            Text(String(format: "Batt: %.1fW (%ds)", raw, age))
                                .font(.system(size: 7.5, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text(String(format: "SoC: %.1fW", socWatts))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(7)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isDirectGaugeMode ? Color.cyan.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(isBattery ? (isDirectGaugeMode ? "Mode: Direct Battery Gas Gauge (Texas Instruments bq40z651 chip, 60s hardware update). Click to switch to Live Responsive mode." : "Mode: Live Responsive (SoC + Display + Base). Click to switch to Direct Battery Gas Gauge mode.") : "Total System Power (AC)")
    }
}
