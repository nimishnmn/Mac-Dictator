import SwiftUI
import MacDictatorCore

public struct DashboardView: View {
    @ObservedObject var state: AppState
    public var onDetachWindow: (() -> Void)?
    public var onQuit: (() -> Void)?

    public init(state: AppState, onDetachWindow: (() -> Void)? = nil, onQuit: (() -> Void)? = nil) {
        self.state = state
        self.onDetachWindow = onDetachWindow
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar - pinned at top with high layout priority
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4.5)
                        .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 20, height: 20)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 0.5) {
                    Text("Mac Dictator")
                        .font(.system(size: 11.5, weight: .bold))
                        .lineLimit(1)
                    Text("Hardware Power Governor")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Total Battery Power Draw in top bar
                HStack(spacing: 3) {
                    Image(systemName: state.reading.isBatteryPowered ? "battery.75" : "bolt.fill")
                        .font(.system(size: 8.5))
                        .foregroundColor(state.reading.isBatteryPowered ? .orange : .green)
                    Text(String(format: "%.1fW", state.reading.systemTotalWatts))
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 4.5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(4)
                .help(state.reading.isBatteryPowered ? "Total Battery Power Draw" : "Total System Power Draw (AC)")

                // Pin Overlay Button
                Button(action: {
                    state.isPinned.toggle()
                }) {
                    Image(systemName: state.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundColor(state.isPinned ? .orange : .secondary)
                        .rotationEffect(.degrees(state.isPinned ? 0 : 45))
                }
                .buttonStyle(.plain)
                .help(state.isPinned ? "Overlay Pinned (Always on Top)" : "Pin Overlay on Top of All Apps")

                if let onDetach = onDetachWindow {
                    Button(action: onDetach) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open in Standalone Window")
                }

                if let onQuit = onQuit {
                    Button(action: onQuit) {
                        Image(systemName: "power")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Quit Mac Dictator")
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 5)
            .layoutPriority(1)

            // Segmented Navigation - pinned at top with high layout priority
            Picker("", selection: $state.selectedTab) {
                Text("Limits & Power").tag(0)
                Text("Processes").tag(1)
                Text("Verification Lab").tag(2)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .layoutPriority(1)

            Divider()
                .layoutPriority(1)

            // Main Content Area - consistent top-aligned height container across all tabs
            VStack(spacing: 6) {
                switch state.selectedTab {
                case 0:
                    PowerGaugesView(state: state)
                    PowerHistoryChartView(state: state)
                    PowerLimitControlsView(state: state)
                case 1:
                    PowerGaugesView(state: state)
                    ProcessListView(state: state)
                    Spacer(minLength: 0)
                case 2:
                    PowerGaugesView(state: state)
                    StressTestView(state: state)
                    Spacer(minLength: 0)
                default:
                    EmptyView()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()
                .layoutPriority(1)

            // Footer Status Bar - pinned at bottom with high layout priority
            HStack(spacing: 4) {
                Circle()
                    .fill(state.config.isGovernorEnabled ? (state.status.isThrottling ? Color.orange : Color.green) : Color.gray)
                    .frame(width: 5, height: 5)
                Text(state.status.statusMessage)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if state.isPinned {
                    Text("📌 PINNED")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(2)
                }
                Text(state.hardwareProfile.chipName)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor))
            .layoutPriority(1)
        }
        .frame(minWidth: 350, maxWidth: .infinity, minHeight: 460, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
