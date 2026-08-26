import SwiftUI
import AppKit

struct MainDashboardView: View {
    @ObservedObject var viewModel: MainDashboardViewModel
    @State private var showOptionsSheet = false
    @State private var showPatchAlert = false
    @State private var patchAlertTitle = "Patching"
    @State private var patchAlertMessage = ""
    @State private var vanillaTweaksAlert = false
    @State private var versionMismatchAlert = false
    @State private var existingWineAlert = false
    @State private var troubleshootingViewModel: TroubleshootingViewModel?
    @State private var addonManagerViewModel: AddonManagerViewModel?
    @State private var modManagerViewModel: ModManagerViewModel?

    var body: some View {
        ZStack(alignment: .topLeading) {
            DashboardBackgroundView()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HeaderView(
                    title: viewModel.versionDisplayName,
                    subtitle: viewModel.subtitleText,
                    versions: viewModel.versions,
                    currentVersionID: viewModel.currentVersionID,
                    onSelectVersion: viewModel.selectVersion,
                    onAddVersion: viewModel.addVersion,
                    onRemoveVersion: viewModel.removeVersion,
                    wantsLauncher: viewModel.currentVersionWantsLauncher,
                    hasLauncher: viewModel.currentVersionHasLauncher,
                    launcherName: viewModel.currentVersionLauncherName,
                    isLauncherLoading: viewModel.isLauncherLoading,
                    onOpenLauncher: viewModel.launchThirdPartyLauncher,
                    onInstallLauncher: viewModel.installLauncher,
                    wineProcessCount: viewModel.wineProcessCount,
                    isForceQuittingWine: viewModel.isForceQuittingWine,
                    onForceQuitWine: viewModel.forceQuitWine
                )
                .padding(.top, 24)
                .padding(.horizontal, 32)

                MainContentView(
                    gamePathLabel: viewModel.currentVersion?.isWorldOfWarcraft == false ? "Executable:" : "Game Path:",
                    gamePatchLabel: viewModel.currentVersion?.isWorldOfWarcraft == false ? "D3D9 Patch:" : "Game Patch:",
                    gameStatus: viewModel.gamePathStatus,
                    gamePatchStatus: viewModel.gamePatchStatus,
                    onSelectGamePath: viewModel.selectGamePath,
                    onOpenGamePath: viewModel.openGameDirectory,
                    canOpenGamePath: viewModel.canOpenGameDirectory,
                    onClearGamePath: viewModel.clearGamePath,
                    canClearGamePath: viewModel.canClearGamePath,
                    isGamePatched: viewModel.isGamePatched,
                    isGamePatchActionable: viewModel.isGamePatchActionable,
                    isGameOperationInProgress: viewModel.isGameOperationInProgress,
                    onPatchGame: viewModel.patchGame,
                    onUnpatchGame: viewModel.unpatchGame,
                    wantsLauncher: viewModel.currentVersionWantsLauncher,
                    launcherPathStatus: viewModel.launcherPathStatus,
                    onSelectLauncherPath: viewModel.selectLauncherPath,
                    onOpenLauncherPath: viewModel.openLauncherDirectory,
                    canOpenLauncherPath: viewModel.canOpenLauncherDirectory,
                    onClearLauncherPath: viewModel.clearLauncherPath,
                    canClearLauncherPath: viewModel.canClearLauncherPath
                )
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(minHeight: 0, maxHeight: .infinity)

                BottomBarView(
                    supportsAddons: viewModel.supportsAddons,
                    supportsMods: viewModel.supportsMods,
                    onOptions: { showOptionsSheet = true },
                    onTroubleshooting: {
                        troubleshootingViewModel = TroubleshootingViewModel(
                            context: viewModel.makeTroubleshootingContext(),
                            onGamePathSelected: viewModel.setGamePath
                        )
                    },
                    onAddons: {
                        addonManagerViewModel = AddonManagerViewModel(gamePath: viewModel.currentVersion?.gamePath)
                    },
                    onMods: {
                        guard let version = viewModel.currentVersion else { return }
                        modManagerViewModel = ModManagerViewModel(version: version, supportsDLL: viewModel.supportsMods)
                    },
                    onPlay: viewModel.launchGame,
                    canPlay: viewModel.canLaunch,
                    isBusy: viewModel.isGameOperationInProgress
                        || viewModel.isForceQuittingWine
                        || viewModel.isCheckingWineProcesses
                )
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }

        }
        .task {
            await viewModel.monitorWineProcesses()
        }
        .sheet(isPresented: $showOptionsSheet) {
            OptionsView(
                viewModel: viewModel,
                onClose: { showOptionsSheet = false }
            )
            .frame(width: 780, height: 540)
        }
        .alert(patchAlertTitle, isPresented: $showPatchAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(patchAlertMessage)
        }
        .sheet(item: $troubleshootingViewModel) { vm in
            TroubleshootingView(viewModel: vm) {
                troubleshootingViewModel = nil
            }
        }
        .sheet(item: $addonManagerViewModel) { vm in
            AddonManagerView(viewModel: vm) {
                addonManagerViewModel = nil
            }
        }
        .sheet(item: $modManagerViewModel) { vm in
            ModManagerView(viewModel: vm) {
                modManagerViewModel = nil
            }
        }
        .alert("Migrate Settings?", isPresented: $viewModel.shouldShowMigrationPrompt) {
            Button("Skip", role: .cancel) {
                viewModel.handleMigration(migrate: false)
            }
            Button("Migrate") {
                viewModel.handleMigration(migrate: true)
            }
        } message: {
            Text("A previous TurtleSilicon installation was detected. Would you like to migrate your settings to WoWSilicon?")
        }
        .alert("Copy Existing Wine Bottle?", isPresented: $viewModel.shouldShowWineBottleMigrationPrompt) {
            Button("Start Fresh", role: .cancel) {
                viewModel.handleWineBottleMigration(copyLegacyBottle: false)
            }
            Button("Copy Bottle") {
                viewModel.handleWineBottleMigration(copyLegacyBottle: true)
            }
        } message: {
            Text("An existing ~/.wine bottle was found. WoWSilicon can copy it to ~/WoWSilicon. The original bottle will be kept, so other Wine applications can continue using it.")
        }
        .alert("Share Anonymous Stats?", isPresented: $viewModel.shouldShowTelemetryConsentPrompt) {
            Button("No Thanks", role: .cancel) {
                viewModel.handleTelemetryConsent(accepted: false)
            }
            Button("Share Anonymous Stats") {
                viewModel.handleTelemetryConsent(accepted: true)
            }
        } message: {
            Text("Help us show anonymous WoWSilicon usage stats, like how many people use the launcher, which WoW versions are used, macOS version, renderer, x87 translation, and configured realmlist server. We do not collect your IP address, username, account name, character name, file paths, or hardware identifiers.")
        }
        .alert("Apply vanilla-tweaks?", isPresented: $vanillaTweaksAlert) {
            Button("Cancel", role: .cancel) {
                viewModel.handleVanillaTweaksConfirmation(apply: false)
            }
            Button("Apply", role: .none) {
                viewModel.handleVanillaTweaksConfirmation(apply: true)
            }
        } message: {
            Text("WoW_tweaked.exe was not found. WoWSilicon can run vanilla-tweaks automatically before launching. Proceed?")
        }
        .alert("Build mismatch detected", isPresented: $versionMismatchAlert) {
            Button("Cancel", role: .cancel) {
                viewModel.handleVersionMismatchConfirmation(regenerate: false)
            }
            Button("Re-generate", role: .none) {
                viewModel.handleVersionMismatchConfirmation(regenerate: true)
            }
        } message: {
            if let data = viewModel.versionMismatchData {
                Text("WoW.exe (\(data.base)) and WoW_tweaked.exe (\(data.tweaked)) have different build numbers.\n\nWould you like to re-generate WoW_tweaked.exe?")
            } else {
                Text("Your tweaked executable is out of sync with WoW.exe. Would you like to re-generate it?")
            }
        }
        .alert("Wine Is Already Running", isPresented: $existingWineAlert) {
            Button("Cancel", role: .cancel) {
                viewModel.handleExistingWineBeforeLaunch(cleanUp: nil)
            }
            Button("Launch Another") {
                viewModel.handleExistingWineBeforeLaunch(cleanUp: false)
            }
            Button("Close and Launch", role: .destructive) {
                viewModel.handleExistingWineBeforeLaunch(cleanUp: true)
            }
        } message: {
            let count = viewModel.wineProcessCount
            let noun = count == 1 ? "process is" : "processes are"
            Text("\(count) Wine-related \(noun) already running. You can close the existing Wine session first or launch another game instance.")
        }
        .onChange(of: viewModel.patchFeedback) { _, feedback in
            guard let feedback else { return }
            patchAlertTitle = feedback.title
            patchAlertMessage = feedback.message
            showPatchAlert = true
            viewModel.clearPatchFeedback()
        }
        .onChange(of: viewModel.shouldShowVanillaTweaksPrompt) { _, shouldShow in
            vanillaTweaksAlert = shouldShow
        }
        .onChange(of: viewModel.shouldShowVersionMismatchPrompt) { _, shouldShow in
            versionMismatchAlert = shouldShow
        }
        .onChange(of: viewModel.shouldShowExistingWinePrompt) { _, shouldShow in
            existingWineAlert = shouldShow
        }
        .sheet(isPresented: Binding.constant(viewModel.isApplyingVanillaTweaks)) {
            VanillaTweaksLoadingView()
                .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.isGameOperationInProgress && !viewModel.isApplyingVanillaTweaks && !viewModel.isUnpatchingOperation },
            set: { _ in }
        )) {
            PatchingLoadingView()
                .interactiveDismissDisabled(true)
        }
    }
}

struct PatchingLoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .controlSize(.large)
            
            Text("Patching...")
                .font(.headline)
            
            Text("Please wait while the patch is being applied.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(minWidth: 320)
    }
}

struct VanillaTweaksLoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .controlSize(.large)

            Text("Applying vanilla-tweaks...")
                .font(.headline)

            Text("Please wait while vanilla-tweaks is being applied to your game.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(minWidth: 320)
    }
}

struct HeaderView: View {
    let title: String
    let subtitle: String
    let versions: [GameVersion]
    let currentVersionID: String
    let onSelectVersion: (String) -> Void
    let onAddVersion: (String, String, Bool) -> Void
    let onRemoveVersion: (String) -> Void
    let wantsLauncher: Bool
    let hasLauncher: Bool
    let launcherName: String
    let isLauncherLoading: Bool
    let onOpenLauncher: () -> Void
    let onInstallLauncher: () -> Void
    let wineProcessCount: Int
    let isForceQuittingWine: Bool
    let onForceQuitWine: () -> Void
    @State private var showVersionPicker = false
    @State private var showAddVersionSheet = false
    @State private var showForceQuitConfirm = false

    var body: some View {
        VStack(spacing: 16) {
            LogoView(currentVersionID: currentVersionID)

            AppVersionBadge(version: appVersion)

            HStack(spacing: 8) {
                Button {
                    showForceQuitConfirm = true
                } label: {
                    HStack(spacing: 7) {
                        if isForceQuittingWine {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Circle()
                                .fill(wineProcessCount > 0 ? Color.orange : Color.secondary.opacity(0.45))
                                .frame(width: 7, height: 7)
                        }

                        Text(wineProcessLabel)
                            .font(.caption.weight(.semibold))

                        if wineProcessCount > 0 && !isForceQuittingWine {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.red)
                        }
                    }
                    .foregroundStyle(wineProcessCount > 0 ? Color.primary : Color.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 27)
                    .background(.thinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(wineProcessCount > 0 ? 0.16 : 0.08))
                    }
                }
                .buttonStyle(.plain)
                .disabled(wineProcessCount == 0 || isForceQuittingWine)
                .help(wineProcessHelp)
                .alert("Force Quit Wine?", isPresented: $showForceQuitConfirm) {
                    Button("Cancel", role: .cancel) { }
                    Button("Force Quit", role: .destructive) { onForceQuitWine() }
                } message: {
                    Text("This will immediately force quit all detected Wine processes, including any running game or other Wine application. Use it when Wine remains active after the game closes or the game has frozen.")
                }

                Button {
                    showVersionPicker = true
                } label: {
                    VersionMenuLabel(title: title)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showVersionPicker, arrowEdge: .bottom) {
                    VersionPickerPopover(
                        versions: versions,
                        currentVersionID: currentVersionID,
                        onSelect: { id in
                            showVersionPicker = false
                            onSelectVersion(id)
                        },
                        onDismiss: { showVersionPicker = false },
                        onRemove: { id in
                            showVersionPicker = false
                            onRemoveVersion(id)
                        }
                    )
                    .frame(minWidth: 260)
                }

                Button {
                    showAddVersionSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Add a version profile")
                .sheet(isPresented: $showAddVersionSheet) {
                    AddVersionSheet { name, baseID, wantsLauncher in
                        showAddVersionSheet = false
                        onAddVersion(name, baseID, wantsLauncher)
                    } onCancel: {
                        showAddVersionSheet = false
                    }
                }

                if wantsLauncher {
                    if hasLauncher {
                        Button(action: onOpenLauncher) {
                            HStack(spacing: 6) {
                                if isLauncherLoading {
                                    ProgressView()
                                        .controlSize(.mini)
                                }
                                Text(isLauncherLoading ? "Opening…" : launcherName)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isLauncherLoading)
                    } else {
                        Button("Install Launcher…", action: onInstallLauncher)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }

            Text(subtitle)
                .font(.callout)
                .italic()
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var wineProcessLabel: String {
        if isForceQuittingWine {
            return "Stopping Wine…"
        }
        if wineProcessCount == 0 {
            return "Wine idle"
        }
        return "Wine · \(wineProcessCount)"
    }

    private var wineProcessHelp: String {
        if wineProcessCount == 0 {
            return "No Wine processes detected"
        }
        let noun = wineProcessCount == 1 ? "process is" : "processes are"
        return "\(wineProcessCount) Wine-related \(noun) running. Click to force quit them."
    }
}

struct MainContentView: View {
    let gamePathLabel: String
    let gamePatchLabel: String
    let gameStatus: StatusValue
    let gamePatchStatus: StatusValue
    let onSelectGamePath: () -> Void
    let onOpenGamePath: () -> Void
    let canOpenGamePath: Bool
    let onClearGamePath: () -> Void
    let canClearGamePath: Bool
    let isGamePatched: Bool
    let isGamePatchActionable: Bool
    let isGameOperationInProgress: Bool
    let onPatchGame: () -> Void
    let onUnpatchGame: () -> Void
    let wantsLauncher: Bool
    let launcherPathStatus: StatusValue
    let onSelectLauncherPath: () -> Void
    let onOpenLauncherPath: () -> Void
    let canOpenLauncherPath: Bool
    let onClearLauncherPath: () -> Void
    let canClearLauncherPath: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            VStack(alignment: .leading, spacing: 12) {
                if wantsLauncher {
                    PathRow(
                        label: "Launcher Path:",
                        status: launcherPathStatus,
                        buttonTitle: "Set/Change",
                        onOpen: onOpenLauncherPath,
                        canOpen: canOpenLauncherPath,
                        onClear: onClearLauncherPath,
                        canClear: canClearLauncherPath,
                        action: onSelectLauncherPath
                    )
                }
                PathRow(
                    label: gamePathLabel,
                    status: gameStatus,
                    buttonTitle: "Set/Change",
                    onOpen: onOpenGamePath,
                    canOpen: canOpenGamePath,
                    onClear: onClearGamePath,
                    canClear: canClearGamePath,
                    action: onSelectGamePath
                )
            }

            Divider()
                .opacity(0.8)

            VStack(alignment: .leading, spacing: 12) {
                PatchRow(
                    label: gamePatchLabel,
                    status: gamePatchStatus,
                    primaryActionTitle: "Patch",
                    secondaryActionTitle: "Unpatch",
                    primaryDisabled: isGameOperationInProgress || !isGamePatchActionable || isGamePatched,
                    secondaryDisabled: isGameOperationInProgress || !isGamePatchActionable || !isGamePatched,
                    primaryAction: onPatchGame,
                    secondaryAction: onUnpatchGame
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .foregroundStyle(.foreground)
                .opacity(0.04)
        }
    }
}

struct LogoView: View {
    let currentVersionID: String

    var body: some View {
        Group {
            if let logo = iconImage(for: currentVersionID) {
                Image(nsImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
            } else {
                Image(systemName: "tortoise.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white, lineWidth: 3)
        }
        .compositingGroup()
        .shadow(radius: 12)
    }
}

struct PathRow: View {
    let label: String
    let status: StatusValue
    let buttonTitle: String
    let onOpen: () -> Void
    let canOpen: Bool
    let onClear: () -> Void
    let canClear: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 150, alignment: .leading)

            StatusLabel(value: status)

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button(action: onOpen) {
                    Image(systemName: "folder")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canOpen)
                .help("Open in Finder")
                .accessibilityLabel("Open in Finder")

                Button(role: .destructive, action: onClear) {
                    Image(systemName: "trash")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canClear)
                .help("Clear selected path (files are not deleted)")
                .accessibilityLabel("Clear selected path")

                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
    }
}

struct PatchRow: View {
    let label: String
    let status: StatusValue
    let primaryActionTitle: String
    let secondaryActionTitle: String
    let primaryDisabled: Bool
    let secondaryDisabled: Bool
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 150, alignment: .leading)

            StatusLabel(value: status)

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button(primaryActionTitle, action: primaryAction)
                    .buttonStyle(.bordered)
                    .disabled(primaryDisabled)

                Button(secondaryActionTitle, action: secondaryAction)
                    .buttonStyle(.bordered)
                    .disabled(secondaryDisabled)
            }
        }
    }
}

struct BottomBarView: View {
    let supportsAddons: Bool
    let supportsMods: Bool
    let onOptions: () -> Void
    let onTroubleshooting: () -> Void
    let onAddons: () -> Void
    let onMods: () -> Void
    let onPlay: () -> Void
    let canPlay: Bool
    let isBusy: Bool
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: 12) {
                BottomActionButton(title: "Options", action: onOptions)
                BottomActionButton(title: "Troubleshooting", action: onTroubleshooting)
                BottomActionButton(title: "Addons", action: onAddons, disabled: !supportsAddons)
                BottomActionButton(title: "Mods", action: onMods, disabled: !supportsMods)
            }

            Spacer(minLength: 20)

            Button("Play", action: onPlay)
                .buttonStyle(.play)
                .disabled(!canPlay || isBusy)
        }
    }
}

struct StatusLabel: View {
    let value: StatusValue

    var body: some View {
        Text(value.text)
            .font(.callout)
            .fontWeight(.semibold)
            .foregroundStyle(value.level.color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VersionMenuLabel: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            Image(systemName: "chevron.down")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.trailing, 16)
        }
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: .capsule)
    }
}

private struct AppVersionBadge: View {
    let version: String

    var body: some View {
        Text("\(version)")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: .capsule)
    }
}

private struct BottomActionButton: View {
    let title: String
    let action: () -> Void
    var disabled: Bool = false

    var body: some View {
        Button(title, action: action)
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 6)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(disabled)
    }
}

private struct AddVersionSheet: View {
    let onAdd: (String, String, Bool) -> Void
    let onCancel: () -> Void

    private let baseOptions: [(id: String, label: String)] = [
        ("vanillasilicon", "VanillaSilicon (1.12.1)"),
        ("burningsilicon", "BurningSilicon (2.4.3)"),
        ("wrathsilicon", "WrathSilicon (3.3.5a)"),
        (VersionManager.genericD3D9TemplateID, "Non-WoW game (32-bit D3D9)")
    ]

    @State private var customName: String = ""
    @State private var selectedBaseID: String = "vanillasilicon"
    @State private var useLauncher: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Version Profile")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Profile Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Name of the profile", text: $customName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Based on")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedBaseID) {
                    ForEach(baseOptions, id: \.id) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .pickerStyle(.radioGroup)
                if selectedBaseID == VersionManager.genericD3D9TemplateID {
                    Text("For standalone 32-bit Direct3D 9 games. Select the game's .exe after creating the profile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if selectedBaseID != VersionManager.genericD3D9TemplateID {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Use third-party launcher", isOn: $useLauncher)
                    if useLauncher {
                        Text("You can install the launcher after creating this profile.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    let name = customName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    onAdd(
                        name,
                        selectedBaseID,
                        selectedBaseID == VersionManager.genericD3D9TemplateID ? false : useLauncher
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
        .animation(.default, value: useLauncher)
        .animation(.default, value: selectedBaseID)
    }
}

private struct VersionPickerPopover: View {
    let versions: [GameVersion]
    let currentVersionID: String
    let onSelect: (String) -> Void
    let onDismiss: () -> Void
    let onRemove: (String) -> Void

    private let defaultIDs = Set(VersionManager.defaultVersions.keys)

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                HStack {
                    Button {
                        onSelect(version.id)
                        onDismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(version.displayName)
                                    .font(.system(size: 16, weight: version.id == currentVersionID ? .semibold : .regular))

                                OptimizationIndicator(level: version.optimizationLevel)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if version.id == currentVersionID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)

                    if !defaultIDs.contains(version.id) {
                        Button {
                            onRemove(version.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                    }
                }

                if index < versions.count - 1 {
                    Divider()
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

private struct OptimizationIndicator: View {
    let level: OptimizationLevel

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            HStack(spacing: 4) {
                Text("Performance: \(level.rawValue.capitalized)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                if level == .low {
                    Text("BETA")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
            }
        }
    }

    var color: Color {
        switch level {
        case .high: return .green
        case .mid: return .yellow
        case .low: return .red
        }
    }
}
