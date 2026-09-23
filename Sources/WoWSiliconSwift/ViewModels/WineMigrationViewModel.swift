import Foundation

struct WineMigrationOperations: Sendable {
    let copyLegacyBottle: @Sendable () throws -> URL
    let migrateExternalUserProfile: @Sendable (URL) throws -> Bool

    static let live = WineMigrationOperations(
        copyLegacyBottle: { try WineBottleService.copyLegacyBottle() },
        migrateExternalUserProfile: { bottleURL in
            try WineBottleService.migrateExternalUserProfileIfNeeded(bottleURL: bottleURL)
        }
    )
}

enum WineProfileMigrationOutcome: Sendable {
    case succeeded(migrated: Bool)
    case failed(message: String)
}

struct WineMigrationError: Error, Sendable {
    let message: String
}

@MainActor
final class WineMigrationViewModel: ObservableObject {
    @Published private(set) var isMigrationInProgress = false
    @Published private(set) var canRetryProfileMigration = false

    private let operations: WineMigrationOperations
    private var migrationTask: Task<Void, Never>?
    private var didRequestProfileMigration = false

    init(operations: WineMigrationOperations = .live) {
        self.operations = operations
    }

    @discardableResult
    func copyLegacyBottle(
        completion: @escaping @MainActor (Result<URL, WineMigrationError>) -> Void
    ) -> Task<Void, Never>? {
        guard migrationTask == nil, !isMigrationInProgress else { return nil }
        isMigrationInProgress = true

        let operation = operations.copyLegacyBottle
        let task = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { () -> Result<URL, WineMigrationError> in
                do {
                    return .success(try operation())
                } catch {
                    return .failure(WineMigrationError(message: error.localizedDescription))
                }
            }.value

            guard let self else { return }
            self.isMigrationInProgress = false
            self.migrationTask = nil
            completion(result)
        }
        migrationTask = task
        return task
    }

    @discardableResult
    func startProfileMigration(
        bottleURL: URL,
        blocked: Bool,
        completion: @escaping @MainActor (WineProfileMigrationOutcome) -> Void
    ) -> Task<Void, Never>? {
        guard !blocked,
              !didRequestProfileMigration,
              migrationTask == nil,
              !isMigrationInProgress else {
            return nil
        }

        didRequestProfileMigration = true
        canRetryProfileMigration = false
        isMigrationInProgress = true
        let operation = operations.migrateExternalUserProfile

        let task = Task { [weak self] in
            let migration = Task.detached(priority: .utility) {
                try operation(bottleURL)
            }

            let outcome: WineProfileMigrationOutcome?
            do {
                let migrated = try await withTaskCancellationHandler {
                    try await migration.value
                } onCancel: {
                    migration.cancel()
                }
                outcome = .succeeded(migrated: migrated)
            } catch is CancellationError {
                self?.didRequestProfileMigration = false
                outcome = nil
            } catch {
                self?.canRetryProfileMigration = true
                outcome = .failed(message: error.localizedDescription)
            }

            guard let self else { return }
            self.isMigrationInProgress = false
            self.migrationTask = nil
            if let outcome {
                completion(outcome)
            }
        }
        migrationTask = task
        return task
    }

    @discardableResult
    func retryProfileMigration(
        bottleURL: URL,
        blocked: Bool,
        completion: @escaping @MainActor (WineProfileMigrationOutcome) -> Void
    ) -> Task<Void, Never>? {
        guard canRetryProfileMigration, migrationTask == nil else { return nil }
        didRequestProfileMigration = false
        return startProfileMigration(bottleURL: bottleURL, blocked: blocked, completion: completion)
    }

    func resetProfileMigrationRequest() {
        guard migrationTask == nil else { return }
        didRequestProfileMigration = false
        canRetryProfileMigration = false
    }
}
