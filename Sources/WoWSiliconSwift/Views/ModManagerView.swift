import SwiftUI

struct ModManagerView: View {
    @ObservedObject var viewModel: ModManagerViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mod Manager").font(.title2).bold()
                    switch viewModel.status {
                    case .ready:
                        Text("Found \(viewModel.mods.count) mods, \(viewModel.mods.filter { $0.enabled }.count) enabled")
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
                Button("Refresh") { viewModel.refresh() }
                    .disabled(viewModel.isPerformingAction)
                Button("Close", action: onClose)
            }

            Divider()

            if case .loading = viewModel.status {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if case .error(let message) = viewModel.status {
                Text(message).foregroundColor(.red).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.mods) { mod in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(mod.name).font(.headline)
                            if mod.required { Text("Required").font(.caption2).padding(4).background(Color.orange.opacity(0.2)).cornerRadius(4) }
                            if mod.enabled && !mod.required {
                                Text("Enabled").font(.caption2).padding(4).background(Color.green.opacity(0.2)).cornerRadius(4)
                            }
                        }
                        Text(mod.description).font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Toggle("Enabled", isOn: Binding(
                                get: { mod.enabled },
                                set: { value in viewModel.toggle(mod: mod, enabled: value) }
                            ))
                            .toggleStyle(.switch)
                            .disabled(mod.required || viewModel.isPerformingAction)

                            Spacer()
                            Button("Delete") { viewModel.delete(mod: mod) }
                                .disabled(mod.required || viewModel.isPerformingAction)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
        .onAppear { viewModel.refresh() }
        .alert(item: $viewModel.alert) { alert in
            Alert(title: Text("Mods"), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }
}
