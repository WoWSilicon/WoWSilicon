import SwiftUI

struct TroubleshootingView: View {
    @ObservedObject var viewModel: TroubleshootingViewModel
    let onClose: () -> Void
    @State private var showingWineBottleDeletionConfirmation = false

    var body: some View {
        VStack(spacing: 16) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    wineRuntimeSection
                    permissionsSection
                    actionsSection
                    debugLogSection
                }
            }
        }
        .padding()
        .frame(minWidth: 620, minHeight: 500)
        .onAppear { viewModel.refresh() }
        .alert(item: $viewModel.alert) { alert in
            Alert(title: Text("Troubleshooting"), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .alert("Delete default Wine bottle?", isPresented: $showingWineBottleDeletionConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Bottle", role: .destructive, action: viewModel.deleteDefaultWineBottle)
        } message: {
            Text("This permanently deletes ~/.wine. Any Windows programs installed in this bottle will be deleted, including third-party launchers. This cannot be undone.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Troubleshooting").font(.title2).bold()
                switch viewModel.status {
                case .busy(let message):
                    Text(message).italic()
                default:
                    EmptyView()
                }
            }
            Spacer()
            Button("Close", action: onClose)
        }
    }

    private var wineRuntimeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bundled Wine").font(.headline)
            HStack {
                Text("Runtime: \(viewModel.wineRuntimeStatus)")
                Spacer()
            }
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Permissions & Access").font(.headline)
            Text("These checks verify effective file access. macOS does not let WoWSilicon read the Privacy & Security switches directly.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(viewModel.permissionChecks) { check in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: permissionIcon(for: check.state))
                        .foregroundStyle(permissionColor(for: check.state))
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(check.name)
                            Spacer()
                            Text(check.status)
                                .foregroundStyle(permissionColor(for: check.state))
                        }
                        if let detail = check.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            HStack {
                Button("Test Again", action: viewModel.refresh)
                    .buttonStyle(.bordered)
                Button("Re-select Game…", action: viewModel.reselectGamePath)
                    .buttonStyle(.bordered)
                Button("Open Privacy Settings", action: viewModel.openPrivacySettings)
                    .buttonStyle(.bordered)
            }
        }
    }

    private func permissionIcon(for state: PermissionAccessCheck.State) -> String {
        switch state {
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .unavailable: return "minus.circle.fill"
        }
    }

    private func permissionColor(for state: PermissionAccessCheck.State) -> Color {
        switch state {
        case .passed: return .green
        case .failed: return .red
        case .unavailable: return .secondary
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions").font(.headline)
            Button("Delete WDB Cache", action: viewModel.deleteWDB)
                .buttonStyle(.bordered)
            Button("Delete default Wine bottle", role: .destructive) {
                showingWineBottleDeletionConfirmation = true
            }
                .buttonStyle(.bordered)
            Button("Delete vanilla-tweaks", action: viewModel.deleteVanillaTweaks)
                .buttonStyle(.bordered)
            Button(role: .destructive, action: viewModel.resetApplicationSupport) {
                Text("Reset WoWSilicon (delete config)")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var debugLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Debug Log").font(.headline)
            
            HStack {
                Text("Copy this information for the dev in Discord.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy to Clipboard", action: viewModel.copyDebugLog)
                    .buttonStyle(.bordered)
            }
            
            HStack(spacing: 20) {
                Toggle("Hide Mac username", isOn: $viewModel.hideMacUserName)
                Toggle("Attach latest error log", isOn: $viewModel.includeLatestErrorLog)
            }
            .padding(.vertical, 4)

            TextEditor(text: Binding.constant(viewModel.debugLog))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 200)
                .disabled(true)
            Button("Copy to Clipboard", action: viewModel.copyDebugLog)
                .buttonStyle(.bordered)
        }
    }
}
