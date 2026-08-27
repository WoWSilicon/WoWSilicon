import SwiftUI
import AppKit

struct OptionsView: View {
    @ObservedObject var viewModel: MainDashboardViewModel
    let onClose: () -> Void

    @State private var selectedTab: OptionsTab = .general
    @State private var realmlistContent: String = ""
    @State private var realmlistURL: URL? = nil
    @State private var realmlistMultipleURLs: [URL] = []
    @State private var showsAudioDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Options")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Close", role: .cancel) {
                    viewModel.completeOptionsSession()
                    onClose()
                }
            }

            HStack {
                Spacer()
                Picker("", selection: $selectedTab) {
                    ForEach(availableTabs) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize(horizontal: true, vertical: false)
                Spacer()
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .general:
                        generalSection
                    case .graphics:
                        graphicsSection
                    case .audio:
                        audioSection
                    case .realmlist:
                        realmlistSection
                    case .dependencies:
                        dependenciesSection
                    case .environment:
                        environmentSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.trailing, 18)
            }

        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            viewModel.refreshOptionAsAltStatus()
            viewModel.refreshRetinaModeStatus()
            viewModel.refreshGraphicsSettings()
            viewModel.refreshVisualCppRuntimeStatus()
            viewModel.refreshGitStatus()
            viewModel.refreshAudioOutputs()
            viewModel.beginOptionsSession()
            refreshRealmlist()
        }
        .onDisappear {
            viewModel.completeOptionsSession()
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            toggleRow(
                "Enable Metal Hud (show FPS)",
                binding: viewModel.boolBinding(\.enableMetalHud)
            )
            toggleRow(
                "Show Terminal",
                binding: viewModel.boolBinding(\.showTerminalNormally)
            )
            if viewModel.isVanillaTweaksSupported {
                toggleRow(
                    "Enable vanilla-tweaks",
                    binding: viewModel.boolBinding(\.enableVanillaTweaks)
                )
            }
            optionAsAltControls
            retinaModeControls
            rosettaX87Controls
            Divider()
                .padding(.vertical, 4)
            wineBottleControls
            Divider()
                .padding(.vertical, 4)
            telemetryControls
            Button("Check for Updates...") {
                UpdaterService.shared.checkForUpdates()
            }
            .buttonStyle(.bordered)
        }
    }

    private var graphicsSection: some View {
        GraphicsSectionView(
            settings: viewModel.graphicsSettingsBinding(),
            showsWoWSettings: viewModel.currentVersion?.supportsCustomGraphicsSettings ?? true
        )
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            audioOutputControls
            Divider()
            toggleRow(
                "Spatialize Stereo",
                binding: viewModel.spatializeStereoBinding()
            )
            toggleRow(
                "Normalize Audio",
                binding: viewModel.nightModeBinding()
            )
        }
    }

    private var availableTabs: [OptionsTab] {
        OptionsTab.allCases.filter { tab in
            tab != .realmlist || viewModel.currentVersion?.supportsRealmlist != false
        }
    }

    private func refreshRealmlist() {
        guard viewModel.currentVersion?.supportsRealmlist != false else {
            realmlistURL = nil
            realmlistMultipleURLs = []
            realmlistContent = ""
            return
        }
        guard let gamePath = viewModel.currentVersion?.gamePath else { return }
        switch RealmlistService.find(gamePath: gamePath) {
        case .none:
            realmlistURL = nil
            realmlistMultipleURLs = []
            realmlistContent = ""
        case .single(let url, let content):
            realmlistURL = url
            realmlistMultipleURLs = []
            realmlistContent = content
        case .multiple(let urls):
            realmlistURL = nil
            realmlistMultipleURLs = urls
            realmlistContent = ""
        }
    }

    private func saveRealmlist() {
        guard let url = realmlistURL else { return }
        try? RealmlistService.write(content: realmlistContent, to: url)
    }

    @ViewBuilder
    private var realmlistSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !realmlistMultipleURLs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Multiple realmlist.wtf files detected", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.headline)
                    Text("WoWSilicon found more than one realmlist.wtf in your game folder. Remove the duplicates so only one remains, then reopen this tab.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(realmlistMultipleURLs, id: \.path) { url in
                        Text(url.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Button("Refresh") { refreshRealmlist() }
                        .buttonStyle(.bordered)
                }
            } else if realmlistURL == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No realmlist.wtf found", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.headline)
                    Text("No realmlist.wtf was found in the game folder. Set the game path first, then reopen this tab.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Refresh") { refreshRealmlist() }
                        .buttonStyle(.bordered)
                }
            } else if let realmlistURL {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Realmlist")
                        .font(.headline)
                    Text(realmlistURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    TextEditor(text: $realmlistContent)
                        .font(.body.monospaced())
                        .padding(12)
                        .frame(minHeight: 80)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                        .onChange(of: realmlistContent) { saveRealmlist() }
                }
            }
        }
    }

    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Environment Variables")
                .font(.headline)

            Text("Enter one KEY=VALUE per line.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: viewModel.stringBinding(\.environmentVariables))
                .font(.body.monospaced())
                .padding(12)
                .frame(minHeight: 160)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2))
                )

            if viewModel.isVanillaTweaksSupported {
                Divider()
                    .padding(.vertical, 8)

                Text("Custom vanilla-tweaks parameters")
                    .font(.headline)

                Text("Enter one flag per line (e.g. --no-sound-in-background or --nameplatedistance 60). Each entry must begin with --flag and may include a value.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                vanillaTweaksParametersEditor
            }
        }
    }

    private var dependenciesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dependencies")
                .font(.headline)

            dependencyStatusRow(
                title: "Microsoft Visual C++ Runtime 2022",
                status: viewModel.visualCppRuntimeStatus,
                isBusy: viewModel.isDependencyInstallInProgress
            )

            Button("Install VC++ Runtime 2022") {
                viewModel.installVisualCppRuntime()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canInstallDependencies || viewModel.visualCppRuntimeStatus == .installed)

            Text(dependenciesHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .padding(.vertical, 4)

            dependencyStatusRow(
                title: "Wine Mono",
                status: viewModel.wineMonoStatus,
                isBusy: viewModel.isWineMonoInstallInProgress
            )

            Button("Install Wine Mono") {
                viewModel.installWineMono()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canInstallWineMono || viewModel.wineMonoStatus == .installed)

            Text("Provides .NET support for third-party launchers. Wine downloads the compatible package and opens its installer.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .padding(.vertical, 4)

            dependencyStatusRow(
                title: "Git",
                status: viewModel.gitStatus,
                isBusy: viewModel.isGitInstallInProgress
            )

            HStack(spacing: 12) {
                Button("Install Git") {
                    viewModel.installGit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isGitInstallInProgress || viewModel.gitStatus == .installed)

                Button("Refresh") {
                    viewModel.refreshGitStatus()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isGitInstallInProgress)
            }

            Text("Git is required for addon installs and updates. This opens Apple's Command Line Tools installer, which includes Git.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dependenciesHelpText: String {
        "Installs Microsoft's x86 Visual C++ Runtime into the selected Wine bottle using the bundled Wine runtime."
    }

    private var visualCppRuntimeStatusColor: Color {
        dependencyStatusColor(viewModel.visualCppRuntimeStatus)
    }

    private func dependencyStatusRow(title: String, status: DependencyInstallStatus, isBusy: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(2)
            Spacer()
            Text(status.text)
                .lineLimit(1)
                .foregroundStyle(dependencyStatusColor(status))
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dependencyStatusColor(_ status: DependencyInstallStatus) -> Color {
        switch status {
        case .installed:
            return .green
        case .missing, .unknown:
            return .secondary
        case .inProgress:
            return .blue
        case .error:
            return .red
        }
    }

    private enum OptionsTab: String, CaseIterable, Identifiable {
        case general
        case graphics
        case audio
        case realmlist
        case dependencies
        case environment

        var id: OptionsTab { self }
        var title: String {
            switch self {
            case .general: return "General"
            case .graphics: return "Graphics"
            case .audio: return "Audio"
            case .realmlist: return "Realmlist"
            case .dependencies: return "Dependencies"
            case .environment: return "Environment"
            }
        }
    }

    private func toggleRow(_ title: String, binding: Binding<Bool>, disabled: Bool = false) -> some View {
        Toggle(isOn: binding) {
            HStack {
                Text(title)
                Spacer()
            }
        }
        .toggleStyle(.switch)
        .disabled(disabled)
    }

    private var telemetryControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            toggleRow(
                "Share Anonymous Usage Statistics",
                binding: viewModel.telemetryEnabledBinding()
            )
            Text("Shares app version, WoW version, macOS version, renderer, x87 translation, and configured realmlist server for public aggregate stats. No IP address, username, account name, character name, file paths, or hardware identifiers are collected.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var wineBottleControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wine Bottle")
                .font(.headline)
            Text(viewModel.wineBottlePath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Show in Finder", action: viewModel.openWineBottleLocation)
                    .buttonStyle(.bordered)
                Button("Set/Change…", action: viewModel.selectWineBottleLocation)
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canChangeWineBottleLocation)
                Button("Use Default", action: viewModel.useDefaultWineBottleLocation)
                    .buttonStyle(.bordered)
                    .disabled(viewModel.usesDefaultWineBottleLocation || !viewModel.canChangeWineBottleLocation)
            }

            HStack(spacing: 10) {
                Button("Open Wine Configuration…", action: viewModel.openWineConfiguration)
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isWineConfigurationLoading)
                if viewModel.isWineConfigurationLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Open Wine Terminal…", action: viewModel.openWineTerminal)
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isWineTerminalLoading)
                if viewModel.isWineTerminalLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("The default is ~/WoWSilicon. Choose an empty folder or an existing Wine bottle. Wine Configuration uses the bundled runtime and the selected bottle.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var audioOutputControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Audio Output")
                    .font(.headline)
                    .frame(width: 120, alignment: .leading)

                audioDeviceMenu(
                    selection: viewModel.audioOutputBinding(),
                    systemTitle: "Follow macOS System Output",
                    devices: viewModel.audioOutputDevices,
                    selectedDeviceIsUnavailable: viewModel.selectedAudioOutputIsUnavailable
                )
                .frame(maxWidth: .infinity)
                .disabled(viewModel.isAudioOutputBusy)

                HStack(spacing: 8) {
                    Button(action: viewModel.testAudioOutput) {
                        Image(systemName: "speaker.wave.2")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isAudioOutputBusy)
                    .help("Play test sound")
                    .accessibilityLabel("Play test sound")

                    Button {
                        showsAudioDetails.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.bordered)
                    .help("Show active audio details")
                    .accessibilityLabel("Show active audio details")
                    .popover(isPresented: $showsAudioDetails, arrowEdge: .bottom) {
                        audioDetailsPopover
                    }

                    Button(action: viewModel.refreshAudioOutputs) {
                        ZStack {
                            Image(systemName: "arrow.clockwise")
                                .opacity(viewModel.isAudioOutputBusy ? 0 : 1)
                            if viewModel.isAudioOutputBusy {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isAudioOutputBusy)
                    .help("Refresh audio devices")
                    .accessibilityLabel("Refresh audio devices")

                }
                .frame(width: 190, alignment: .trailing)
            }

            HStack(spacing: 10) {
                Text("Audio Input")
                    .font(.headline)
                    .frame(width: 120, alignment: .leading)

                audioDeviceMenu(
                    selection: viewModel.audioInputBinding(),
                    systemTitle: "Follow macOS System Input",
                    devices: viewModel.audioInputDevices,
                    selectedDeviceIsUnavailable: viewModel.selectedAudioInputIsUnavailable
                )
                .frame(maxWidth: .infinity)
                .disabled(viewModel.isAudioOutputBusy)

                Color.clear
                    .frame(width: 190, height: 1)
            }
        }
    }

    private func audioDeviceMenu(
        selection: Binding<String>,
        systemTitle: String,
        devices: [WineAudioOutputDevice],
        selectedDeviceIsUnavailable: Bool
    ) -> some View {
        let selectedID = selection.wrappedValue
        let selectedTitle: String
        if selectedID.isEmpty {
            selectedTitle = systemTitle
        } else if let device = devices.first(where: { $0.id == selectedID }) {
            selectedTitle = device.name
        } else {
            selectedTitle = "Previously selected device (unavailable)"
        }

        return Menu {
            Button {
                selection.wrappedValue = ""
            } label: {
                if selectedID.isEmpty {
                    Label(systemTitle, systemImage: "checkmark")
                } else {
                    Text(systemTitle)
                }
            }

            Divider()

            if selectedDeviceIsUnavailable, !selectedID.isEmpty {
                Label("Previously selected device (unavailable)", systemImage: "checkmark")
                    .disabled(true)
            }

            ForEach(devices) { device in
                Button {
                    selection.wrappedValue = device.id
                } label: {
                    if selectedID == device.id {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private var audioDetailsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active Audio")
                .font(.headline)

            if let details = viewModel.audioDetails {
                audioDetailRow("Output", details.deviceName)
                audioDetailRow(
                    "Format",
                    "\(details.channelCount) ch · \(formattedSampleRate(details.sampleRate)) · \(details.bitsPerSample)-bit"
                )
            } else {
                Text("Audio details are unavailable.")
                    .foregroundStyle(.secondary)
            }

            audioDetailRow(
                "Spatial Stereo",
                viewModel.currentVersion?.settings.spatializeStereo == true ? "On" : "Off"
            )
            audioDetailRow(
                "Normalize Audio",
                viewModel.currentVersion?.settings.nightMode == true ? "On" : "Off"
            )
        }
        .padding(16)
        .frame(width: 320)
    }

    private func audioDetailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formattedSampleRate(_ sampleRate: Int) -> String {
        if sampleRate.isMultiple(of: 1_000) {
            return "\(sampleRate / 1_000) kHz"
        }
        return String(format: "%.1f kHz", Double(sampleRate) / 1_000)
    }

    private var rosettaX87Controls: some View {
        let selection = viewModel.x87BackendBinding()

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("x87 Translation")
                Spacer()
                Picker("", selection: selection) {
                    ForEach(X87Backend.allCases, id: \.self) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            Text(x87BackendDescription(selection.wrappedValue))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func x87BackendDescription(_ backend: X87Backend) -> String {
        switch backend {
        case .disabled:
            return "Uses stock Rosetta translation. This is significantly slower and intended for testing."
        case .rosettaX87:
            return "Uses rosettax87_jit for accelerated x87 translation."
        case .x87Sidecar:
            return "Runs accelerated x87 translation in an isolated helper process."
        }
    }

    private var vanillaTweaksParametersBinding: Binding<String> {
        viewModel.stringBinding(\.vanillaTweaksParameters)
    }

    private var vanillaTweaksParametersEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: vanillaTweaksParametersBinding)
                .font(.body.monospaced())
                .padding(12)
                .frame(minHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2))
                )

            if vanillaTweaksParametersBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("--no-sound-in-background\n--nameplatedistance 60")
                    .font(.body.monospaced())
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
            }
        }
    }

    private var optionAsAltControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Remap Option key as Alt key")
                .font(.headline)

            HStack(spacing: 8) {
                Text(viewModel.optionAsAltStatusText)
                    .foregroundStyle(viewModel.optionAsAltStatusColor)
                if viewModel.isOptionAsAltBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 12) {
                Button("Enable") { viewModel.enableOptionAsAlt() }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(viewModel.isOptionAsAltBusy || viewModel.optionAsAltStatus.isEnabled)

                Button("Disable") { viewModel.disableOptionAsAlt() }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isOptionAsAltBusy || viewModel.optionAsAltStatus.isDisabled)
            }

            Text("Updating the Wine registry can take several seconds. The status will refresh once the change completes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var retinaModeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("High Resolution Mode")
                .font(.headline)

            HStack(spacing: 8) {
                Text(viewModel.retinaModeStatusText)
                    .foregroundStyle(viewModel.retinaModeStatusColor)
                if viewModel.isRetinaModeBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 12) {
                Button("Enable") { viewModel.enableRetinaMode() }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(viewModel.isRetinaModeBusy || viewModel.retinaModeStatus.isEnabled)

                Button("Disable") { viewModel.disableRetinaMode() }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isRetinaModeBusy || viewModel.retinaModeStatus.isDisabled)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Cursor Size")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Cursor Size", selection: viewModel.cursorSizeBinding()) {
                        ForEach(MainDashboardViewModel.allowedCursorSizeMultipliers, id: \.self) { value in
                            Text("\(value)x").tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }

            Text("Can cause fonts to render smaller, but game will run at native resolution.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}
