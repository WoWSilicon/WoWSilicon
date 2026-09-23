import Foundation
import XCTest
@testable import WoWSiliconSwift

@MainActor
final class WineMigrationViewModelTests: XCTestCase {
    func testCopiesLegacyBottleAndClearsBusyStateBeforeCompletion() async throws {
        let destination = URL(fileURLWithPath: "/tmp/WoWSilicon-test-bottle", isDirectory: true)
        let model = WineMigrationViewModel(operations: WineMigrationOperations(
            copyLegacyBottle: { destination },
            migrateExternalUserProfile: { _ in false }
        ))
        var completedWhileBusy = true
        var copiedURL: URL?

        let task = try XCTUnwrap(model.copyLegacyBottle { result in
            completedWhileBusy = model.isMigrationInProgress
            copiedURL = try? result.get()
        })
        XCTAssertTrue(model.isMigrationInProgress)
        await task.value

        XCTAssertFalse(completedWhileBusy)
        XCTAssertFalse(model.isMigrationInProgress)
        XCTAssertEqual(copiedURL, destination)
    }

    func testProfileMigrationRunsOnlyOnceUntilReset() async throws {
        let calls = LockedMigrationCounter()
        let model = WineMigrationViewModel(operations: WineMigrationOperations(
            copyLegacyBottle: { URL(fileURLWithPath: "/tmp/unused") },
            migrateExternalUserProfile: { _ in
                calls.increment()
                return false
            }
        ))
        let bottleURL = URL(fileURLWithPath: "/tmp/test-bottle", isDirectory: true)

        let first = try XCTUnwrap(model.startProfileMigration(
            bottleURL: bottleURL,
            blocked: false,
            completion: { _ in }
        ))
        await first.value
        XCTAssertNil(model.startProfileMigration(bottleURL: bottleURL, blocked: false, completion: { _ in }))

        model.resetProfileMigrationRequest()
        let second = try XCTUnwrap(model.startProfileMigration(
            bottleURL: bottleURL,
            blocked: false,
            completion: { _ in }
        ))
        await second.value
        XCTAssertEqual(calls.value, 2)
    }

    func testFailedProfileMigrationCanBeRetried() async throws {
        let attempts = LockedMigrationCounter()
        let model = WineMigrationViewModel(operations: WineMigrationOperations(
            copyLegacyBottle: { URL(fileURLWithPath: "/tmp/unused") },
            migrateExternalUserProfile: { _ in
                if attempts.increment() == 1 {
                    throw TestMigrationError.failed
                }
                return true
            }
        ))
        let bottleURL = URL(fileURLWithPath: "/tmp/test-bottle", isDirectory: true)
        var outcomes: [WineProfileMigrationOutcome] = []

        let first = try XCTUnwrap(model.startProfileMigration(
            bottleURL: bottleURL,
            blocked: false,
            completion: { outcomes.append($0) }
        ))
        await first.value
        XCTAssertTrue(model.canRetryProfileMigration)

        let retry = try XCTUnwrap(model.retryProfileMigration(
            bottleURL: bottleURL,
            blocked: false,
            completion: { outcomes.append($0) }
        ))
        await retry.value

        XCTAssertFalse(model.canRetryProfileMigration)
        XCTAssertEqual(attempts.value, 2)
        guard case .failed(let message) = outcomes.first else {
            return XCTFail("Expected the first migration to fail")
        }
        XCTAssertEqual(message, TestMigrationError.failed.localizedDescription)
        guard case .succeeded(let migrated) = outcomes.last else {
            return XCTFail("Expected the retry to succeed")
        }
        XCTAssertTrue(migrated)
    }
}

private final class LockedMigrationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private enum TestMigrationError: LocalizedError {
    case failed

    var errorDescription: String? { "test migration failed" }
}
