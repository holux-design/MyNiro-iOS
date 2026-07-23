import Foundation

enum AppGroup {
    static let id = "group.com.holux-design.MyNiro"
    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}

struct CachedVehicleSnapshot: Codable, Equatable {
    var vehicleName: String
    var vin: String
    var socPercent: Double?
    var rangeKm: Double?
    var isCharging: Bool
    var isPluggedIn: Bool
    var chargeSpeedKW: Double?
    var targetSocAC: Double?
    var isLocked: Bool?
    var climateOn: Bool
    var climateTempC: Double?
    var updatedAt: Date
    var chargeTimeSeconds: Int64?
    /// Last known park / vehicle GPS from Kia. Absent when no fix.
    var latitude: Double?
    var longitude: Double?

    static let storageKey = "cachedVehicleSnapshot"

    static func load() -> CachedVehicleSnapshot? {
        guard let data = AppGroup.defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(CachedVehicleSnapshot.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            AppGroup.defaults.set(data, forKey: Self.storageKey)
        }
    }
}

struct WidgetActionFeedback: Codable, Equatable {
    var message: String
    /// `nil` = in progress, `true` = success, `false` = failure
    var isSuccess: Bool?
    var expiresAt: Date

    static let storageKey = "widgetActionFeedback"
    static let displayDuration: TimeInterval = 3

    static func load() -> WidgetActionFeedback? {
        guard let data = AppGroup.defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(WidgetActionFeedback.self, from: data)
    }

    static func active(at date: Date = .now) -> WidgetActionFeedback? {
        guard let value = load(), value.expiresAt > date else { return nil }
        return value
    }

    static func show(_ message: String, success: Bool? = true, duration: TimeInterval = displayDuration) {
        let feedback = WidgetActionFeedback(
            message: message,
            isSuccess: success,
            expiresAt: Date().addingTimeInterval(duration)
        )
        if let data = try? JSONEncoder().encode(feedback) {
            AppGroup.defaults.set(data, forKey: storageKey)
            AppGroup.defaults.synchronize()
        }
    }

    static func clear() {
        AppGroup.defaults.removeObject(forKey: storageKey)
    }
}

struct ClimateDefaults: Codable, Equatable {
    var temperatureC: Double = 22
    var steeringWheel: Int = 0 // 0 off, 1 low, 2 high-ish
    var frontLeftSeat: Int = 0
    var frontRightSeat: Int = 0
    var rearLeftSeat: Int = 0
    var rearRightSeat: Int = 0
    /// 0 = off mode for seat meaning; cool uses ventilation flag in ClimateOptions
    var frontLeftCool: Bool = false
    var frontRightCool: Bool = false
    var rearLeftCool: Bool = false
    var rearRightCool: Bool = false

    static let storageKey = "climateDefaults"

    static func load() -> ClimateDefaults {
        guard let data = AppGroup.defaults.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(ClimateDefaults.self, from: data)
        else { return ClimateDefaults() }
        return value
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            AppGroup.defaults.set(data, forKey: Self.storageKey)
        }
    }
}
