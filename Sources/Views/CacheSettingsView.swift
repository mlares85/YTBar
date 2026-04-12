import SwiftUI

struct CacheSettingsView: View {
    @EnvironmentObject private var vm: AppViewModel

    var body: some View {
        Section("Cache") {
            enableToggle
            if vm.cacheConfig.isEnabled {
                usageDisplay
                sizeSlider
                thresholdStepper
                qualityPicker
                clearButton
            }
        }
    }

    private var enableToggle: some View {
        Toggle("Enable local caching", isOn: $vm.cacheConfig.isEnabled)
            .font(.system(size: 12))
            .onChange(of: vm.cacheConfig.isEnabled) {
                vm.saveCacheConfig()
            }
            .accessibilityLabel("Enable local audio caching")
    }

    private var usageDisplay: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Cache Usage")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(usageText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: usageFraction)
                .progressViewStyle(.linear)
                .accessibilityLabel("Cache usage \(usageText)")
        }
    }

    private var sizeSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Max cache size: \(vm.cacheConfig.maxSizeMB) MB")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Slider(
                value: sizeMBBinding,
                in: 100...2000,
                step: 100
            )
            .onChange(of: vm.cacheConfig.maxSizeMB) {
                vm.saveCacheConfig()
            }
            .accessibilityLabel("Maximum cache size")
        }
    }

    private var thresholdStepper: some View {
        Stepper(
            "Auto-cache after \(vm.cacheConfig.autoCacheThreshold) plays",
            value: $vm.cacheConfig.autoCacheThreshold,
            in: 1...20
        )
        .font(.system(size: 12))
        .onChange(of: vm.cacheConfig.autoCacheThreshold) {
            vm.saveCacheConfig()
        }
        .accessibilityLabel("Auto-cache play count threshold")
    }

    private var qualityPicker: some View {
        Picker("Download quality", selection: $vm.cacheConfig.downloadQuality) {
            ForEach(DownloadQuality.allCases, id: \.self) { quality in
                Text(quality.displayName).tag(quality)
            }
        }
        .pickerStyle(.segmented)
        .font(.system(size: 12))
        .onChange(of: vm.cacheConfig.downloadQuality) {
            vm.saveCacheConfig()
        }
        .accessibilityLabel("Download audio quality")
    }

    @State private var showClearConfirm = false

    private var clearButton: some View {
        Button("Clear Cache", role: .destructive) {
            showClearConfirm = true
        }
        .font(.system(size: 12))
        .alert("Clear Cache?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { vm.clearCache() }
        } message: {
            Text("All cached audio files will be deleted.")
        }
        .accessibilityLabel("Clear all cached audio files")
        .help("Delete all cached audio files")
    }
}

// MARK: - Computed

private extension CacheSettingsView {
    var usageText: String {
        "\(vm.cacheUsageMB) / \(vm.cacheConfig.maxSizeMB) MB"
    }

    var usageFraction: Double {
        guard vm.cacheConfig.maxSizeMB > 0 else { return 0 }
        return min(
            Double(vm.cacheUsageMB) / Double(vm.cacheConfig.maxSizeMB),
            1.0
        )
    }

    var sizeMBBinding: Binding<Double> {
        Binding(
            get: { Double(vm.cacheConfig.maxSizeMB) },
            set: { vm.cacheConfig.maxSizeMB = Int($0) }
        )
    }
}
