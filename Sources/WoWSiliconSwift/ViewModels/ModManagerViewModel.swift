import Foundation

@MainActor
final class ModManagerViewModel: ObservableObject, Identifiable {
    let id = UUID()

    enum Status {
        case idle
        case loading(String)
        case ready
        case error(String)
    }

    @Published var mods: [ModInfo] = []
    @Published var status: Status = .idle
    @Published var alert: ManagerAlert?
    @Published var isPerformingAction = false

    private let version: GameVersion
    private let supportsDLL: Bool

    init(version: GameVersion, supportsDLL: Bool) {
        self.version = version
        self.supportsDLL = supportsDLL
    }

    func refresh() {
        status = .loading("Scanning mods…")
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let mods = try ModService.scanMods(version: self.version, supportsDLL: self.supportsDLL)
                Task { @MainActor in
                    self.mods = mods
                    self.status = .ready
                }
            } catch {
                Task { @MainActor in
                    self.mods = []
                    self.status = .error(error.localizedDescription)
                }
            }
        }
    }

    func toggle(mod: ModInfo, enabled: Bool) {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let updated = try ModService.setMod(mod, enabled: enabled, version: self.version)
                Task { @MainActor in
                    if let index = self.mods.firstIndex(of: mod) {
                        self.mods[index] = updated
                    }
                    self.isPerformingAction = false
                }
            } catch {
                Task { @MainActor in
                    self.isPerformingAction = false
                    self.alert = ManagerAlert(message: error.localizedDescription)
                }
            }
        }
    }

    func delete(mod: ModInfo) {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                try ModService.delete(mod: mod, version: self.version)
                Task { @MainActor in
                    self.mods.removeAll { $0 == mod }
                    self.isPerformingAction = false
                }
            } catch {
                Task { @MainActor in
                    self.isPerformingAction = false
                    self.alert = ManagerAlert(message: error.localizedDescription)
                }
            }
        }
    }
}
