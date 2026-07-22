import BetterBlueKit
import Foundation
import WidgetKit

@Observable
@MainActor
final class VehicleStore {
    static let shared = VehicleStore()

    var isLoggedIn = false
    var isLoading = false
    var isCommandPending = false
    var pendingAction: PendingVehicleAction?
    var busyMessage: String?
    var errorMessage: String?
    var toastMessage: String?

    var isBusy: Bool { isLoading || isCommandPending }

    enum PendingVehicleAction: Equatable {
        case lock, climate, charge, limit
    }

    var email = ""
    var vehicle: Vehicle?
    var status: VehicleStatus?
    var lastUpdated: Date?
    var climateDefaults = ClimateDefaults.load()
    var snapshot: CachedVehicleSnapshot?

    private var authToken: AuthToken?
    private var client: (any APIClientProtocol)?
    private var accountId: UUID = UUID()
    private var password = ""
    private var pin = ""
    /// Assumed lock state after a lock/unlock command until status confirms or the command fails.
    private var optimisticLocked: Bool?
    /// Assumed charging state after start/stop until status confirms or the command fails.
    private var optimisticCharging: Bool?

    private init() {
        snapshot = CachedVehicleSnapshot.load()
        restoreSession()
    }

    var displayName: String {
        if let model = vehicle?.model, !model.isEmpty {
            if model.caseInsensitiveCompare("Niro") == .orderedSame {
                return "My Niro"
            }
            return String(format: String(localized: "My %@"), model)
        }
        if let name = snapshot?.vehicleName, name == "My Niro" {
            return "My Niro"
        }
        return snapshot?.vehicleName ?? String(localized: "My Niro")
    }

    var socPercent: Double {
        status?.evStatus?.evRange.percentage ?? snapshot?.socPercent ?? 0
    }

    var rangeKm: Double {
        guard let ev = status?.evStatus else { return snapshot?.rangeKm ?? 0 }
        return ev.evRange.range.units.convert(ev.evRange.range.length, to: .kilometers)
    }

    var isCharging: Bool {
        if let optimisticCharging { return optimisticCharging }
        return status?.evStatus?.charging ?? snapshot?.isCharging ?? false
    }

    /// Charging visuals and the stop slider — stays on stop UI while a stop command is in flight.
    var displayAsCharging: Bool {
        if pendingAction == .charge, optimisticCharging == false { return true }
        return isCharging
    }
    var isPluggedIn: Bool { status?.evStatus?.pluggedIn ?? snapshot?.isPluggedIn ?? false }
    var chargeSpeedKW: Double { status?.evStatus?.chargeSpeed ?? snapshot?.chargeSpeedKW ?? 0 }
    var targetSocAC: Int {
        Int(status?.evStatus?.targetSocAC ?? snapshot?.targetSocAC ?? 80)
    }
    var isLocked: Bool {
        if let optimisticLocked { return optimisticLocked }
        if let status {
            switch status.lockStatus {
            case .locked: return true
            case .unlocked: return false
            case .unknown: break
            }
        }
        return snapshot?.isLocked ?? false
    }
    var climateOn: Bool { status?.climateStatus.airControlOn ?? snapshot?.climateOn ?? false }

    var chargeTimeText: String? {
        guard let seconds = status?.evStatus?.chargeTime.components.seconds ?? snapshot?.chargeTimeSeconds,
              seconds > 0 else { return nil }
        return Self.formatDuration(seconds: seconds)
    }

    // MARK: - Auth

    func restoreSession() {
        let email = KeychainStore.get(.email) ?? AppGroup.defaults.string(forKey: "email")
        let password = KeychainStore.get(.password) ?? AppGroup.defaults.string(forKey: "password")
        let pin = KeychainStore.get(.pin)
            ?? AppGroup.defaults.string(forKey: "pin")
            ?? ""
        let accountIdString = KeychainStore.get(.accountId) ?? AppGroup.defaults.string(forKey: "accountId")

        guard let email, let password,
              let accountIdString,
              let accountId = UUID(uuidString: accountIdString)
        else { return }

        self.email = email
        self.password = password
        self.pin = pin
        self.accountId = accountId
        isLoggedIn = true
        syncSessionToWatch()

        Task { await loginAndRefresh(forceVehiclePoll: false) }
    }

    private func persistCredentials(
        email: String,
        password: String,
        pin: String,
        accountId: UUID,
        refreshToken: String
    ) {
        KeychainStore.set(email, for: .email)
        KeychainStore.set(password, for: .password)
        KeychainStore.set(pin, for: .pin)
        KeychainStore.set(accountId.uuidString, for: .accountId)
        KeychainStore.set(refreshToken, for: .refreshToken)
        // Mirror into App Group so same-device widgets can authenticate.
        AppGroup.defaults.set(email, forKey: "email")
        AppGroup.defaults.set(password, forKey: "password")
        AppGroup.defaults.set(pin, forKey: "pin")
        AppGroup.defaults.set(accountId.uuidString, forKey: "accountId")
        AppGroup.defaults.set(refreshToken, forKey: "refreshToken")
        syncSessionToWatch()
    }

    /// iPhone → Watch via WatchConnectivity (App Groups do not cross devices).
    func syncSessionToWatch() {
        #if os(iOS)
        guard isLoggedIn else {
            PhoneWatchSync.shared.pushLoggedOut()
            return
        }
        PhoneWatchSync.shared.pushSession(
            email: email,
            password: password,
            pin: pin,
            accountId: accountId,
            refreshToken: KeychainStore.get(.refreshToken) ?? AppGroup.defaults.string(forKey: "refreshToken"),
            snapshot: snapshot
        )
        #endif
    }

    /// Watch receives credentials pushed from the iPhone companion.
    func applyWatchConnectivityContext(_ context: [String: Any]) {
        #if os(watchOS)
        if let loggedIn = context["loggedIn"] as? Bool, loggedIn == false {
            logout()
            return
        }
        guard
            let email = context["email"] as? String,
            let password = context["password"] as? String,
            let accountIdString = context["accountId"] as? String,
            let accountId = UUID(uuidString: accountIdString)
        else { return }

        let pin = context["pin"] as? String ?? ""
        let refreshToken = context["refreshToken"] as? String ?? ""

        self.email = email
        self.password = password
        self.pin = pin
        self.accountId = accountId
        KeychainStore.set(email, for: .email)
        KeychainStore.set(password, for: .password)
        KeychainStore.set(pin, for: .pin)
        KeychainStore.set(accountIdString, for: .accountId)
        if !refreshToken.isEmpty {
            KeychainStore.set(refreshToken, for: .refreshToken)
            AppGroup.defaults.set(refreshToken, forKey: "refreshToken")
        }
        AppGroup.defaults.set(email, forKey: "email")
        AppGroup.defaults.set(password, forKey: "password")
        AppGroup.defaults.set(pin, forKey: "pin")
        AppGroup.defaults.set(accountIdString, forKey: "accountId")

        if let data = context["snapshot"] as? Data,
           let snap = try? JSONDecoder().decode(CachedVehicleSnapshot.self, from: data) {
            snap.save()
            snapshot = snap
        }

        isLoggedIn = true
        Task { await loginAndRefresh(forceVehiclePoll: false) }
        #endif
    }

    func login(email: String, password: String, pin: String) async {
        errorMessage = nil
        isLoading = true
        busyMessage = String(localized: "Signing in…")
        defer {
            isLoading = false
            busyMessage = nil
        }

        let accountId = UUID()
        self.email = email
        self.password = password
        self.pin = pin
        self.accountId = accountId

        do {
            try await configureClient()
            let token = try await client!.login()
            authToken = token
            persistCredentials(
                email: email,
                password: password,
                pin: pin,
                accountId: accountId,
                refreshToken: token.refreshToken
            )
            isLoggedIn = true
            busyMessage = String(localized: "Syncing with car…")
            try await refreshVehiclesAndStatus(cached: false)
            showToast(String(localized: "Connected"))
        } catch {
            isLoggedIn = false
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        KeychainStore.deleteAll()
        for key in ["email", "password", "pin", "accountId", "refreshToken", CachedVehicleSnapshot.storageKey] {
            AppGroup.defaults.removeObject(forKey: key)
        }
        isLoggedIn = false
        vehicle = nil
        status = nil
        authToken = nil
        client = nil
        email = ""
        password = ""
        pin = ""
        snapshot = nil
        optimisticLocked = nil
        optimisticCharging = nil
        #if os(iOS)
        PhoneWatchSync.shared.pushLoggedOut()
        #endif
        reloadWidgets()
    }

    // MARK: - Refresh

    func refresh(force: Bool = true) async {
        guard isLoggedIn else { return }
        // Kia rejects overlapping status/command calls with HTTP 400 — same as the
        // official app's "some request is still running" case.
        if isCommandPending {
            showToast(String(localized: "Still talking to the car — please wait"))
            return
        }
        isLoading = true
        busyMessage = String(localized: "Syncing with car…")
        defer {
            isLoading = false
            busyMessage = nil
        }
        errorMessage = nil
        do {
            try await ensureAuthenticated()
            try await refreshVehiclesAndStatus(cached: !force)
            reconcileLockOptimisticAfterRefresh()
            reconcileChargeOptimisticAfterRefresh()
        } catch {
            guard !Self.isCancellation(error) else { return }
            if Self.isRequestInProgress(error) {
                showToast(String(localized: "Another request is still running — please wait"))
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Commands

    @discardableResult
    func unlock() async -> Bool {
        await send(.unlock, toast: String(localized: "Unlock sent"), action: .lock)
    }

    @discardableResult
    func lock() async -> Bool {
        await send(.lock, toast: String(localized: "Lock sent"), action: .lock)
    }

    @discardableResult
    func toggleLock() async -> Bool {
        let currentlyLocked = isLocked
        optimisticLocked = !currentlyLocked
        if currentlyLocked {
            return await unlock()
        } else {
            return await lock()
        }
    }

    @discardableResult
    func startClimate(temperatureC: Double? = nil) async -> Bool {
        var options = climateDefaults.asClimateOptions()
        if let temperatureC {
            options.temperature = Temperature(value: temperatureC, units: .celsius)
        }
        return await send(.startClimate(options), toast: String(localized: "Climate start sent"), action: .climate)
    }

    @discardableResult
    func stopClimate() async -> Bool {
        await send(.stopClimate, toast: String(localized: "Climate stop sent"), action: .climate)
    }

    @discardableResult
    func toggleClimate(temperatureC: Double? = nil) async -> Bool {
        if climateOn {
            return await stopClimate()
        } else {
            return await startClimate(temperatureC: temperatureC)
        }
    }

    @discardableResult
    func startCharge() async -> Bool {
        await send(.startCharge, toast: String(localized: "Charging start sent"), action: .charge, optimisticCharge: true)
    }

    @discardableResult
    func stopCharge() async -> Bool {
        await send(.stopCharge, toast: String(localized: "Charging stop sent"), action: .charge, optimisticCharge: false)
    }

    @discardableResult
    func toggleCharge() async -> Bool {
        if isCharging {
            return await stopCharge()
        } else {
            return await startCharge()
        }
    }

    @discardableResult
    func setACChargeLimit(_ acPercent: Int) async -> Bool {
        let dc = Int(status?.evStatus?.targetSocDC ?? Double(acPercent))
        return await send(
            .setTargetSOC(acLevel: acPercent, dcLevel: dc),
            toast: String(format: String(localized: "AC limit %lld%%"), acPercent),
            action: .limit
        )
    }

    func saveClimateDefaults(_ defaults: ClimateDefaults) {
        climateDefaults = defaults
        defaults.save()
    }

    /// Optional service PIN used only for remote commands (lock/climate/charge).
    /// Login and status work without it. Official EU app often never shows this.
    func updatePin(_ newPin: String) {
        pin = newPin
        KeychainStore.set(newPin, for: .pin)
        AppGroup.defaults.set(newPin, forKey: "pin")
        client = nil // force recreate with new pin on next command
    }

    var hasPinConfigured: Bool { !pin.isEmpty }

    // MARK: - Private

    /// Widget/Shortcuts start with a cold store — credentials exist, but `vehicle` is nil until login.
    private func ensureReadyForCommand() async -> Bool {
        if !isLoggedIn {
            restoreSession()
        }
        guard isLoggedIn else {
            errorMessage = String(localized: "Sign in to MyNiro first")
            return false
        }
        if vehicle == nil || client == nil || authToken == nil || !(authToken?.isValid ?? false) {
            await loginAndRefresh(forceVehiclePoll: true)
        }
        guard vehicle != nil else {
            if errorMessage == nil || errorMessage?.isEmpty == true {
                errorMessage = String(localized: "No vehicle")
            }
            return false
        }
        return true
    }

    @discardableResult
    private func send(
        _ command: VehicleCommand,
        toast: String,
        action: PendingVehicleAction,
        optimisticCharge: Bool? = nil
    ) async -> Bool {
        errorMessage = nil
        guard await ensureReadyForCommand() else {
            if action == .lock { clearLockOptimistic() }
            return false
        }
        guard let vehicle else {
            errorMessage = String(localized: "No vehicle")
            if action == .lock { clearLockOptimistic() }
            return false
        }
        pendingAction = action
        isCommandPending = true
        if let optimisticCharge {
            optimisticCharging = optimisticCharge
        }
        busyMessage = String(localized: "Sending to car…")
        defer {
            isCommandPending = false
            pendingAction = nil
            busyMessage = nil
        }

        do {
            try await ensureAuthenticated()
            try await client!.sendCommand(for: vehicle, command: command, authToken: authToken!)
            busyMessage = String(localized: "Waiting for car…")
            try? await Task.sleep(for: .seconds(2))
            do {
                try await refreshVehiclesAndStatus(cached: false)
                if action == .lock {
                    reconcileLockOptimisticAfterRefresh()
                }
                if action == .charge {
                    reconcileChargeOptimisticAfterRefresh()
                }
            } catch {
                // Command already accepted; a busy/cancel on the follow-up poll isn't a failure.
                guard Self.isCancellation(error) || Self.isRequestInProgress(error) else { throw error }
            }
            showToast(toast)
            return true
        } catch {
            if action == .lock { clearLockOptimistic() }
            if action == .charge { clearChargeOptimistic() }
            guard !Self.isCancellation(error) else { return false }
            if Self.isRequestInProgress(error) {
                showToast(String(localized: "Another request is still running — please wait"))
                return false
            }
            let message = error.localizedDescription
            if message.localizedCaseInsensitiveContains("pin") {
                errorMessage = String(format: String(localized: "%@ — add a Service PIN in Settings if your account has one."), message)
            } else {
                errorMessage = message
            }
            return false
        }
    }

    private func clearLockOptimistic() {
        optimisticLocked = nil
    }

    private func clearChargeOptimistic() {
        optimisticCharging = nil
    }

    /// Drop the assumed lock state once the car reports the same value; keep it if status still lags.
    private func reconcileLockOptimisticAfterRefresh() {
        guard let assumed = optimisticLocked else { return }
        let serverLocked: Bool = {
            if let status {
                switch status.lockStatus {
                case .locked: return true
                case .unlocked: return false
                case .unknown: break
                }
            }
            return snapshot?.isLocked ?? assumed
        }()
        if serverLocked == assumed {
            optimisticLocked = nil
        }
    }

    /// Drop the assumed charging state once the car reports the same value; keep it if status still lags.
    private func reconcileChargeOptimisticAfterRefresh() {
        guard let assumed = optimisticCharging else { return }
        let serverCharging = status?.evStatus?.charging ?? snapshot?.isCharging ?? assumed
        if serverCharging == assumed {
            optimisticCharging = nil
        }
    }

    private func loginAndRefresh(forceVehiclePoll: Bool) async {
        isLoading = true
        busyMessage = String(localized: "Connecting…")
        defer {
            isLoading = false
            busyMessage = nil
        }
        do {
            try await configureClient()
            let token = try await client!.login()
            authToken = token
            persistCredentials(
                email: email,
                password: password,
                pin: pin,
                accountId: accountId,
                refreshToken: token.refreshToken
            )
            busyMessage = String(localized: "Syncing with car…")
            try await refreshVehiclesAndStatus(cached: !forceVehiclePoll)
        } catch {
            guard !Self.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func ensureAuthenticated() async throws {
        if client == nil {
            try await configureClient()
        }
        if let token = authToken, token.isValid {
            return
        }
        let token = try await client!.login()
        authToken = token
        persistCredentials(
            email: email,
            password: password,
            pin: pin,
            accountId: accountId,
            refreshToken: token.refreshToken
        )
    }

    private func configureClient() async throws {
        let refresh = KeychainStore.get(.refreshToken) ?? AppGroup.defaults.string(forKey: "refreshToken")
        let config = APIClientConfiguration(
            region: .europe,
            brand: .kia,
            username: email,
            password: password,
            refreshToken: refresh,
            pin: pin,
            accountId: accountId
        )
        client = try createBetterBlueKitAPIClient(configuration: config)
    }

    private func refreshVehiclesAndStatus(cached: Bool) async throws {
        guard let client, let token = authToken else { return }
        let vehicles = try await client.fetchVehicles(authToken: token)
        guard let first = vehicles.first else {
            throw APIError(message: String(localized: "No vehicles on this account"), apiName: "MyNiro")
        }
        vehicle = first
        status = try await client.fetchVehicleStatus(for: first, authToken: token, cached: cached)
        lastUpdated = Date()
        persistSnapshot()
        reloadWidgets()
    }

    private func persistSnapshot() {
        guard let vehicle, let status else { return }
        let snap = CachedVehicleSnapshot(
            vehicleName: displayName,
            vin: vehicle.vin,
            socPercent: status.evStatus?.evRange.percentage,
            rangeKm: status.evStatus.map {
                $0.evRange.range.units.convert($0.evRange.range.length, to: .kilometers)
            },
            isCharging: status.evStatus?.charging ?? false,
            isPluggedIn: status.evStatus?.pluggedIn ?? false,
            chargeSpeedKW: status.evStatus?.chargeSpeed,
            targetSocAC: status.evStatus?.targetSocAC,
            isLocked: status.lockStatus == .locked,
            climateOn: status.climateStatus.airControlOn,
            climateTempC: {
                let t = status.climateStatus.temperature
                return t.units.convert(t.value, to: .celsius)
            }(),
            updatedAt: Date(),
            chargeTimeSeconds: status.evStatus?.chargeTime.components.seconds
        )
        snapshot = snap
        snap.save()
        syncSessionToWatch()
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toastMessage == message { toastMessage = nil }
        }
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func formatDuration(seconds: Int64) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return String(format: String(localized: "%1$lldh %2$lldmin"), hours, minutes)
        }
        return String(format: String(localized: "%lldmin"), minutes)
    }

    static func formatKm(_ km: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let n = formatter.string(from: NSNumber(value: km.rounded())) ?? "0"
        return String(format: String(localized: "%@ km"), n)
    }

    static func formatUpdated(_ date: Date?) -> String {
        guard let date else { return String(localized: "Not updated") }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return String(format: String(localized: "Updated %@"), formatter.string(from: date))
    }

    static func formatAsOf(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return String(format: String(localized: "as of %@"), formatter.string(from: date))
    }

    /// SwiftUI `.refreshable` cancels its task (often when the view updates);
    /// that surfaces as `URLError.cancelled` / "Network error: cancelled".
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError || Task.isCancelled { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return true }
        let message = error.localizedDescription.lowercased()
        return message.contains("cancelled") || message.contains("canceled")
    }

    /// Kia Europe often answers overlapping vehicle calls with HTTP 400; BetterBlueKit
    /// also models this as `APIError.concurrentRequest`.
    static func isRequestInProgress(_ error: Error) -> Bool {
        if let apiError = error as? APIError {
            if apiError.errorType == .concurrentRequest { return true }
            if apiError.code == 400 { return true }
        }
        let message = error.localizedDescription.lowercased()
        return message.contains("http 400")
            || message.contains("already in progress")
            || message.contains("still running")
    }
}

extension ClimateDefaults {
    func asClimateOptions() -> ClimateOptions {
        var options = ClimateOptions(preferredUnits: .celsius)
        options.temperature = Temperature(value: temperatureC, units: .celsius)
        options.climate = true
        options.duration = 10
        options.steeringWheel = steeringWheel
        options.frontLeftSeat = frontLeftCool ? 0 : frontLeftSeat
        options.frontRightSeat = frontRightCool ? 0 : frontRightSeat
        options.rearLeftSeat = rearLeftCool ? 0 : rearLeftSeat
        options.rearRightSeat = rearRightCool ? 0 : rearRightSeat
        options.frontLeftVentilation = frontLeftCool
        options.frontRightVentilation = frontRightCool
        options.rearLeftVentilation = rearLeftCool
        options.rearRightVentilation = rearRightCool
        if frontLeftCool { options.frontLeftSeat = max(frontLeftSeat, 1) }
        if frontRightCool { options.frontRightSeat = max(frontRightSeat, 1) }
        if rearLeftCool { options.rearLeftSeat = max(rearLeftSeat, 1) }
        if rearRightCool { options.rearRightSeat = max(rearRightSeat, 1) }
        return options
    }

    var summaryText: String {
        let temp = String(format: "%g°", temperatureC)
        let steering = steeringWheel == 0
            ? String(localized: "steering off")
            : String(localized: "steering on")
        let seatsOn = [frontLeftSeat > 0 || frontLeftCool,
                       frontRightSeat > 0 || frontRightCool,
                       rearLeftSeat > 0 || rearLeftCool,
                       rearRightSeat > 0 || rearRightCool]
            .filter(\.self).count
        let seats = seatsOn == 1
            ? String(format: String(localized: "%lld seat on"), seatsOn)
            : String(format: String(localized: "%lld seats on"), seatsOn)
        return "\(temp) · \(steering) · \(seats)"
    }
}
