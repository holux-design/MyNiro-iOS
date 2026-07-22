//
//  HyundaiEuropeAPIClient+Status.swift
//  BetterBlueKit
//
//  Cached vs force-refresh vehicle status for Hyundai Europe.
//  Same wake + poll pattern as Kia Europe (shared CCS2 backend shape).
//

import Foundation

extension HyundaiEuropeAPIClient {
    static let realTimeRefreshCooldown: TimeInterval = 60
    static let forceRefreshPollInterval: Duration = .seconds(3)
    static let forceRefreshMaxAttempts = 12

    func fetchLatestVehicleStatus(
        for vehicle: Vehicle,
        authToken: AuthToken
    ) async throws -> VehicleStatus {
        let ccs2 = vehicle.marketOptions?.ccs2Supported ?? false
        let endpoint = ccs2 ? "/ccs2/carstatus/latest" : "/status/latest"

        let (statusData, _, _) = try await performJSONRequest(
            url: "\(baseURL)/api/v1/spa/vehicles/\(vehicle.regId)\(endpoint)",
            method: .GET,
            headers: authorizedHeaders(authToken: authToken, ccs2: ccs2),
            requestType: .fetchVehicleStatus,
            vin: vehicle.vin
        )

        let (parkData, _, _) = try await performJSONRequest(
            url: "\(baseURL)/api/v1/spa/vehicles/\(vehicle.regId)/location/park",
            method: .GET,
            headers: authorizedHeaders(authToken: authToken, ccs2: ccs2),
            requestType: .fetchVehicleStatus,
            vin: vehicle.vin
        )

        return try parseVehicleStatusResponse(statusData, parkData, for: vehicle)
    }

    func forceRefreshVehicleStatus(
        for vehicle: Vehicle,
        authToken: AuthToken
    ) async throws -> VehicleStatus {
        let ccs2 = vehicle.marketOptions?.ccs2Supported ?? false
        let now = Date()
        if let last = lastRealTimeRefresh,
           now.timeIntervalSince(last) < Self.realTimeRefreshCooldown {
            BBLogger.debug(
                .api,
                "HyundaiEurope: skipping modem wake (last real-time refresh \(Int(now.timeIntervalSince(last)))s ago)"
            )
            return try await fetchLatestVehicleStatus(for: vehicle, authToken: authToken)
        }

        let baselineDate = (try? await fetchLatestVehicleStatus(for: vehicle, authToken: authToken))?.syncDate
            ?? .distantPast
        let wakePath = ccs2 ? "/ccs2/carstatus" : "/status"
        BBLogger.info(.api, "HyundaiEurope: Requesting real-time status refresh for VIN \(vehicle.vin)")

        do {
            _ = try await performJSONRequest(
                url: "\(baseURL)/api/v1/spa/vehicles/\(vehicle.regId)\(wakePath)",
                method: .GET,
                headers: authorizedHeaders(authToken: authToken, ccs2: ccs2),
                requestType: .fetchVehicleStatus,
                vin: vehicle.vin
            )
        } catch {
            BBLogger.warning(
                .api,
                "HyundaiEurope: modem wake failed, falling back to cached latest: \(error.localizedDescription)"
            )
            return try await fetchLatestVehicleStatus(for: vehicle, authToken: authToken)
        }

        var lastStatus: VehicleStatus?
        for attempt in 1 ... Self.forceRefreshMaxAttempts {
            try await Task.sleep(for: Self.forceRefreshPollInterval)
            do {
                let status = try await fetchLatestVehicleStatus(for: vehicle, authToken: authToken)
                lastStatus = status
                let syncDate = status.syncDate ?? .distantPast
                if syncDate > baselineDate {
                    lastRealTimeRefresh = Date()
                    BBLogger.info(
                        .api,
                        "HyundaiEurope: fresh status after \(attempt) poll(s); syncDate=\(syncDate)"
                    )
                    return status
                }
                BBLogger.debug(
                    .api,
                    "HyundaiEurope: status still stale after poll \(attempt)/\(Self.forceRefreshMaxAttempts)"
                )
            } catch {
                BBLogger.warning(
                    .api,
                    "HyundaiEurope: status poll \(attempt) failed: \(error.localizedDescription)"
                )
            }
        }

        BBLogger.warning(.api, "HyundaiEurope: force refresh timed out waiting for fresh status")
        if let lastStatus { return lastStatus }
        return try await fetchLatestVehicleStatus(for: vehicle, authToken: authToken)
    }
}
