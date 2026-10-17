import SwiftUI
import MacDictatorCore

public struct ProcessListView: View {
    @ObservedObject var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PROCESS GOVERNOR MONITOR")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(state.processes.filter { $0.isClampedToECores }.count) throttled")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.orange)
            }

            if state.processes.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 24))
                        .foregroundColor(.green.opacity(0.6))
                    Text("All processes operating normally within budget")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(state.processes) { proc in
                            ProcessRow(proc: proc) {
                                state.toggleExempt(processName: proc.name)
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ProcessRow: View {
    let proc: ThrottledProcessInfo
    let onToggleExempt: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(proc.name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text(String(format: "PID %d", proc.pid))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)

                    if proc.isExempt {
                        Text("EXEMPT")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(3)
                    } else if proc.isClampedToECores {
                        Text(String(format: "THROTTLED %.0f%%", proc.dutyCyclePercent))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(3)
                    }
                }

                HStack(spacing: 8) {
                    Text(String(format: "%.1f%% CPU", proc.cpuPercent))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(String(format: "~%.2f W", proc.estimatedWatts))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.primary)
                }
            }

            Spacer()

            Button(action: onToggleExempt) {
                Image(systemName: proc.isExempt ? "shield.fill" : "shield")
                    .font(.system(size: 12))
                    .foregroundColor(proc.isExempt ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .help(proc.isExempt ? "Remove exemption" : "Exempt from power throttling")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(proc.isClampedToECores ? Color.orange.opacity(0.06) : Color.primary.opacity(0.03))
        .cornerRadius(6)
    }
}
