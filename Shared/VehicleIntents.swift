import AppIntents
import WidgetKit

@MainActor
private enum WidgetIntentFeedback {
    static let widgetKind = "BatteryStatusWidget"

    /// Paint success immediately, then run the car command without blocking the intent return.
    /// WidgetKit defers timeline reloads until `perform()` finishes — awaiting the API (~5s) is why
    /// the status used to appear late.
    static func run(
        successMessage: String,
        failureFallback: String,
        command: @MainActor @escaping () async -> Bool
    ) async -> IntentDialog {
        WidgetActionFeedback.show(successMessage, success: true, duration: 60)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)

        // Keep running after `perform()` returns — do not await the car API here.
        DispatchQueue.global(qos: .userInitiated).async {
            ProcessInfo.processInfo.performExpiringActivity(withReason: "MyNiro vehicle command") { expired in
                guard !expired else { return }
                let done = DispatchSemaphore(value: 0)
                Task { @MainActor in
                    defer { done.signal() }
                    let ok = await command()
                    if ok {
                        WidgetActionFeedback.show(successMessage, success: true)
                    } else {
                        let failure = VehicleStore.shared.errorMessage ?? failureFallback
                        WidgetActionFeedback.show(failure, success: false)
                    }
                    WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
                }
                done.wait()
            }
        }

        return IntentDialog(stringLiteral: successMessage)
    }

    static func showFailure(_ message: String) {
        WidgetActionFeedback.show(message, success: false)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}

struct UnlockVehicleIntent: AppIntent {
    static var title: LocalizedStringResource = "Unlock Vehicle"
    static var description = IntentDescription("Unlock your Kia")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = VehicleStore.shared
        if !store.isLoggedIn {
            store.restoreSession()
        }
        guard store.isLoggedIn else {
            return .result(dialog: IntentDialog(LocalizedStringResource("Sign in on iPhone first, then open MyNiro once")))
        }
        let ok = await store.unlock()
        WidgetCenter.shared.reloadAllTimelines()
        if ok {
            return .result(dialog: IntentDialog(LocalizedStringResource("Unlock sent")))
        }
        return .result(dialog: IntentDialog(stringLiteral: store.errorMessage ?? String(localized: "Unlock failed")))
    }
}

struct LockVehicleIntent: AppIntent {
    static var title: LocalizedStringResource = "Lock Vehicle"
    static var description = IntentDescription("Lock your Kia")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = VehicleStore.shared
        let ok = await store.lock()
        WidgetCenter.shared.reloadAllTimelines()
        if ok {
            return .result(dialog: IntentDialog(LocalizedStringResource("Lock sent")))
        }
        return .result(dialog: IntentDialog(stringLiteral: store.errorMessage ?? String(localized: "Lock failed")))
    }
}

struct StartClimateIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Climate"
    static var description = IntentDescription("Start climate with your defaults")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = VehicleStore.shared
        let ok = await store.startClimate()
        WidgetCenter.shared.reloadAllTimelines()
        if ok {
            return .result(dialog: IntentDialog(LocalizedStringResource("Climate start sent")))
        }
        return .result(dialog: IntentDialog(stringLiteral: store.errorMessage ?? String(localized: "Climate start failed")))
    }
}

struct PreHeatClimateIntent: AppIntent {
    static var title: LocalizedStringResource = "Pre-heat"
    static var description = IntentDescription("Toggle climate at 22°C")
    static var openAppWhenRun = false

    private static let temperatureC: Double = 22

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = VehicleStore.shared
        let stopping = store.climateOn
        let ok = await store.toggleClimate(temperatureC: Self.temperatureC)
        WidgetCenter.shared.reloadAllTimelines()
        if ok {
            let message = stopping
                ? LocalizedStringResource("Climate stop sent")
                : LocalizedStringResource("Pre-heat sent")
            return .result(dialog: IntentDialog(message))
        }
        return .result(dialog: IntentDialog(stringLiteral: store.errorMessage ?? String(localized: "Climate command failed")))
    }
}

struct PreCoolClimateIntent: AppIntent {
    static var title: LocalizedStringResource = "Pre-cool"
    static var description = IntentDescription("Toggle climate at 17°C")
    static var openAppWhenRun = false

    private static let temperatureC: Double = 17

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = VehicleStore.shared
        let stopping = store.climateOn
        let ok = await store.toggleClimate(temperatureC: Self.temperatureC)
        WidgetCenter.shared.reloadAllTimelines()
        if ok {
            let message = stopping
                ? LocalizedStringResource("Climate stop sent")
                : LocalizedStringResource("Pre-cool sent")
            return .result(dialog: IntentDialog(message))
        }
        return .result(dialog: IntentDialog(stringLiteral: store.errorMessage ?? String(localized: "Climate command failed")))
    }
}

struct StopClimateIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Climate"
    static var description = IntentDescription("Stop climate control")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = VehicleStore.shared
        let ok = await store.stopClimate()
        WidgetCenter.shared.reloadAllTimelines()
        if ok {
            return .result(dialog: IntentDialog(LocalizedStringResource("Climate stop sent")))
        }
        return .result(dialog: IntentDialog(stringLiteral: store.errorMessage ?? String(localized: "Climate stop failed")))
    }
}

struct ToggleLockIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Lock"
    static var description = IntentDescription("Lock or unlock your Kia")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let unlocking = CachedVehicleSnapshot.load()?.isLocked ?? true
        let successMessage = unlocking
            ? String(localized: "Unlock sent")
            : String(localized: "Lock sent")
        let dialog = await WidgetIntentFeedback.run(
            successMessage: successMessage,
            failureFallback: String(localized: "Lock command failed")
        ) {
            await VehicleStore.shared.toggleLock()
        }
        return .result(dialog: dialog)
    }
}

struct ToggleClimateIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Climate"
    static var description = IntentDescription("Start or stop climate control")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let stopping = CachedVehicleSnapshot.load()?.climateOn ?? false
        let successMessage = stopping
            ? String(localized: "Climate stop sent")
            : String(localized: "Climate start sent")
        let dialog = await WidgetIntentFeedback.run(
            successMessage: successMessage,
            failureFallback: String(localized: "Climate command failed")
        ) {
            await VehicleStore.shared.toggleClimate()
        }
        return .result(dialog: dialog)
    }
}

struct ToggleChargeIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Charge"
    static var description = IntentDescription("Start or stop charging")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snap = CachedVehicleSnapshot.load()
        let plugged = snap?.isPluggedIn ?? false
        let charging = snap?.isCharging ?? false
        guard plugged || charging else {
            let message = String(localized: "Plug in to charge")
            WidgetIntentFeedback.showFailure(message)
            return .result(dialog: IntentDialog(LocalizedStringResource("Plug in to charge")))
        }
        let successMessage = charging
            ? String(localized: "Charging stop sent")
            : String(localized: "Charging start sent")
        let dialog = await WidgetIntentFeedback.run(
            successMessage: successMessage,
            failureFallback: String(localized: "Charge command failed")
        ) {
            await VehicleStore.shared.toggleCharge()
        }
        return .result(dialog: dialog)
    }
}

#if os(iOS)
struct MyNiroShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: UnlockVehicleIntent(),
            phrases: [
                "Unlock my car with \(.applicationName)",
                "Unlock the car with \(.applicationName)",
                "Open my car with \(.applicationName)",
                "Unlock \(.applicationName)",
            ],
            shortTitle: "Unlock",
            systemImageName: "lock.open.fill"
        )
        AppShortcut(
            intent: ToggleLockIntent(),
            phrases: [
                "Lock my car with \(.applicationName)",
                "Lock the car with \(.applicationName)",
                "Toggle lock with \(.applicationName)",
            ],
            shortTitle: "Lock",
            systemImageName: "lock.fill"
        )
        AppShortcut(
            intent: StartClimateIntent(),
            phrases: [
                "Start climate with \(.applicationName)",
            ],
            shortTitle: "Start Climate",
            systemImageName: "snowflake"
        )
        AppShortcut(
            intent: PreHeatClimateIntent(),
            phrases: [
                "Preheat my car with \(.applicationName)",
                "Pre-heat my car with \(.applicationName)",
                "Warm my car with \(.applicationName)",
                "Pre-heat with \(.applicationName)",
            ],
            shortTitle: "Pre-heat",
            systemImageName: "thermometer.sun.fill"
        )
        AppShortcut(
            intent: PreCoolClimateIntent(),
            phrases: [
                "Pre-cool my car with \(.applicationName)",
                "Precool my car with \(.applicationName)",
                "Cool my car with \(.applicationName)",
                "Pre-cool with \(.applicationName)",
            ],
            shortTitle: "Pre-cool",
            systemImageName: "thermometer.snowflake"
        )
        AppShortcut(
            intent: ToggleClimateIntent(),
            phrases: [
                "Toggle climate with \(.applicationName)",
                "Stop climate with \(.applicationName)",
                "Climate with \(.applicationName)",
            ],
            shortTitle: "Climate",
            systemImageName: "snowflake"
        )
        AppShortcut(
            intent: ToggleChargeIntent(),
            phrases: [
                "Start charging with \(.applicationName)",
                "Toggle charge with \(.applicationName)",
                "Charge with \(.applicationName)",
            ],
            shortTitle: "Charge",
            systemImageName: "bolt.fill"
        )
    }
}
#endif
