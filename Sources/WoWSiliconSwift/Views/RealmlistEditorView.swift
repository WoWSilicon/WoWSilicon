import SwiftUI

struct RealmlistEditorView: View {
    let url: URL

    @AppStorage("realmlistEditorMode") private var mode: EditorMode = .servers
    @State private var savedContent: String
    @State private var rawContent: String
    @State private var editorDraft: ServerDraft?
    @State private var serverPendingRemoval: RealmlistServer?
    @State private var errorMessage: String?

    init(url: URL, content: String) {
        self.url = url
        _savedContent = State(initialValue: content)
        _rawContent = State(initialValue: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Realm Servers")
                        .font(.headline)
                    Text("Choose the server this client connects to.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Editor", selection: $mode) {
                    ForEach(EditorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            Label(url.path, systemImage: "doc.text")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            switch mode {
            case .servers:
                serverList
            case .raw:
                rawEditor
            }
        }
        .sheet(item: $editorDraft) { draft in
            ServerEditorSheet(draft: draft) { name, address in
                let updated: String
                switch draft.action {
                case .add:
                    updated = RealmlistService.addingServer(name: name, address: address, to: savedContent)
                case .edit(let id):
                    updated = RealmlistService.updatingServer(
                        id: id,
                        name: name,
                        address: address,
                        in: savedContent
                    )
                }
                persist(updated)
            }
        }
        .alert(item: $serverPendingRemoval) { server in
            Alert(
                title: Text("Remove \(server.displayName)?"),
                message: Text("This removes the server from realmlist.wtf."),
                primaryButton: .destructive(Text("Remove")) {
                    persist(RealmlistService.removingServer(id: server.id, from: savedContent))
                },
                secondaryButton: .cancel()
            )
        }
        .alert(
            "Could not update realmlist.wtf",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var servers: [RealmlistServer] {
        RealmlistService.servers(in: savedContent)
    }

    @ViewBuilder
    private var serverList: some View {
        if servers.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.secondary)
                Text("No realm servers configured")
                    .font(.headline)
                Text("Add a server address to start switching realms from WoWSilicon.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    editorDraft = .adding
                } label: {
                    Label("Add Server", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 42)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.16))
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(servers) { server in
                        serverRow(server)
                        if server.id != servers.last?.id {
                            Divider()
                                .padding(.leading, 46)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.16))
                )

                Button {
                    editorDraft = .adding
                } label: {
                    Label("Add Server", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func serverRow(_ server: RealmlistServer) -> some View {
        HStack(spacing: 8) {
            Button {
                guard !server.isActive else { return }
                persist(RealmlistService.activatingServer(id: server.id, in: savedContent))
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: server.isActive ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(server.isActive ? Color.accentColor : Color.secondary.opacity(0.55))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.displayName)
                            .fontWeight(server.isActive ? .semibold : .regular)
                            .foregroundStyle(.primary)
                        if server.displayName != server.address {
                            Text(server.address)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Button {
                    editorDraft = .editing(server)
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .help("Edit server")
                .accessibilityLabel("Edit \(server.displayName)")

                Button(role: .destructive) {
                    serverPendingRemoval = server
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .help("Remove server")
                .accessibilityLabel("Remove \(server.displayName)")
            }
            .frame(width: 60, alignment: .trailing)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: 58)
    }

    private var rawEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $rawContent)
                .font(.body.monospaced())
                .padding(10)
                .frame(minHeight: 180)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2))
                )

            HStack {
                Text(rawContent == savedContent ? "No unsaved changes" : "Unsaved changes")
                    .font(.caption)
                    .foregroundStyle(rawContent == savedContent ? Color.secondary : Color.orange)

                Spacer()

                Button("Revert") {
                    rawContent = savedContent
                }
                .buttonStyle(.bordered)
                .disabled(rawContent == savedContent)

                Button("Save Changes") {
                    persist(rawContent)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(rawContent == savedContent)
            }
        }
    }

    private func persist(_ content: String) {
        do {
            try RealmlistService.write(content: content, to: url)
            savedContent = content
            rawContent = content
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private enum EditorMode: String, CaseIterable, Identifiable {
        case servers
        case raw

        var id: Self { self }
        var title: String {
            switch self {
            case .servers: return "Servers"
            case .raw: return "Raw File"
            }
        }
    }
}

private struct ServerDraft: Identifiable {
    enum Action {
        case add
        case edit(Int)
    }

    let id = UUID()
    let action: Action
    let title: String
    let name: String
    let address: String

    static let adding = ServerDraft(
        action: .add,
        title: "Add Server",
        name: "",
        address: ""
    )

    static func editing(_ server: RealmlistServer) -> ServerDraft {
        ServerDraft(
            action: .edit(server.id),
            title: "Edit Server",
            name: server.name ?? "",
            address: server.address
        )
    }
}

private struct ServerEditorSheet: View {
    let draft: ServerDraft
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var address: String

    init(draft: ServerDraft, onSave: @escaping (String, String) -> Void) {
        self.draft = draft
        self.onSave = onSave
        _name = State(initialValue: draft.name)
        _address = State(initialValue: draft.address)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(draft.title)
                .font(.title2)
                .fontWeight(.semibold)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Name")
                    TextField("Optional, for example My Realm", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                }
                GridRow {
                    Text("Address")
                    TextField("For example logon.example.com", text: $address)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave(name, address)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}
