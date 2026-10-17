import SwiftUI
import MacDictatorCore

public struct PowerLimitControlsView: View {
    @ObservedObject var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 6) {
            // Master Governor Toggle Card
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("POWER GOVERNOR")
                            .font(.system(size: 9.5, weight: .bold))
                            .lineLimit(1)
                        Text(state.config.isGovernorEnabled ? "ON" : "OFF")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(state.config.isGovernorEnabled ? .green : .secondary)
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1)
                            .background((state.config.isGovernorEnabled ? Color.green : Color.secondary).opacity(0.15))
                            .cornerRadius(2)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Text(state.config.isGovernorEnabled ? "Hardware wattage capped." : "Hardware power unconstrained.")
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Toggle("", isOn: Binding(
                    get: { state.config.isGovernorEnabled },
                    set: { _ in state.toggleGovernor() }
                ))
                .toggleStyle(SwitchToggleStyle(tint: .green))
                .labelsHidden()
                .scaleEffect(0.75)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(7)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(state.config.isGovernorEnabled ? Color.green.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
            )

            // CPU Limit Slider & Presets
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("CPU LIMIT", systemImage: "cpu")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.cyan)
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.1f W", state.config.cpuLimitWatts))
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .fixedSize()
                }

                Slider(
                    value: Binding(
                        get: { state.config.cpuLimitWatts },
                        set: { state.setCpuLimit($0) }
                    ),
                    in: 0.5...25.0,
                    step: 0.5
                )
                .accentColor(.cyan)
                .controlSize(.mini)

                // Quick Presets with small compact buttons
                HStack(spacing: 3) {
                    SmallPresetButton(label: "1W", watts: 1.0, current: state.config.cpuLimitWatts) {
                        state.setCpuLimit(1.0)
                    }
                    SmallPresetButton(label: "3W", watts: 3.0, current: state.config.cpuLimitWatts) {
                        state.setCpuLimit(3.0)
                    }
                    SmallPresetButton(label: "5W", watts: 5.0, current: state.config.cpuLimitWatts) {
                        state.setCpuLimit(5.0)
                    }
                    SmallPresetButton(label: "10W", watts: 10.0, current: state.config.cpuLimitWatts) {
                        state.setCpuLimit(10.0)
                    }
                    SmallPresetButton(label: "15W", watts: 15.0, current: state.config.cpuLimitWatts) {
                        state.setCpuLimit(15.0)
                    }
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

            // GPU Limit Slider & Presets
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("GPU LIMIT", systemImage: "circle.grid.cross")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.purple)
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.1f W", state.config.gpuLimitWatts))
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .fixedSize()
                }

                Slider(
                    value: Binding(
                        get: { state.config.gpuLimitWatts },
                        set: { state.setGpuLimit($0) }
                    ),
                    in: 0.5...20.0,
                    step: 0.5
                )
                .accentColor(.purple)
                .controlSize(.mini)

                // Quick Presets with small compact buttons
                HStack(spacing: 3) {
                    SmallPresetButton(label: "1W", watts: 1.0, current: state.config.gpuLimitWatts) {
                        state.setGpuLimit(1.0)
                    }
                    SmallPresetButton(label: "2W", watts: 2.0, current: state.config.gpuLimitWatts) {
                        state.setGpuLimit(2.0)
                    }
                    SmallPresetButton(label: "5W", watts: 5.0, current: state.config.gpuLimitWatts) {
                        state.setGpuLimit(5.0)
                    }
                    SmallPresetButton(label: "10W", watts: 10.0, current: state.config.gpuLimitWatts) {
                        state.setGpuLimit(10.0)
                    }
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

            // Governor Strategy Selection
            VStack(alignment: .leading, spacing: 3) {
                Text("STRATEGY")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Picker("", selection: Binding(
                    get: { state.config.strategy },
                    set: { state.setStrategy($0) }
                )) {
                    ForEach(ThrottleStrategy.allCases) { strat in
                        Text(strat.rawValue).tag(strat)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.mini)
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
        .frame(maxWidth: .infinity)
    }
}

private struct SmallPresetButton: View {
    let label: String
    let watts: Double
    let current: Double
    let action: () -> Void

    private var isSelected: Bool {
        abs(watts - current) < 0.1
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 8, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                .cornerRadius(3.5)
        }
        .buttonStyle(.plain)
    }
}
