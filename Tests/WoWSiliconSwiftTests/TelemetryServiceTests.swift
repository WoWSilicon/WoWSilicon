import Foundation
import XCTest
@testable import WoWSiliconSwift

@MainActor
final class TelemetryServiceTests: XCTestCase {
    func testOverlappingEventsShareConfigurationRequest() async throws {
        let stub = TelemetryHTTPStub(configStatusCode: 200, configDelayNanoseconds: 20_000_000)
        let service = makeService(stub: stub)
        service.setClientTelemetryEnabled(true)

        let launch = try XCTUnwrap(service.recordLaunch(prefs: enabledPrefs, context: context))
        let wowStart = try XCTUnwrap(service.recordWowStart(prefs: enabledPrefs, context: context))
        await launch.value
        await wowStart.value

        let counts = await stub.requestCounts()
        XCTAssertEqual(counts.config, 1)
        XCTAssertEqual(counts.event, 2)
    }

    func testDisablingTelemetryWhileConfigLoadsPreventsEvent() async throws {
        let stub = TelemetryHTTPStub(configStatusCode: 200, configDelayNanoseconds: 50_000_000)
        let service = makeService(stub: stub)
        service.setClientTelemetryEnabled(true)

        let launch = try XCTUnwrap(service.recordLaunch(prefs: enabledPrefs, context: context))
        await Task.yield()
        service.setClientTelemetryEnabled(false)
        await launch.value

        let counts = await stub.requestCounts()
        XCTAssertEqual(counts.event, 0)
    }

    func testRateLimitedConfigAppliesBackoffWithoutPosting() async throws {
        for statusCode in [429, 503] {
            let stub = TelemetryHTTPStub(configStatusCode: statusCode)
            let service = makeService(stub: stub)
            service.setClientTelemetryEnabled(true)

            let first = try XCTUnwrap(service.recordLaunch(prefs: enabledPrefs, context: context))
            await first.value
            let second = service.recordWowStart(prefs: enabledPrefs, context: context)

            XCTAssertNil(second)
            let counts = await stub.requestCounts()
            XCTAssertEqual(counts.config, 1)
            XCTAssertEqual(counts.event, 0)
        }
    }

    func testRateLimitedEventAppliesBackoffBeforeNextEvent() async throws {
        for statusCode in [429, 503] {
            let stub = TelemetryHTTPStub(configStatusCode: 200, eventStatusCode: statusCode)
            let service = makeService(stub: stub)
            service.setClientTelemetryEnabled(true)

            let first = try XCTUnwrap(service.recordLaunch(prefs: enabledPrefs, context: context))
            await first.value
            let second = service.recordWowStart(prefs: enabledPrefs, context: context)

            XCTAssertNil(second)
            let counts = await stub.requestCounts()
            XCTAssertEqual(counts.config, 1)
            XCTAssertEqual(counts.event, 1)
        }
    }

    func testHeartbeatUsesGameSessionIDAndIsRateLimited() async throws {
        let stub = TelemetryHTTPStub(configStatusCode: 200)
        let service = makeService(stub: stub, heartbeatInterval: 0)
        service.setClientTelemetryEnabled(true)

        let wowStart = try XCTUnwrap(service.recordWowStart(prefs: enabledPrefs, context: context))
        await wowStart.value
        let heartbeat = try XCTUnwrap(service.updateGameRunning(true))
        await heartbeat.value

        let events = await stub.events()
        XCTAssertEqual(events.map(\.event), ["wow_start", "heartbeat"])
        let wowStartEvent = try XCTUnwrap(events.first)
        let heartbeatEvent = try XCTUnwrap(events.last)
        XCTAssertEqual(wowStartEvent.sessionID, heartbeatEvent.sessionID)
        XCTAssertNotEqual(wowStartEvent.sessionID, enabledPrefs.telemetryInstallID)
    }

    func testHeartbeatIsNotSentBeforeInterval() async throws {
        let stub = TelemetryHTTPStub(configStatusCode: 200)
        let service = makeService(stub: stub, heartbeatInterval: 300)
        service.setClientTelemetryEnabled(true)

        let wowStart = try XCTUnwrap(service.recordWowStart(prefs: enabledPrefs, context: context))
        await wowStart.value

        XCTAssertNil(service.updateGameRunning(true))
        let counts = await stub.requestCounts()
        XCTAssertEqual(counts.event, 1)
    }

    func testGameSessionEndsOnlyAfterRunningProcessWasObserved() async throws {
        let stub = TelemetryHTTPStub(configStatusCode: 200)
        let service = makeService(stub: stub, heartbeatInterval: 0)
        service.setClientTelemetryEnabled(true)

        let wowStart = try XCTUnwrap(service.recordWowStart(prefs: enabledPrefs, context: context))
        await wowStart.value
        service.updateGameRunning(false)
        let firstHeartbeat = try XCTUnwrap(service.updateGameRunning(true))
        await firstHeartbeat.value

        let sessionEnd = try XCTUnwrap(service.updateGameRunning(false))
        await sessionEnd.value
        XCTAssertNil(service.updateGameRunning(true))
        let counts = await stub.requestCounts()
        XCTAssertEqual(counts.event, 3)
        let events = await stub.events()
        XCTAssertEqual(events.map(\.event), ["wow_start", "heartbeat", "session_end"])
    }

    private var enabledPrefs: UserPrefs {
        UserPrefs(
            telemetryEnabled: true,
            telemetryConsentAsked: true,
            telemetryInstallID: "test-install"
        )
    }

    private var context: TelemetryEventContext {
        TelemetryEventContext(version: nil)
    }

    private func makeService(
        stub: TelemetryHTTPStub,
        heartbeatInterval: TimeInterval = 5 * 60
    ) -> TelemetryService {
        TelemetryService(
            baseURL: URL(string: "https://telemetry.example")!,
            httpClient: { request in
                try await stub.respond(to: request)
            },
            randomSample: { 0 },
            heartbeatInterval: heartbeatInterval
        )
    }
}

private actor TelemetryHTTPStub {
    private let configStatusCode: Int
    private let eventStatusCode: Int
    private let configDelayNanoseconds: UInt64
    private var configRequestCount = 0
    private var eventRequestCount = 0
    private var recordedEvents: [RecordedTelemetryEvent] = []

    init(
        configStatusCode: Int,
        eventStatusCode: Int = 202,
        configDelayNanoseconds: UInt64 = 0
    ) {
        self.configStatusCode = configStatusCode
        self.eventStatusCode = eventStatusCode
        self.configDelayNanoseconds = configDelayNanoseconds
    }

    func respond(to request: URLRequest) async throws -> TelemetryHTTPResult {
        if request.url?.lastPathComponent == "config.json" {
            configRequestCount += 1
            if configDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: configDelayNanoseconds)
            }
            let data = Data(
                #"{"telemetry_enabled":true,"heartbeat_enabled":true,"heartbeat_interval_minutes":5,"launch_sample_rate":1,"heartbeat_sample_rate":1,"config_ttl_hours":24}"#.utf8
            )
            return TelemetryHTTPResult(
                data: data,
                statusCode: configStatusCode,
                retryAfter: "3600"
            )
        }

        eventRequestCount += 1
        if let data = request.httpBody,
           let event = try? JSONDecoder().decode(RecordedTelemetryEvent.self, from: data) {
            recordedEvents.append(event)
        }
        return TelemetryHTTPResult(
            data: Data(),
            statusCode: eventStatusCode,
            retryAfter: "3600"
        )
    }

    func requestCounts() -> (config: Int, event: Int) {
        (configRequestCount, eventRequestCount)
    }

    func events() -> [RecordedTelemetryEvent] {
        recordedEvents
    }
}

private struct RecordedTelemetryEvent: Decodable {
    let event: String
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case event
        case sessionID = "session_id"
    }
}
