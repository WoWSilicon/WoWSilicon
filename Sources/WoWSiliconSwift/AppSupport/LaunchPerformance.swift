import os

final class LaunchPerformanceInterval {
    fileprivate let state: OSSignpostIntervalState

    fileprivate init(state: OSSignpostIntervalState) {
        self.state = state
    }
}

enum LaunchPerformance {
    private static let signposter = OSSignposter(
        subsystem: "com.wowsilicon.swift",
        category: "Launch Performance"
    )

    static func beginAppLaunch() -> LaunchPerformanceInterval {
        LaunchPerformanceInterval(
            state: signposter.beginInterval("App Launch")
        )
    }

    static func endAppLaunch(_ interval: LaunchPerformanceInterval) {
        signposter.endInterval("App Launch", interval.state)
    }

    static func beginPlayToWine(profile: String) -> LaunchPerformanceInterval {
        LaunchPerformanceInterval(
            state: signposter.beginInterval(
                "Play to Wine",
                "profile: \(profile, privacy: .public)"
            )
        )
    }

    static func endPlayToWine(_ interval: LaunchPerformanceInterval, outcome: String) {
        signposter.endInterval(
            "Play to Wine",
            interval.state,
            "outcome: \(outcome, privacy: .public)"
        )
    }

    static func measure<T>(
        _ name: StaticString,
        operation: () throws -> T
    ) rethrows -> T {
        try signposter.withIntervalSignpost(name, around: operation)
    }
}
