import SwiftUI
import MacDictatorCore

public struct StressTestView: View {
    @ObservedObject var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("VERIFICATION & STRESS LAB", systemImage: "flame.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(state.isStressTesting ? .orange : .secondary)
                Spacer()
                if state.isStressTesting {
                    Text("BURNING LOAD")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(4)
                }
            }

            Text("Verify power limits by generating a controlled synthetic CPU workload. With the Governor active, observe how the power curve is strictly restrained below your set limit.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            // Thread count controls
            HStack {
                Text("Stress Threads:")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Stepper("\(state.stressThreads) threads", value: $state.stressThreads, in: 1...state.hardwareProfile.totalCores)
                    .disabled(state.isStressTesting)
            }

            // Action button
            Button(action: {
                state.toggleStressTest()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: state.isStressTesting ? "stop.fill" : "play.fill")
                        .font(.system(size: 10))
                    Text(state.isStressTesting ? "Stop Stress Test" : "Start Synthetic Load Test")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(state.isStressTesting ? Color.red : Color.orange)
                .foregroundColor(.white)
                .cornerRadius(5)
            }
            .buttonStyle(.plain)

            Divider()

            // Hardware summary
            VStack(alignment: .leading, spacing: 4) {
                Text("HARDWARE SPECS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                HStack {
                    Text("Chip:")
                        .foregroundColor(.secondary)
                    Text(state.hardwareProfile.chipName)
                        .fontWeight(.medium)
                }
                HStack {
                    Text("Cores:")
                        .foregroundColor(.secondary)
                    Text("\(state.hardwareProfile.totalCores) Total (\(state.hardwareProfile.performanceCores) Super/Perf, \(state.hardwareProfile.efficiencyCores) Efficiency)")
                        .fontWeight(.medium)
                }
                HStack {
                    Text("Rated Max TDP:")
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f W", state.hardwareProfile.ratedMaxTdpWatts))
                        .fontWeight(.medium)
                }
            }
            .font(.system(size: 10))
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(state.isStressTesting ? Color.orange.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
