import Foundation
import WatchConnectivity

/// Pushes login + vehicle snapshot from iPhone → Watch.
/// App Groups are per-device; WatchConnectivity is required for the Watch/complications to authenticate.
final class PhoneWatchSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneWatchSync()

    private static let loggedInKey = "loggedIn"
    private static let emailKey = "email"
    private static let passwordKey = "password"
    private static let pinKey = "pin"
    private static let accountIdKey = "accountId"
    private static let refreshTokenKey = "refreshToken"
    private static let snapshotKey = "snapshot"

    private override init() {
        super.init()
    }

    private static var isAppExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }

    func activate() {
        guard !Self.isAppExtension, WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    #if os(iOS)
    @MainActor
    func pushSession(
        email: String,
        password: String,
        pin: String,
        accountId: UUID,
        refreshToken: String?,
        snapshot: CachedVehicleSnapshot?
    ) {
        guard !Self.isAppExtension, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            activate()
            return
        }
        var context: [String: Any] = [
            Self.loggedInKey: true,
            Self.emailKey: email,
            Self.passwordKey: password,
            Self.pinKey: pin,
            Self.accountIdKey: accountId.uuidString
        ]
        if let refreshToken {
            context[Self.refreshTokenKey] = refreshToken
        }
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            context[Self.snapshotKey] = data
        }
        try? session.updateApplicationContext(context)
    }

    @MainActor
    func pushLoggedOut() {
        guard !Self.isAppExtension, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            activate()
            return
        }
        try? session.updateApplicationContext([Self.loggedInKey: false])
    }
    #endif

    #if os(watchOS)
    private func applyContext(_ context: [String: Any]) {
        Task { @MainActor in
            VehicleStore.shared.applyWatchConnectivityContext(context)
        }
    }
    #endif

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        #if os(iOS)
        guard activationState == .activated, error == nil else { return }
        Task { @MainActor in
            VehicleStore.shared.syncSessionToWatch()
        }
        #endif
        #if os(watchOS)
        if !session.receivedApplicationContext.isEmpty {
            applyContext(session.receivedApplicationContext)
        }
        #endif
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in
            VehicleStore.shared.syncSessionToWatch()
        }
    }
    #endif

    #if os(watchOS)
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyContext(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        applyContext(userInfo)
    }
    #endif
}
