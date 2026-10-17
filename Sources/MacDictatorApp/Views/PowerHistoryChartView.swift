import SwiftUI
import MacDictatorCore

public struct PowerHistoryChartView: View {
    @ObservedObject var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    private var maxWatts: Double {
        let maxData = state.history.map { max($0.cpuPowerWatts, $0.gpuPowerWatts) }.max() ?? 6.0
        let limit = state.config.cpuLimitWatts
        return max(8.0, max(maxData * 1.2, limit * 1.25))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("POWER HISTORY (30s)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    LegendItem(name: "CPU", color: .cyan)
                    LegendItem(name: "GPU", color: .purple)
                    if state.config.isGovernorEnabled {
                        LegendItem(name: "Cap", color: .red, isDashed: true)
                    }
                }
            }

            ZStack(alignment: .topTrailing) {
                // Background grid lines
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height

                    Path { path in
                        // 2 horizontal guide lines
                        for i in 1...2 {
                            let y = h * (CGFloat(i) / 3.0)
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: w, y: y))
                        }
                    }
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)

                    // Draw Limit Line if Governor is Enabled
                    if state.config.isGovernorEnabled {
                        let limitY = h * (1.0 - CGFloat(state.config.cpuLimitWatts / maxWatts))
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: max(0, limitY)))
                            path.addLine(to: CGPoint(x: w, y: max(0, limitY)))
                        }
                        .stroke(Color.red.opacity(0.85), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                    }

                    // Draw CPU Power Curve
                    if state.history.count > 1 {
                        let stepX = w / CGFloat(max(1, state.history.count - 1))

                        Path { path in
                            for (index, item) in state.history.enumerated() {
                                let x = CGFloat(index) * stepX
                                let y = h * (1.0 - CGFloat(item.cpuPowerWatts / maxWatts))
                                if index == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                        // Draw GPU Power Curve
                        Path { path in
                            for (index, item) in state.history.enumerated() {
                                let x = CGFloat(index) * stepX
                                let y = h * (1.0 - CGFloat(item.gpuPowerWatts / maxWatts))
                                if index == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(Color.purple.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                    }
                }
                .frame(height: 55)

                // Scale label
                Text(String(format: "%.0f W max", maxWatts))
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(2)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct LegendItem: View {
    let name: String
    let color: Color
    var isDashed: Bool = false

    var body: some View {
        HStack(spacing: 2.5) {
            if isDashed {
                HStack(spacing: 1) {
                    Rectangle().fill(color).frame(width: 2.5, height: 1.5)
                    Rectangle().fill(color).frame(width: 2.5, height: 1.5)
                }
            } else {
                Circle().fill(color).frame(width: 4.5, height: 4.5)
            }
            Text(name)
                .font(.system(size: 7.5, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}
