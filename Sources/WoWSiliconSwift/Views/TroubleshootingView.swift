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
