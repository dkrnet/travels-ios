// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public enum EventDetailDisplayRules {
    public static func normalizedDisplayText(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    public static func isMeaningfulDisplayText(_ value: String?) -> Bool {
        normalizedDisplayText(value) != nil
    }

    public static func hasMeaningfulAltitude(_ value: Double) -> Bool {
        value.isFinite && value > 0
    }

    public static func hasMeaningfulAccuracy(_ value: Double) -> Bool {
        value.isFinite && value >= 0
    }

    public static func hasMeaningfulCourse(_ value: Double) -> Bool {
        value.isFinite && value >= 0
    }

    public static func hasMeaningfulSpeed(_ value: Double) -> Bool {
        value.isFinite && value >= 0
    }

    public static func speedDisplayText(
        _ value: Double,
        measurementSystem: MeasurementSystemPreference = .default
    ) -> String {
        guard value.isFinite, value >= 0 else {
            // REGRESSION GUARD: unavailable speed should stay visible as an explicit "Not provided" value instead of disappearing from the detail view.
            return "Not provided"
        }

        let formatter = MeasurementFormatter()
        formatter.locale = .current
        formatter.unitStyle = .short
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.numberStyle = .decimal
        formatter.numberFormatter.minimumFractionDigits = 2
        formatter.numberFormatter.maximumFractionDigits = 2

        let measurement: Measurement<UnitSpeed>
        switch measurementSystem {
        case .metric:
            measurement = Measurement(value: value * 3.6, unit: .kilometersPerHour)
        case .imperial:
            measurement = Measurement(value: value * 2.236_936_292_054_4, unit: .milesPerHour)
        }
        return formatter.string(from: measurement)
    }

    public static func hasMeaningfulSolarPeriod(_ value: SolarPeriod) -> Bool {
        value != .unknown
    }

    public static func hasMeaningfulAreasOfInterest(_ values: [String]) -> Bool {
        values.contains { isMeaningfulDisplayText($0) }
    }

    public static func hasMeaningfulPlaceMetadata(_ geolocation: Geolocation) -> Bool {
        if isMeaningfulDisplayText(geolocation.identifier) { return true }
        if hasMeaningfulAccuracy(geolocation.horizontalAccuracy) { return true }
        if hasMeaningfulAccuracy(geolocation.verticalAccuracy) { return true }
        if hasMeaningfulAltitude(geolocation.altitude) { return true }
        if geolocation.timestamp != nil { return true }
        if geolocation.minLatitude != nil || geolocation.maxLatitude != nil { return true }
        if geolocation.minLongitude != nil || geolocation.maxLongitude != nil { return true }
        if isMeaningfulDisplayText(geolocation.timeZoneIdentifier) { return true }
        if isMeaningfulDisplayText(geolocation.name) { return true }
        if isMeaningfulDisplayText(geolocation.subThoroughfare) { return true }
        if isMeaningfulDisplayText(geolocation.thoroughfare) { return true }
        if isMeaningfulDisplayText(geolocation.subLocality) { return true }
        if isMeaningfulDisplayText(geolocation.locality) { return true }
        if isMeaningfulDisplayText(geolocation.subAdministrativeArea) { return true }
        if isMeaningfulDisplayText(geolocation.administrativeArea) { return true }
        if isMeaningfulDisplayText(geolocation.postalCode) { return true }
        if isMeaningfulDisplayText(geolocation.isoCountryCode) { return true }
        if isMeaningfulDisplayText(geolocation.country) { return true }
        if isMeaningfulDisplayText(geolocation.inlandWater) { return true }
        if isMeaningfulDisplayText(geolocation.ocean) { return true }
        return hasMeaningfulAreasOfInterest(geolocation.areasOfInterest)
    }
}
