import Foundation

struct TelemetryEventContext: Sendable {
    let appVersion: String
    let wowVersion: String?
    let renderer: String
    let macOSVersion: String
    let realmlist: String?

    init(version: GameVersion?) {
        appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? appVersionFallback
        wowVersion = version?.wowVersion
        renderer = "d9vk"
        macOSVersion = TelemetryEventContext.makeMacOSVersion()
        if let gamePath = version?.gamePath {
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

final class TelemetryService: @unchecked Sendable {
    static let shared = TelemetryService()

    private let baseURL = URL(string: "https://telemetry.wowsilicon.workers.dev")!
    private let session = URLSession(configuration: .ephemeral)
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let queue = DispatchQueue(label: "com.wowsilicon.telemetry", qos: .utility)
    private var cachedConfig: TelemetryConfig?
    private var configExpiresAt: Date?
    private var backoffUntil: Date?

    private init() {}

    func recordLaunch(prefs: UserPrefs, context: TelemetryEventContext) {
        record(event: "launch", prefs: prefs, context: context, sessionID: prefs.telemetryInstallID)
    }

    func recordWowStart(prefs: UserPrefs, context: TelemetryEventContext) {
        record(event: "wow_start", prefs: prefs, context: context, sessionID: UUID().uuidString)
    }

    private func record(event: String, prefs: UserPrefs, context: TelemetryEventContext, sessionID: String) {
        guard prefs.telemetryEnabled else { return }
        guard backoffUntil.map({ Date() < $0 }) != true else { return }

        queue.async { [weak self] in
            guard let self else { return }
            self.fetchConfigIfNeeded { [weak self] config in
                guard let self else { return }
                guard config.telemetryEnabled else { return }
                if event == "heartbeat", !config.heartbeatEnabled { return }

                let sampleRate = event == "heartbeat" ? config.heartbeatSampleRate : config.launchSampleRate
                guard Double.random(in: 0...1) <= sampleRate else { return }

                self.post(
                    TelemetryPayload(
                        event: event,
                        installID: prefs.telemetryInstallID,
                        sessionID: sessionID,
                        appVersion: context.appVersion,
                        wowVersion: context.wowVersion,
                        renderer: context.renderer,
                        macOSVersion: context.macOSVersion,
                        realmlist: context.realmlist
                    )
                )
            }
        }
    }

    private func fetchConfigIfNeeded(completion: @escaping @Sendable (TelemetryConfig) -> Void) {
        if let cachedConfig, let configExpiresAt, Date() < configExpiresAt {
            completion(cachedConfig)
            return
        }

        let url = baseURL.appendingPathComponent("config.json")
        session.dataTask(with: url) { [weak self] data, response, _ in
            guard let self else { return }

            if let response = response as? HTTPURLResponse,
               response.statusCode == 429 || response.statusCode == 503 {
                self.applyBackoff(from: response)
                completion(.fallback)
                return
            }

            guard let data,
                  let config = try? self.decoder.decode(TelemetryConfig.self, from: data) else {
                completion(self.cachedConfig ?? .fallback)
                return
            }

            self.cachedConfig = config
            self.configExpiresAt = Date().addingTimeInterval(TimeInterval(config.configTTLHours * 60 * 60))
            completion(config)
        }.resume()
    }

    private func post(_ payload: TelemetryPayload) {
        var request = URLRequest(url: baseURL.appendingPathComponent("event"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? encoder.encode(payload)

        session.dataTask(with: request) { [weak self] _, response, _ in
            guard let self, let response = response as? HTTPURLResponse else { return }
            if response.statusCode == 429 || response.statusCode == 503 {
                self.applyBackoff(from: response)
            }
        }.resume()
    }

    private func applyBackoff(from response: HTTPURLResponse) {
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
            .flatMap(TimeInterval.init) ?? 6 * 60 * 60
        backoffUntil = Date().addingTimeInterval(retryAfter)
    }
}

private let appVersionFallback = "unknown"

private struct TelemetryConfig: Decodable, Sendable {
    let telemetryEnabled: Bool
    let heartbeatEnabled: Bool
    let heartbeatIntervalMinutes: Int
    let launchSampleRate: Double
    let heartbeatSampleRate: Double
    let configTTLHours: Int

    static let fallback = TelemetryConfig(
        telemetryEnabled: true,
        heartbeatEnabled: false,
        heartbeatIntervalMinutes: 60,
        launchSampleRate: 1.0,
        heartbeatSampleRate: 0.0,
        configTTLHours: 24
    )

    enum CodingKeys: String, CodingKey {
        case telemetryEnabled = "telemetry_enabled"
        case heartbeatEnabled = "heartbeat_enabled"
        case heartbeatIntervalMinutes = "heartbeat_interval_minutes"
        case launchSampleRate = "launch_sample_rate"
        case heartbeatSampleRate = "heartbeat_sample_rate"
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
    let macOSVersion: String
    let realmlist: String?

    enum CodingKeys: String, CodingKey {
        case event
        case installID = "install_id"
        case sessionID = "session_id"
        case appVersion = "app_version"
        case wowVersion = "wow_version"
        case renderer
        case macOSVersion = "macos_version"
        case realmlist
    }
}
