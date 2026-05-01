import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AddonManagerView: View {
    @ObservedObject var viewModel: AddonManagerViewModel
    let onClose: () -> Void

    @State private var installURL = ""
    @State private var showBulkInstallSheet = false
    @State private var bulkInstallText = ""

    var body: some View {
        VStack(spacing: 16) {
            header
            content
        }
        .padding()
        .frame(minWidth: 620, minHeight: 420)
        .onAppear { viewModel.refresh(checkUpdates: false) }
        .alert(item: $viewModel.alert) { alert in
            Alert(title: Text("Addons"), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $showBulkInstallSheet) {
            BulkInstallSheet(
                text: $bulkInstallText,
                isBusy: viewModel.isPerformingAction,
                progress: viewModel.multiInstallProgress,
                onInstall: {
                    viewModel.installMultiple(from: bulkInstallText)
                },
                onCancel: {
                    bulkInstallText = ""
                    showBulkInstallSheet = false
                },
                gitURLs: viewModel.addons.filter { $0.hasGitRepo }.compactMap { $0.gitRemoteURL }
            )
        }
        .onChange(of: viewModel.isPerformingAction) { _, isBusy in
            if !isBusy && showBulkInstallSheet {
                showBulkInstallSheet = false
                bulkInstallText = ""
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Addon Manager").font(.title2).bold()
                switch viewModel.status {
                case .ready:
                    Text("Found \(viewModel.addons.count) addons, \(viewModel.addons.filter { $0.hasGitRepo }.count) git repos")
                        .italic()
                case .loading(let message):
                    Text(message).italic()
                case .error(let message):
                    Text(message).foregroundColor(.red)
                case .idle:
                    EmptyView()
                }
            }
            Spacer()
            Toggle("Only git", isOn: $viewModel.showOnlyGit)
                .toggleStyle(.switch)
            Button("Update All") { viewModel.updateAll() }
                .disabled(viewModel.isPerformingAction || viewModel.filteredAddons.filter { $0.hasGitRepo && $0.needsUpdate }.isEmpty)
            Button("Refresh") { viewModel.refresh(checkUpdates: true) }
                .disabled(viewModel.isPerformingAction)
            Button("Close", action: onClose)
        }
    }

    private var content: some View {
        VStack(spacing: 16) {
            installRow
            Divider()
            list
        }
    }

    private var installRow: some View {
        HStack {
            TextField("https://github.com/user/addon", text: $installURL)
                .textFieldStyle(.roundedBorder)
            Button("Install") {
                viewModel.install(from: installURL)
                installURL = ""
            }
            .disabled(viewModel.isPerformingAction || installURL.isEmpty)
            Button("Multiple…") {
                bulkInstallText = ""
                showBulkInstallSheet = true
            }
            .disabled(viewModel.isPerformingAction)
        }
    }

    private var list: some View {
        Group {
            if case .loading = viewModel.status {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else if case .error(let message) = viewModel.status {
                Text(message)
                    .foregroundColor(.red)
                    .frame(maxHeight: .infinity)
            } else {
                List(viewModel.filteredAddons) { addon in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(addon.name).font(.headline)
                            if addon.hasGitRepo {
                                Text("Git").font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.18))
                                    .cornerRadius(4)
                            }
                            if addon.needsUpdate {
                                Text("Update available")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.18))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
                            } else if addon.hasGitRepo {
                                Text("Up to date")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.18))
                                    .foregroundColor(.green)
                                    .cornerRadius(4)
                            }
                        }
                        Text(addon.description).font(.caption).foregroundColor(.secondary)
                        HStack(spacing: 12) {
                            if let remote = addon.gitRemoteURL {
                                Text(remote).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if addon.hasGitRepo && addon.needsUpdate {
                                Button("Update") { viewModel.update(addon: addon) }
                                    .disabled(viewModel.isPerformingAction)
                            }
                            Button("Delete") { viewModel.delete(addon: addon) }
                                .disabled(viewModel.isPerformingAction)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

private struct BulkInstallSheet: View {
    @Binding var text: String
    let isBusy: Bool
    let progress: AddonManagerViewModel.InstallProgress?
    let onInstall: () -> Void
    let onCancel: () -> Void
    let gitURLs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Install Multiple Addons")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Import") { importFile() }
                Button("Export") { exportFile() }
            }

            Text("Paste one repository URL per line. Git repositories are supported.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
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

            if let progress = progress {
                ProgressView("Installing: \(progress.current) / \(progress.total)",
                             value: Double(progress.current),
                             total: Double(progress.total))
                    .padding(.vertical, 8)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Install") {
                    onInstall()
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export Addon URLs"
        panel.message = "Choose a location to save your addon URLs."
        panel.nameFieldStringValue = "addons.txt"
        
        if panel.runModal() == .OK, let url = panel.url {
            let content = gitURLs.joined(separator: "\n")
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK, let url = panel.url {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                text = content
                onInstall()
            }
        }
    }
}
