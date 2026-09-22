import Foundation

struct TelemetryEventContext: Sendable {
    let appVersion: String
    let wowVersion: String?
    let renderer: String
    let x87Translation: String
    let macOSVersion: String
    let realmlist: String?

    init(version: GameVersion?) {
        appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? appVersionFallback
        wowVersion = version?.isWorldOfWarcraft == true ? version?.wowVersion : nil
        renderer = version?.settings.graphicsSettings.backend.rawValue ?? GraphicsBackend.d9vk.rawValue
        x87Translation = version?.settings.x87Backend.rawValue ?? X87Backend.rosettaX87.rawValue
        macOSVersion = TelemetryEventContext.makeMacOSVersion()
        if version?.supportsRealmlist == true, let gamePath = version?.gamePath {
            realmlist = RealmlistService.currentRealmValue(gamePath: gamePath)
        } else {
            realmlist = nil
        }
    }

    private static func makeMacOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion)"
    }
}

struct TelemetryHTTPResult: Sendable {
    let data: Data
    let statusCode: Int
    let retryAfter: String?
}

typealias TelemetryHTTPClient = @Sendable (URLRequest) async throws -> TelemetryHTTPResult

@MainActor
final class TelemetryService {
    static let shared = TelemetryService()

    private let baseURL: URL
    private let httpClient: TelemetryHTTPClient
    private let cancelAllRequests: @Sendable () -> Void
    private let now: @Sendable () -> Date
    private let randomSample: @Sendable () -> Double
    private let heartbeatIntervalOverride: TimeInterval?
    private var clientTelemetryEnabled = false
    private var cachedConfig: TelemetryConfig?
    private var configExpiresAt: Date?
    private var backoffUntil: Date?
    private var stateGeneration = 0
    private var configRequest: (id: UUID, task: Task<TelemetryHTTPResult, Error>)?
    private var activeGameSession: ActiveGameSession?

    private convenience init() {
        let session = URLSession(configuration: .ephemeral)
        self.init(
            baseURL: URL(string: "https://telemetry.wowsilicon.workers.dev")!,
            httpClient: { request in
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                return TelemetryHTTPResult(
                    data: data,
                    statusCode: response.statusCode,
                    retryAfter: response.value(forHTTPHeaderField: "Retry-After")
                )
            },
            cancelAllRequests: {
                session.getAllTasks { tasks in
                    tasks.forEach { $0.cancel() }
                }
            }
        )
    }

    init(
        baseURL: URL,
        httpClient: @escaping TelemetryHTTPClient,
        cancelAllRequests: @escaping @Sendable () -> Void = {},
        now: @escaping @Sendable () -> Date = Date.init,
        randomSample: @escaping @Sendable () -> Double = { Double.random(in: 0...1) },
        heartbeatInterval: TimeInterval? = nil
    ) {
        self.baseURL = baseURL
        self.httpClient = httpClient
        self.cancelAllRequests = cancelAllRequests
        self.now = now
        self.randomSample = randomSample
        heartbeatIntervalOverride = heartbeatInterval
    }

    func setClientTelemetryEnabled(_ enabled: Bool) {
        clientTelemetryEnabled = enabled
        stateGeneration += 1

        if !enabled {
            activeGameSession = nil
            configRequest?.task.cancel()
            configRequest = nil
            cancelAllRequests()
        }
    }

    @discardableResult
    func recordLaunch(prefs: UserPrefs, context: TelemetryEventContext) -> Task<Void, Never>? {
        record(event: "launch", prefs: prefs, context: context, sessionID: prefs.telemetryInstallID)
    }

    @discardableResult
    func recordWowStart(prefs: UserPrefs, context: TelemetryEventContext) -> Task<Void, Never>? {
        let session = ActiveGameSession(
            id: UUID().uuidString,
            prefs: prefs,
            context: context,
            lastHeartbeatAt: now(),
            wasObservedRunning: false
        )
        guard let task = record(event: "wow_start", prefs: prefs, context: context, sessionID: session.id) else {
            return nil
        }
        activeGameSession = session
        return task
    }

    @discardableResult
    func updateGameRunning(_ isRunning: Bool) -> Task<Void, Never>? {
        guard var session = activeGameSession else { return nil }

        if !isRunning {
            if session.wasObservedRunning {
                activeGameSession = nil
                return record(
                    event: "session_end",
                    prefs: session.prefs,
                    context: session.context,
                    sessionID: session.id
                )
            }
            return nil
        }

        session.wasObservedRunning = true
        let configuredHeartbeatInterval = heartbeatIntervalOverride ?? cachedConfig.map {
            TimeInterval(max($0.heartbeatIntervalMinutes, 1) * 60)
        } ?? 5 * 60
        guard now().timeIntervalSince(session.lastHeartbeatAt) >= configuredHeartbeatInterval else {
            activeGameSession = session
            return nil
        }

        session.lastHeartbeatAt = now()
        activeGameSession = session
        return record(
            event: "heartbeat",
            prefs: session.prefs,
            context: session.context,
            sessionID: session.id
        )
    }

    private func record(
        event: String,
        prefs: UserPrefs,
        context: TelemetryEventContext,
        sessionID: String
    ) -> Task<Void, Never>? {
        guard prefs.telemetryEnabled else { return nil }
        guard clientTelemetryEnabled else { return nil }
        guard backoffUntil.map({ now() < $0 }) != true else { return nil }

        let generation = stateGeneration
        return Task { [weak self] in
            guard let self else { return }
            await self.send(
                event: event,
                prefs: prefs,
                context: context,
                sessionID: sessionID,
                generation: generation
            )
        }
    }

    private func send(
        event: String,
        prefs: UserPrefs,
        context: TelemetryEventContext,
        sessionID: String,
        generation: Int
    ) async {
        guard isEnabled(generation: generation) else { return }
        guard let config = await fetchConfigIfNeeded(generation: generation) else { return }
        guard isEnabled(generation: generation) else { return }
        guard config.telemetryEnabled else { return }
        if event == "heartbeat" || event == "session_end" {
            guard config.heartbeatEnabled else { return }
            guard randomSample() <= config.heartbeatSampleRate else { return }
        } else {
            guard randomSample() <= config.launchSampleRate else { return }
        }

        await post(
            TelemetryPayload(
                event: event,
                installID: prefs.telemetryInstallID,
                sessionID: sessionID,
                appVersion: context.appVersion,
                wowVersion: context.wowVersion,
                renderer: context.renderer,
                x87Translation: context.x87Translation,
                macOSVersion: context.macOSVersion,
                realmlist: context.realmlist
            ),
            generation: generation
        )
    }

    private func fetchConfigIfNeeded(generation: Int) async -> TelemetryConfig? {
        if let cachedConfig, let configExpiresAt, now() < configExpiresAt {
            return cachedConfig
        }

        let requestID: UUID
        let task: Task<TelemetryHTTPResult, Error>
        if let existing = configRequest {
            requestID = existing.id
            task = existing.task
        } else {
            requestID = UUID()
            let request = URLRequest(url: baseURL.appendingPathComponent("config.json"))
            task = Task { try await httpClient(request) }
            configRequest = (requestID, task)
        }

        let result: TelemetryHTTPResult
        do {
            result = try await task.value
        } catch {
            if configRequest?.id == requestID {
                configRequest = nil
            }
            guard isEnabled(generation: generation) else { return nil }
            return cachedConfig ?? .fallback
        }

        if configRequest?.id == requestID {
            configRequest = nil
        }
        guard isEnabled(generation: generation) else { return nil }

        if result.statusCode == 429 || result.statusCode == 503 {
            applyBackoff(retryAfter: result.retryAfter)
            return nil
        }

        guard let config = try? JSONDecoder().decode(TelemetryConfig.self, from: result.data) else {
            return cachedConfig ?? .fallback
        }

        cachedConfig = config
        configExpiresAt = now().addingTimeInterval(TimeInterval(config.configTTLHours * 60 * 60))
        return config
    }

    private func post(_ payload: TelemetryPayload, generation: Int) async {
        guard isEnabled(generation: generation) else { return }
        var request = URLRequest(url: baseURL.appendingPathComponent("event"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONEncoder().encode(payload)

        guard let result = try? await httpClient(request) else { return }
        guard isEnabled(generation: generation) else { return }
        if result.statusCode == 429 || result.statusCode == 503 {
            applyBackoff(retryAfter: result.retryAfter)
        }
    }

    private func applyBackoff(retryAfter: String?) {
        let interval = retryAfter.flatMap(TimeInterval.init) ?? 6 * 60 * 60
        backoffUntil = now().addingTimeInterval(interval)
    }

    private func isEnabled(generation: Int) -> Bool {
        clientTelemetryEnabled && stateGeneration == generation
    }
}

private let appVersionFallback = "unknown"

private struct ActiveGameSession {
    let id: String
    let prefs: UserPrefs
    let context: TelemetryEventContext
    var lastHeartbeatAt: Date
    var wasObservedRunning: Bool
}

private struct TelemetryConfig: Decodable, Sendable {
    let telemetryEnabled: Bool
    let heartbeatEnabled: Bool
    let heartbeatIntervalMinutes: Int
    let heartbeatSampleRate: Double
    let launchSampleRate: Double
    let configTTLHours: Int

    static let fallback = TelemetryConfig(
        telemetryEnabled: true,
        heartbeatEnabled: true,
        heartbeatIntervalMinutes: 5,
        heartbeatSampleRate: 1.0,
        launchSampleRate: 1.0,
        configTTLHours: 24
    )

    enum CodingKeys: String, CodingKey {
        case telemetryEnabled = "telemetry_enabled"
        case heartbeatEnabled = "heartbeat_enabled"
        case heartbeatIntervalMinutes = "heartbeat_interval_minutes"
        case heartbeatSampleRate = "heartbeat_sample_rate"
        case launchSampleRate = "launch_sample_rate"
        case configTTLHours = "config_ttl_hours"
    }
}

private struct TelemetryPayload: Encodable, Sendable {
    let event: String
    let installID: String
    let sessionID: String
    let appVersion: String
    let wowVersion: String?
    let renderer: String
    let x87Translation: String
    let macOSVersion: String
    let realmlist: String?

    enum CodingKeys: String, CodingKey {
        case event
        case installID = "install_id"
        case sessionID = "session_id"
        case appVersion = "app_version"
        case wowVersion = "wow_version"
        case renderer
        case x87Translation = "x87_translation"
        case macOSVersion = "macos_version"
        case realmlist
    }
}
