//
//  KiaEuropeAPIClient+Status.swift
//  BetterBlueKit
//
//  Cached vs force-refresh vehicle status for Kia Europe.
//  `/ccs2/carstatus/latest` (and `/status/latest`) only return the cloud
//  snapshot — they do not wake the car. Pull-to-refresh / post-command
//  updates need GET `/ccs2/carstatus` (or `/status`) first, then poll
//  `/latest` until the CCU timestamp advances (same pattern as
//  hyundai_kia_connect_api PR #1184).
//

import Foundation

extension KiaEuropeAPIClient {
    /// Cooldown between successful modem wakes — back-to-back force refreshes
    /// get throttled by Kia and just burn 20–30s for a still-stale snapshot.
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

    /// Wakes the vehicle modem and polls `/latest` until the snapshot is newer
    /// than `triggerTime`. Returns the freshest status fetched (even on timeout).
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
                "KiaEurope: skipping modem wake (last real-time refresh \(Int(now.timeIntervalSince(last)))s ago)"
            )
            return try await fetchLatestVehicleStatus(for: vehicle, authToken: authToken)
        }

        let baselineDate = (try? await fetchLatestVehicleStatus(for: vehicle, authToken: authToken))?.syncDate
            ?? .distantPast
        let wakePath = ccs2 ? "/ccs2/carstatus" : "/status"
        BBLogger.info(.api, "KiaEurope: Requesting real-time status refresh for VIN \(vehicle.vin)")

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
                "KiaEurope: modem wake failed, falling back to cached latest: \(error.localizedDescription)"
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
                        "KiaEurope: fresh status after \(attempt) poll(s); syncDate=\(syncDate)"
                    )
                    return status
                }
                BBLogger.debug(
                    .api,
                    "KiaEurope: status still stale after poll \(attempt)/\(Self.forceRefreshMaxAttempts)"
                )
            } catch {
                BBLogger.warning(
                    .api,
                    "KiaEurope: status poll \(attempt) failed: \(error.localizedDescription)"
                )
            }
        }

        BBLogger.warning(.api, "KiaEurope: force refresh timed out waiting for fresh status")
        if let lastStatus { return lastStatus }
        return try await fetchLatestVehicleStatus(for: vehicle, authToken: authToken)
    }
}
