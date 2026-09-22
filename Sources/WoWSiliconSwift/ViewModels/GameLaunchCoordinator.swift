import Foundation

enum GameLaunchPreflight {
    case ready(processCount: Int?)
    case existingWine(processCount: Int)
    case cancelled
}

enum GameLaunchOutcome {
    case started
    case versionMismatch(base: String, tweaked: String)
    case vanillaTweaksMissing
    case failed(LaunchServiceError)
    case cancelled
}

struct PendingGameLaunch {
    let version: GameVersion
    let shouldCleanUpWine: Bool
}

@MainActor
final class GameLaunchCoordinator {
    typealias ProcessCountProvider = @Sendable () -> Int?
    typealias GameLauncher = (GameVersion) async throws -> Void

    private let processCountProvider: ProcessCountProvider
    private let gameLauncher: GameLauncher
    private var pendingVersion: GameVersion?
    private var playToWineInterval: LaunchPerformanceInterval?

    init(
        processCountProvider: @escaping ProcessCountProvider = {
            WineProcessMonitor.currentApplicationProcessCount()
        },
        gameLauncher: @escaping GameLauncher = { version in
            try await LaunchService.shared.launch(version: version)
        }
    ) {
        self.processCountProvider = processCountProvider
        self.gameLauncher = gameLauncher
    }

    func prepareLaunch(
        version: GameVersion,
        isAudioBusy: @escaping @MainActor () -> Bool
    ) async -> GameLaunchPreflight {
        beginMeasurement(for: version)

        while isAudioBusy() {
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                finishMeasurement(outcome: "cancelled")
                return .cancelled
            }
        }

        let processCount = await Task.detached(priority: .userInitiated) { [processCountProvider] in
            LaunchPerformance.measure("Wine Process Check") {
                processCountProvider()
            }
        }.value

        guard !Task.isCancelled else {
            finishMeasurement(outcome: "cancelled")
            return .cancelled
        }

        if let processCount, processCount > 0 {
            pendingVersion = version
            finishMeasurement(outcome: "existing Wine prompt")
            return .existingWine(processCount: processCount)
        }

        return .ready(processCount: processCount)
    }

    func resolvePendingLaunch(cleanUp: Bool?) -> PendingGameLaunch? {
        guard let version = pendingVersion else { return nil }
        pendingVersion = nil
        guard let cleanUp else { return nil }

        beginMeasurement(for: version)
        return PendingGameLaunch(version: version, shouldCleanUpWine: cleanUp)
    }

    func launchPrepared(_ version: GameVersion) async -> GameLaunchOutcome {
        do {
            try Task.checkCancellation()
            try await gameLauncher(version)
            finishMeasurement(outcome: "Wine process started")
            return .started
        } catch is CancellationError {
            finishMeasurement(outcome: "cancelled")
            return .cancelled
        } catch let error as LaunchServiceError {
            switch error {
            case .versionMismatch(let base, let tweaked):
                finishMeasurement(outcome: "version mismatch prompt")
                return .versionMismatch(base: base, tweaked: tweaked)
            case .vanillaTweaksMissing:
                finishMeasurement(outcome: "failed")
                return .vanillaTweaksMissing
            default:
                finishMeasurement(outcome: "failed")
                return .failed(error)
            }
        } catch {
            finishMeasurement(outcome: "failed")
            return .failed(.processLaunchFailed(error.localizedDescription))
        }
    }

    private func beginMeasurement(for version: GameVersion) {
        finishMeasurement(outcome: "superseded")
        playToWineInterval = LaunchPerformance.beginPlayToWine(profile: version.id)
    }

    private func finishMeasurement(outcome: String) {
        guard let playToWineInterval else { return }
        LaunchPerformance.endPlayToWine(playToWineInterval, outcome: outcome)
        self.playToWineInterval = nil
    }
}
