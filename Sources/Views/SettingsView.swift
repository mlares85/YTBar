import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var vm: AppViewModel

    var body: some View {
        List {
            apiSection
            authSection
            audioSection
            playbackSection
            layoutSection
            appearanceSection
            CacheSettingsView()
            aboutSection
            diagnosticsSection
            quitSection
        }
        .listStyle(.inset)
    }

    @State private var showSaved = false

    private var apiSection: some View {
        Section("Google API") {
            apiLinks
            VStack(alignment: .leading, spacing: 6) {
                Text("Client ID")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    TextField("Client ID", text: $vm.configClientID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                    pasteButton { vm.configClientID = $0 }
                }
                Text("Client Secret")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    SecureField("Client Secret", text: $vm.configClientSecret)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                    pasteButton { vm.configClientSecret = $0 }
                }
                HStack {
                    Button("Save") { saveConfig() }
                        .font(.system(size: 12))
                        .disabled(vm.configClientID.isEmpty || vm.configClientSecret.isEmpty)
                        .help("Save Google API credentials")
                    if showSaved {
                        Text("Saved!")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    private var apiLinks: some View {
        HStack(spacing: 12) {
            Button {
                let url = URL(string: "https://console.cloud.google.com/apis/credentials")!
                NSWorkspace.shared.open(url)
            } label: {
                Label("API Dashboard", systemImage: "globe")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Open Google API Dashboard")
            .help("Open Google Cloud Console credentials page")

            Button { openSetupGuide() } label: {
                Label("Setup Guide", systemImage: "questionmark.circle")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Open setup guide")
            .help("Open the Google API setup guide")
        }
    }

    private func openSetupGuide() {
        guard let url = Bundle.module.url(
            forResource: "setup-guide", withExtension: "html"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func pasteButton(into setter: @escaping (String) -> Void) -> some View {
        Button {
            if let str = NSPasteboard.general.string(forType: .string) {
                setter(str.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } label: {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 11))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Paste from clipboard")
        .help("Paste from clipboard")
    }

    private func saveConfig() {
        vm.onSaveConfig?(vm.configClientID, vm.configClientSecret)
        showSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showSaved = false
        }
    }

    private var authSection: some View {
        Section("Account") {
            if vm.isAuthenticated {
                signOutRow
            } else {
                signInRow
            }
        }
    }

    private var signInRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { vm.signIn(); vm.showToast(.info, message: "Auth code copied to clipboard") }) {
                if vm.isSigningIn && vm.deviceCode == nil {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Sign In with Google")
                }
            }
            .disabled(vm.isSigningIn)
            .accessibilityLabel("Sign in with Google")
            .help("Sign in with Google")
            if !vm.isSigningIn {
                Text("A browser will open and an auth code will be copied to your clipboard — just paste it when prompted.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let err = vm.signInError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            deviceCodeView
        }
    }

    @ViewBuilder
    private var deviceCodeView: some View {
        if let code = vm.deviceCode {
            VStack(alignment: .leading, spacing: 6) {
                Text("A browser window opened. Paste the code when prompted.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(code)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .textSelection(.enabled)
                        .accessibilityLabel("Device code: \(code)")
                }
                Button(action: { copyCode(code) }) {
                    Label("Copy Code Again", systemImage: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Copy auth code to clipboard")
                .help("Copy auth code to clipboard in case you overwrote it")
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Waiting for authorization...")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func copyCode(_ code: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        vm.showToast(.success, message: "Code copied to clipboard")
    }

    private var signOutRow: some View {
        HStack {
            Label("Signed In", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
            Spacer()
            Button("Sign Out", action: vm.signOut)
                .font(.system(size: 12))
                .help("Sign out of your Google account")
        }
    }

    private var audioSection: some View {
        Section("Audio") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Streaming quality")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Picker("Streaming quality", selection: $vm.audioQuality) {
                    ForEach(AudioQuality.allCases, id: \.self) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: vm.audioQuality) {
                    vm.onSetAudioQuality?(vm.audioQuality)
                }
                .accessibilityLabel("Streaming audio quality")
            }
        }
    }

    private var playbackSection: some View {
        Section("Playback") {
            Toggle(
                "Resume playback on launch",
                isOn: resumeSessionBinding
            )
            .accessibilityLabel("Resume queue and track position when the app restarts")
            .help("Restore the queue, current track, and playback position from your last session.")
            Toggle(
                "Back button jumps to previous song",
                isOn: restartEnabledBinding
            )
            .accessibilityLabel("Back button jumps to previous song when pressed early")
            thresholdRow
            Toggle(
                "Auto-extend queue with radio at end",
                isOn: autoExtendBinding
            )
            .accessibilityLabel("Auto-extend queue with a radio mix when nearing the end")
            .help("When the queue has fewer than 5 upcoming tracks, fetch a radio mix seeded from the current song and append it (deduped).")
        }
    }

    private var resumeSessionBinding: Binding<Bool> {
        Binding(
            get: { vm.resumeSessionEnabled },
            set: {
                vm.resumeSessionEnabled = $0
                vm.onSetResumeSession?($0)
            }
        )
    }

    private var autoExtendBinding: Binding<Bool> {
        Binding(
            get: { vm.autoExtendQueueEnabled },
            set: {
                vm.autoExtendQueueEnabled = $0
                vm.onSetAutoExtendQueueEnabled?($0)
            }
        )
    }

    private var thresholdRow: some View {
        HStack(spacing: 8) {
            Text("Jump to previous if within")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Stepper(
                value: thresholdBinding,
                in: 0...60,
                step: 1
            ) {
                Text("\(Int(vm.previousRestartThreshold))s")
                    .font(.system(size: 11))
                    .monospacedDigit()
            }
            .accessibilityLabel("Previous-song jump threshold in seconds")
        }
        .disabled(!vm.previousRestartEnabled)
    }

    private var restartEnabledBinding: Binding<Bool> {
        Binding(
            get: { vm.previousRestartEnabled },
            set: {
                vm.previousRestartEnabled = $0
                vm.onSetPreviousRestartEnabled?($0)
            }
        )
    }

    private var thresholdBinding: Binding<Double> {
        Binding(
            get: { vm.previousRestartThreshold },
            set: {
                vm.previousRestartThreshold = $0
                vm.onSetPreviousRestartThreshold?($0)
            }
        )
    }

    private var layoutSection: some View {
        Section("Layout") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(
                    "Hide browse panel by default",
                    isOn: autoHideBinding
                )
                .accessibilityLabel("Hide browse panel until a nav button is clicked")
                Text("When on, the Search/Library/Liked/Queue area stays hidden until you click a nav button. Resets when the popover closes.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var autoHideBinding: Binding<Bool> {
        Binding(
            get: { vm.autoHideBrowsePanel },
            set: {
                vm.autoHideBrowsePanel = $0
                vm.onSetAutoHideBrowsePanel?($0)
            }
        )
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Window opacity: \(Int(vm.windowOpacity * 100))%")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Slider(
                    value: opacityBinding,
                    in: 0.5...1.0,
                    step: 0.05
                )
                .accessibilityLabel("Window opacity")
            }
        }
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { vm.windowOpacity },
            set: { vm.setWindowOpacity($0) }
        )
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("YTBar")
                    .font(.system(size: 12))
                Spacer()
                Text(AppVersion.display)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Button("Check for yt-dlp updates", action: vm.checkForUpdates)
                .font(.system(size: 12))
                .accessibilityLabel("Check for yt-dlp updates")
                .help("Check for yt-dlp updates")
        }
    }

    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            Toggle("Debug logging", isOn: debugLoggingBinding)
                .accessibilityLabel("Enable debug logging")
            Text("Writes diagnostic info to ~/Library/Logs/YTBar/ytbar.log")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Export Debug Log") { exportDebugLog() }
                .font(.system(size: 12))
                .disabled(!DebugLogger.shared.logFileExists)
                .accessibilityLabel("Export debug log file")
                .help("Save a copy of the debug log to a location you choose")
        }
    }

    private var debugLoggingBinding: Binding<Bool> {
        Binding(
            get: { vm.debugLoggingEnabled },
            set: {
                vm.debugLoggingEnabled = $0
                vm.onSetDebugLogging?($0)
            }
        )
    }

    private func exportDebugLog() {
        guard let content = DebugLogger.shared.readLogContents() else { return }
        let version = AppVersion.display
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let date = ISO8601DateFormatter().string(from: Date())
        let header = """
        YTBar Debug Log Export
        Date: \(date)
        App Version: \(version)
        macOS: \(os)
        ---

        """
        let full = header + content
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ytbar-debug-log.txt"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? full.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private var quitSection: some View {
        Section {
            Button("Quit YTBar", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 12))
            .accessibilityLabel("Quit application")
            .help("Quit YTBar (⌘Q)")
        }
    }
}
