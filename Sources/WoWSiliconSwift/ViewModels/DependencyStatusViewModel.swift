import Foundation

struct DependencyOperations: Sendable {
    let hasWineRuntime: @Sendable () -> Bool
    let isVisualCppRuntimeInstalled: @Sendable () -> Bool
    let installVisualCppRuntime: @Sendable (String) throws -> Void
    let isWineMonoInstalled: @Sendable () -> Bool
    let installWineMono: @Sendable (String) throws -> Void
    let isGitInstalled: @Sendable () -> Bool
    let installGit: @Sendable () throws -> Void
    let isRosettaInstalled: @Sendable () -> Bool
    let installRosetta: @Sendable () throws -> Void

    static let live = DependencyOperations(
        hasWineRuntime: { BundledWineRuntime.wineExecutableURL() != nil },
        isVisualCppRuntimeInstalled: DependencyService.isVisualCppRuntimeInstalled,
        installVisualCppRuntime: DependencyService.installVisualCppRuntime,
        isWineMonoInstalled: DependencyService.isWineMonoInstalled,
        installWineMono: DependencyService.installWineMono,
        isGitInstalled: DependencyService.isGitInstalled,
        installGit: DependencyService.installGit,
        isRosettaInstalled: DependencyService.isRosettaInstalled,
        installRosetta: DependencyService.installRosetta
    )
}

@MainActor
final class DependencyStatusViewModel: ObservableObject {
    @Published private(set) var isVisualCppInstallInProgress = false
    @Published private(set) var visualCppRuntimeStatus: DependencyInstallStatus = .unknown
    @Published private(set) var isWineMonoInstallInProgress = false
    @Published private(set) var wineMonoStatus: DependencyInstallStatus = .unknown
    @Published private(set) var isGitInstallInProgress = false
    @Published private(set) var gitStatus: DependencyInstallStatus = .unknown
    @Published private(set) var isRosettaInstallInProgress = false
    @Published private(set) var rosettaStatus: DependencyInstallStatus = .unknown

    private let operations: DependencyOperations

    init(operations: DependencyOperations = .live) {
        self.operations = operations
    }

    var canInstallVisualCppRuntime: Bool {
        operations.hasWineRuntime() && !isVisualCppInstallInProgress
    }

    var canInstallWineMono: Bool {
        operations.hasWineRuntime() && !isWineMonoInstallInProgress
    }

    @discardableResult
    func installVisualCppRuntime(
        customVariables: String,
        feedback: @escaping @MainActor (PatchFeedback) -> Void
    ) -> Task<Void, Never>? {
        guard canInstallVisualCppRuntime else { return nil }
        isVisualCppInstallInProgress = true
        visualCppRuntimeStatus = .inProgress("Installing...")

        let operations = operations
        return Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<Bool, DependencyOperationError> in
                do {
                    try operations.installVisualCppRuntime(customVariables)
                    return .success(operations.isVisualCppRuntimeInstalled())
                } catch {
                    return .failure(DependencyOperationError(message: error.localizedDescription))
                }
            }.value

            guard let self else { return }
            self.isVisualCppInstallInProgress = false
            switch result {
            case .success(let installed):
                self.visualCppRuntimeStatus = installed ? .installed : .missing
                feedback(PatchFeedback(
                    title: "Dependencies",
                    message: "Microsoft Visual C++ Runtime 2022 installed successfully.",
                    isError: false
                ))
            case .failure(let error):
                self.visualCppRuntimeStatus = .error(error.message)
                feedback(PatchFeedback(title: "Dependencies Failed", message: error.message, isError: true))
                self.refreshVisualCppRuntimeStatus()
            }
        }
    }

    @discardableResult
    func refreshVisualCppRuntimeStatus() -> Task<Void, Never>? {
        guard !isVisualCppInstallInProgress else { return nil }
        let operation = operations.isVisualCppRuntimeInstalled
        return Task { [weak self] in
            let installed = await Task.detached(priority: .utility, operation: operation).value
            self?.visualCppRuntimeStatus = installed ? .installed : .missing
        }
    }

    @discardableResult
    func installWineMono(
        customVariables: String,
        feedback: @escaping @MainActor (PatchFeedback) -> Void
    ) -> Task<Void, Never>? {
        guard canInstallWineMono else { return nil }
        isWineMonoInstallInProgress = true
        wineMonoStatus = .inProgress("Waiting for installer...")

        let operation = operations.installWineMono
        return Task { [weak self] in
            let errorMessage = await Task.detached(priority: .userInitiated) { () -> String? in
                do {
                    try operation(customVariables)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value

            guard let self else { return }
            self.isWineMonoInstallInProgress = false
            if let errorMessage {
                self.wineMonoStatus = .error(errorMessage)
                feedback(PatchFeedback(title: "Wine Mono Install Failed", message: errorMessage, isError: true))
                self.refreshWineMonoStatus()
            } else {
                self.wineMonoStatus = .installed
                feedback(PatchFeedback(
                    title: "Dependencies",
                    message: "Wine Mono installed successfully.",
                    isError: false
                ))
            }
        }
    }

    @discardableResult
    func refreshWineMonoStatus() -> Task<Void, Never>? {
        guard !isWineMonoInstallInProgress else { return nil }
        let operation = operations.isWineMonoInstalled
        return Task { [weak self] in
            let installed = await Task.detached(priority: .utility, operation: operation).value
            self?.wineMonoStatus = installed ? .installed : .missing
        }
    }

    @discardableResult
    func installGit(
        feedback: @escaping @MainActor (PatchFeedback) -> Void
    ) -> Task<Void, Never>? {
        guard !isGitInstallInProgress else { return nil }
        isGitInstallInProgress = true
        gitStatus = .inProgress("Opening installer...")

        let operations = operations
        return Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<Bool, DependencyOperationError> in
                do {
                    try operations.installGit()
                    return .success(operations.isGitInstalled())
                } catch {
                    return .failure(DependencyOperationError(message: error.localizedDescription))
                }
            }.value

            guard let self else { return }
            self.isGitInstallInProgress = false
            switch result {
            case .success(let installed):
                self.gitStatus = installed ? .installed : .inProgress("Installer opened")
                feedback(PatchFeedback(
                    title: "Git",
                    message: "Apple's Git installer has been opened. Finish the installation, then refresh the status.",
                    isError: false
                ))
            case .failure(let error):
                self.gitStatus = .error(error.message)
                feedback(PatchFeedback(title: "Git Install Failed", message: error.message, isError: true))
                self.refreshGitStatus()
            }
        }
    }

    @discardableResult
    func refreshGitStatus() -> Task<Void, Never>? {
        guard !isGitInstallInProgress else { return nil }
        let operation = operations.isGitInstalled
        return Task { [weak self] in
            let installed = await Task.detached(priority: .utility, operation: operation).value
            self?.gitStatus = installed ? .installed : .missing
        }
    }

    @discardableResult
    func installRosetta(
        feedback: @escaping @MainActor (PatchFeedback) -> Void
    ) -> Task<Void, Never>? {
        guard !isRosettaInstallInProgress, rosettaStatus != .installed else { return nil }
        isRosettaInstallInProgress = true
        rosettaStatus = .inProgress("Opening installer...")

        let operation = operations.installRosetta
        return Task { [weak self] in
            let errorMessage = await Task.detached(priority: .userInitiated) { () -> String? in
                do {
                    try operation()
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value

            guard let self else { return }
            self.isRosettaInstallInProgress = false
            if let errorMessage {
                self.rosettaStatus = .error(errorMessage)
                feedback(PatchFeedback(title: "Rosetta 2 Install Failed", message: errorMessage, isError: true))
            } else {
                self.rosettaStatus = .inProgress("Installer opened")
                feedback(PatchFeedback(
                    title: "Rosetta 2",
                    message: "Finish the Rosetta 2 installation in Terminal, then refresh the status.",
                    isError: false
                ))
            }
        }
    }

    @discardableResult
    func refreshRosettaStatus(
        missing: @escaping @MainActor () -> Void = {}
    ) -> Task<Void, Never>? {
        guard !isRosettaInstallInProgress else { return nil }
        let operation = operations.isRosettaInstalled
        return Task { [weak self] in
            let installed = await Task.detached(priority: .utility, operation: operation).value
            self?.rosettaStatus = installed ? .installed : .missing
            if !installed {
                missing()
            }
        }
    }
}

private struct DependencyOperationError: Error, Sendable {
    let message: String
}
