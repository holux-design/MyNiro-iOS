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
