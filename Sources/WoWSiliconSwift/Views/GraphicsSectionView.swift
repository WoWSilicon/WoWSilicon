import SwiftUI

struct GraphicsSectionView: View {
    @Binding var settings: GraphicsSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            GroupBox("Graphics Backend") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Graphics Backend", selection: $settings.backend) {
                        ForEach(GraphicsBackend.allCases, id: \.self) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    Text(settings.backend == .d9mt
                         ? "Experimental Metal backend. Some WoW clients or configurations may have rendering issues or crashes."
                         : "Default Vulkan-based backend with broad compatibility.")
                        .font(.caption)
                        .foregroundStyle(settings.backend == .d9mt ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
            }

            // Display
            GroupBox("Display") {
                VStack(spacing: 0) {
                    pickerRow("Window Mode", selection: $settings.windowMode, options: WindowMode.allCases, label: \.displayName)
                    Divider()
                    resolutionRow
                    Divider()
                    refreshRateRow
                    Divider()
                    toggleRow("VSync", isOn: $settings.vsync)
                }
            }

            // Quality
            GroupBox("Quality") {
                VStack(spacing: 0) {
                    pickerRow("Anti-Aliasing", selection: $settings.multisampling, options: Multisampling.allCases, label: \.displayName)
                    Divider()
                    pickerRow("Texture Filtering", selection: $settings.textureFiltering, options: TextureFiltering.allCases, label: \.displayName)
                    Divider()
                    pickerRow("Shadows", selection: $settings.shadowQuality, options: ShadowQuality.allCases, label: \.displayName)
                    Divider()
                    toggleRow("Specular Lighting", isOn: $settings.specular)
                    Divider()
                    toggleRow("Projected Textures", isOn: $settings.projectedTextures)
                }
            }

            // Distance & Environment
            GroupBox("Distance & Environment") {
                VStack(spacing: 0) {
                    viewDistanceRow
                    Divider()
                    groundEffectRow
                    Divider()
                    weatherRow
                    Divider()
                    particleRow
                }
            }
        }
    }

    // MARK: - Row builders

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func pickerRow<T: Hashable>(
        _ title: String,
        selection: Binding<T>,
        options: [T],
        label: KeyPath<T, String>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option[keyPath: label]).tag(option)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var resolutionRow: some View {
        HStack {
            Text("Resolution")
            Spacer()
            Picker("", selection: $settings.resolution) {
                Text("Default").tag("")
                ForEach(GraphicsSettings.commonResolutions, id: \.self) { res in
                    Text(res).tag(res)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var refreshRateRow: some View {
        HStack {
            Text("Refresh Rate")
            Spacer()
            Picker("", selection: $settings.refreshRate) {
                ForEach(GraphicsSettings.commonRefreshRates, id: \.self) { rate in
                    Text("\(rate) Hz").tag(rate)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var viewDistanceRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("View Distance")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(settings.viewDistance)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(settings.viewDistance) },
                    set: { settings.viewDistance = Int($0) }
                ),
                in: 177...1277,
                step: 50
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var groundEffectRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Ground Effects")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(groundEffectLabel)
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(settings.groundEffectDensity) },
                    set: { settings.groundEffectDensity = Int($0) }
                ),
                in: 0...3,
                step: 1
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var groundEffectLabel: String {
        switch settings.groundEffectDensity {
        case 0: return "Off"
        case 1: return "Low"
        case 2: return "Medium"
        default: return "High"
        }
    }

    private var weatherRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Weather")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(weatherLabel)
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(settings.weatherDensity) },
                    set: { settings.weatherDensity = Int($0) }
                ),
                in: 0...3,
                step: 1
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var weatherLabel: String {
        switch settings.weatherDensity {
        case 0: return "Off"
        case 1: return "Low"
        case 2: return "Medium"
        default: return "High"
        }
    }

    private var particleRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Particle Density")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(Int(settings.particleDensity * 100))%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $settings.particleDensity, in: 0...1, step: 0.1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
