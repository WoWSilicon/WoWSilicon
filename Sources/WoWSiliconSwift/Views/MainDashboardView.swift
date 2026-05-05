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
                    onForceQuitWine: viewModel.forceQuitWine
                )
                .padding(.top, 24)
                .padding(.horizontal, 32)

                MainContentView(
                    gameStatus: viewModel.gamePathStatus,
                    crossOverStatus: viewModel.crossOverPathStatus,
                    gamePatchStatus: viewModel.gamePatchStatus,
                    crossOverPatchStatus: viewModel.crossOverPatchStatus,
                    onSelectGamePath: viewModel.selectGamePath,
                    onSelectCrossOverPath: viewModel.selectCrossOverPath,
                    isGamePatched: viewModel.isGamePatched,
                    isGamePatchActionable: viewModel.isGamePatchActionable,
                    isCrossOverPatched: viewModel.isCrossOverPatched,
                    isCrossOverPatchActionable: viewModel.isCrossOverPatchActionable,
                    isGameOperationInProgress: viewModel.isGameOperationInProgress,
                    onPatchGame: viewModel.patchGame,
                    onUnpatchGame: viewModel.unpatchGame,
                    onPatchCrossOver: viewModel.patchCrossOver,
                    onUnpatchCrossOver: viewModel.unpatchCrossOver,
                    wantsLauncher: viewModel.currentVersionWantsLauncher,
                    launcherPathStatus: viewModel.launcherPathStatus,
                    onSelectLauncherPath: viewModel.selectLauncherPath
                )
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(minHeight: 0, maxHeight: .infinity)

                BottomBarView(
                    supportsMods: viewModel.supportsMods,
                    onOptions: { showOptionsSheet = true },
                    onTroubleshooting: {
                        troubleshootingViewModel = TroubleshootingViewModel(
                            context: viewModel.makeTroubleshootingContext()
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
                )
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }

        }
        .sheet(isPresented: $showOptionsSheet) {
            OptionsView(
                viewModel: viewModel,
                onClose: { showOptionsSheet = false }
            )
            .frame(minWidth: 520, minHeight: 500)
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
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.red)
                }
                .buttonStyle(.plain)
                .help("Force quit Wine session")
                .alert("Force Quit Wine?", isPresented: $showForceQuitConfirm) {
                    Button("Cancel", role: .cancel) { }
                    Button("Force Quit", role: .destructive) { onForceQuitWine() }
                } message: {
                    Text("This will immediately force quit all Wine processes and the wineserver. Useful when the game has frozen.")
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
}

struct MainContentView: View {
    let gameStatus: StatusValue
    let crossOverStatus: StatusValue
    let gamePatchStatus: StatusValue
    let crossOverPatchStatus: StatusValue
    let onSelectGamePath: () -> Void
    let onSelectCrossOverPath: () -> Void
    let isGamePatched: Bool
    let isGamePatchActionable: Bool
    let isCrossOverPatched: Bool
    let isCrossOverPatchActionable: Bool
    let isGameOperationInProgress: Bool
    let onPatchGame: () -> Void
    let onUnpatchGame: () -> Void
    let onPatchCrossOver: () -> Void
    let onUnpatchCrossOver: () -> Void
    let wantsLauncher: Bool
    let launcherPathStatus: StatusValue
    let onSelectLauncherPath: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            VStack(alignment: .leading, spacing: 12) {
                if wantsLauncher {
                    PathRow(
                        label: "Launcher Path:",
                        status: launcherPathStatus,
                        buttonTitle: "Set/Change",
                        action: onSelectLauncherPath
                    )
                }
                PathRow(
                    label: "CrossOver:",
                    status: crossOverStatus,
                    buttonTitle: "Set/Change",
                    action: onSelectCrossOverPath
                )
                PathRow(
                    label: "Game Path:",
                    status: gameStatus,
                    buttonTitle: "Set/Change",
                    action: onSelectGamePath
                )
            }

            Divider()
                .opacity(0.8)

            VStack(alignment: .leading, spacing: 12) {
                PatchRow(
                    label: "CrossOver Patch:",
                    status: crossOverPatchStatus,
                    primaryActionTitle: "Patch",
                    secondaryActionTitle: "Unpatch",
                    primaryDisabled: isGameOperationInProgress || !isCrossOverPatchActionable || isCrossOverPatched,
                    secondaryDisabled: isGameOperationInProgress || !isCrossOverPatchActionable || !isCrossOverPatched,
                    primaryAction: onPatchCrossOver,
                    secondaryAction: onUnpatchCrossOver
                )
                PatchRow(
                    label: "Game Patch:",
                    status: gamePatchStatus,
                    primaryActionTitle: "Patch",
                    secondaryActionTitle: "Unpatch",
                    primaryDisabled: isGameOperationInProgress || !isGamePatchActionable || isGamePatched || !isCrossOverPatched,
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
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 150, alignment: .leading)

            StatusLabel(value: status)

            Spacer(minLength: 12)

            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
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
                BottomActionButton(title: "Addons", action: onAddons)

                if supportsMods {
                    BottomActionButton(title: "Mods", action: onMods)
                }
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

    var body: some View {
        Button(title, action: action)
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 6)
            .buttonStyle(.bordered)
            .controlSize(.large)
    }
}

private struct AddVersionSheet: View {
    let onAdd: (String, String, Bool) -> Void
    let onCancel: () -> Void

    private let baseOptions: [(id: String, label: String)] = [
        ("vanillasilicon", "VanillaSilicon (1.12.1)"),
        ("burningsilicon", "BurningSilicon (2.4.3)"),
        ("wrathsilicon", "WrathSilicon (3.3.5a)")
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
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Use third-party launcher", isOn: $useLauncher)
                if useLauncher {
                    Text("You can install the launcher after setting up CrossOver.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    let name = customName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    onAdd(name, selectedBaseID, useLauncher)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
        .animation(.default, value: useLauncher)
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
