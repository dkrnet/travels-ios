// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public enum TwilightPhase: String, Codable, CaseIterable, Sendable {
    case none
    case morningCivilTwilight = "morning_civil_twilight"
    case eveningCivilTwilight = "evening_civil_twilight"
}

public enum SolarPeriod: String, Codable, CaseIterable, Sendable {
    case unknown
    case morningCivilTwilight = "morning_civil_twilight"
    case day
    case eveningCivilTwilight = "evening_civil_twilight"
    case nightBeforeMidnight = "night_before_midnight"
    case nightAfterMidnight = "night_after_midnight"

    init(twilightPhase: TwilightPhase) {
        switch twilightPhase {
        case .none:
            self = .unknown
        case .morningCivilTwilight:
            self = .morningCivilTwilight
        case .eveningCivilTwilight:
            self = .eveningCivilTwilight
        }
    }

    var twilightPhase: TwilightPhase {
        switch self {
        case .morningCivilTwilight:
            return .morningCivilTwilight
        case .eveningCivilTwilight:
            return .eveningCivilTwilight
        case .unknown, .day, .nightBeforeMidnight, .nightAfterMidnight:
            return .none
        }
    }

    var displayName: String {
        switch self {
        case .morningCivilTwilight:
            return "Morning Twilight"
        case .day:
            return "Day"
        case .eveningCivilTwilight:
            return "Evening Twilight"
        case .nightBeforeMidnight, .nightAfterMidnight:
            return "Night"
        case .unknown:
            return "Unknown"
        }
    }
}

public struct TwilightResult: Equatable, Sendable {
    public var phase: TwilightPhase
    public var percent: Double?

    public init(phase: TwilightPhase, percent: Double?) {
        self.phase = phase
        self.percent = percent
    }
}

public struct SolarPeriodResult: Equatable, Sendable {
    public var period: SolarPeriod
    public var percent: Double?

    public init(period: SolarPeriod, percent: Double?) {
        self.period = period
        self.percent = percent
    }
}

struct SolarEventTimes: Equatable, Sendable {
    var civilDawn: Date?
    var sunrise: Date?
    var sunset: Date?
    var civilDusk: Date?
}

enum SolarTwilight {
    private static let sunriseSunsetZenith = 90.833
    private static let civilTwilightZenith = 96.0

    private struct SolarCalculationContext {
        let utcMidnight: Date
        let dayOfYear: Double
    }

    static func twilightResult(
        at eventDate: Date,
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone
    ) -> TwilightResult {
        guard coordinatesAreValid(latitude: latitude, longitude: longitude) else {
            return TwilightResult(phase: .none, percent: nil)
        }
        guard let events = calculateSolarEvents(
            for: eventDate,
            latitude: latitude,
            longitude: longitude,
            timeZone: timeZone
        ) else {
            return TwilightResult(phase: .none, percent: nil)
        }
        return twilightResult(at: eventDate, solarEvents: events)
    }

    static func solarPeriodResult(
        at eventDate: Date,
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone
    ) -> SolarPeriodResult {
        guard coordinatesAreValid(latitude: latitude, longitude: longitude) else {
            return SolarPeriodResult(period: .unknown, percent: nil)
        }

        let calendar = calendarForTimeZone(timeZone)
        let localMidnight = calendar.startOfDay(for: eventDate)
        guard let nextLocalMidnight = calendar.date(byAdding: .day, value: 1, to: localMidnight),
              let solarEvents = calculateSolarEvents(
                for: eventDate,
                latitude: latitude,
                longitude: longitude,
                timeZone: timeZone
              ),
              let solarMidday = solarNoon(
                for: eventDate,
                latitude: latitude,
                longitude: longitude,
                timeZone: timeZone
              )
        else {
            return SolarPeriodResult(period: .unknown, percent: nil)
        }

        let previousCivilDuskDate = previousCivilDusk(
            for: eventDate,
            latitude: latitude,
            longitude: longitude,
            timeZone: timeZone
        )

        if let civilDawn = solarEvents.civilDawn,
           let sunrise = solarEvents.sunrise,
           sunrise > civilDawn,
           eventDate >= civilDawn,
           eventDate < sunrise {
            let percent = clamp(eventDate.timeIntervalSince(civilDawn) / sunrise.timeIntervalSince(civilDawn))
            return SolarPeriodResult(period: .morningCivilTwilight, percent: percent)
        }

        if let sunrise = solarEvents.sunrise,
           let sunset = solarEvents.sunset,
           sunrise <= solarMidday,
           solarMidday <= sunset,
           eventDate >= sunrise,
           eventDate <= sunset {
            let percent: Double
            if eventDate <= solarMidday {
                guard solarMidday > sunrise else {
                    return SolarPeriodResult(period: .unknown, percent: nil)
                }
                percent = 0.5 * eventDate.timeIntervalSince(sunrise) / solarMidday.timeIntervalSince(sunrise)
            } else {
                guard sunset > solarMidday else {
                    return SolarPeriodResult(period: .unknown, percent: nil)
                }
                percent = 0.5 + 0.5 * eventDate.timeIntervalSince(solarMidday) / sunset.timeIntervalSince(solarMidday)
            }
            return SolarPeriodResult(period: .day, percent: clamp(percent))
        }

        if let sunset = solarEvents.sunset,
           let civilDusk = solarEvents.civilDusk,
           civilDusk > sunset,
           eventDate > sunset,
           eventDate <= civilDusk {
            let percent = clamp(eventDate.timeIntervalSince(sunset) / civilDusk.timeIntervalSince(sunset))
            return SolarPeriodResult(period: .eveningCivilTwilight, percent: percent)
        }

        if let civilDusk = solarEvents.civilDusk,
           civilDusk < nextLocalMidnight,
           eventDate > civilDusk,
           eventDate < nextLocalMidnight {
            let percent = clamp(eventDate.timeIntervalSince(civilDusk) / nextLocalMidnight.timeIntervalSince(civilDusk))
            return SolarPeriodResult(period: .nightBeforeMidnight, percent: percent)
        }

        if let civilDawn = solarEvents.civilDawn,
           civilDawn > localMidnight,
           eventDate >= localMidnight,
           eventDate < civilDawn {
            let percent = clamp(eventDate.timeIntervalSince(localMidnight) / civilDawn.timeIntervalSince(localMidnight))
            return SolarPeriodResult(period: .nightAfterMidnight, percent: percent)
        }

        _ = previousCivilDuskDate
        return SolarPeriodResult(period: .unknown, percent: nil)
    }

    static func twilightResult(at eventDate: Date, solarEvents: SolarEventTimes?) -> TwilightResult {
        guard let solarEvents else {
            return TwilightResult(phase: .none, percent: nil)
        }

        if let civilDawn = solarEvents.civilDawn,
           let sunrise = solarEvents.sunrise,
           sunrise > civilDawn,
           eventDate >= civilDawn,
           eventDate < sunrise {
            let percent = clamp(eventDate.timeIntervalSince(civilDawn) / sunrise.timeIntervalSince(civilDawn))
            return TwilightResult(phase: .morningCivilTwilight, percent: percent)
        }

        if let sunset = solarEvents.sunset,
           let civilDusk = solarEvents.civilDusk,
           civilDusk > sunset,
           eventDate > sunset,
           eventDate <= civilDusk {
            let percent = clamp(eventDate.timeIntervalSince(sunset) / civilDusk.timeIntervalSince(sunset))
            return TwilightResult(phase: .eveningCivilTwilight, percent: percent)
        }

        return TwilightResult(phase: .none, percent: nil)
    }

    static func calculateSolarEvents(
        for eventDate: Date,
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone
    ) -> SolarEventTimes? {
        guard let context = solarCalculationContext(
            for: eventDate,
            latitude: latitude,
            longitude: longitude,
            timeZone: timeZone
        ) else {
            return nil
        }

        return SolarEventTimes(
            civilDawn: solarEventDate(
                latitude: latitude,
                longitude: longitude,
                zenith: civilTwilightZenith,
                rising: true,
                context: context
            ),
            sunrise: solarEventDate(
                latitude: latitude,
                longitude: longitude,
                zenith: sunriseSunsetZenith,
                rising: true,
                context: context
            ),
            sunset: solarEventDate(
                latitude: latitude,
                longitude: longitude,
                zenith: sunriseSunsetZenith,
                rising: false,
                context: context
            ),
            civilDusk: solarEventDate(
                latitude: latitude,
                longitude: longitude,
                zenith: civilTwilightZenith,
                rising: false,
                context: context
            )
        )
    }

    static func solarNoon(
        for eventDate: Date,
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone
    ) -> Date? {
        guard let context = solarCalculationContext(
            for: eventDate,
            latitude: latitude,
            longitude: longitude,
            timeZone: timeZone
        ) else {
            return nil
        }

        let solarNoonUTCMinutes = solarNoonUTCMinutes(for: longitude, dayOfYear: context.dayOfYear)
        return context.utcMidnight.addingTimeInterval(solarNoonUTCMinutes * 60.0)
    }

    private static func previousCivilDusk(
        for eventDate: Date,
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone
    ) -> Date? {
        let calendar = calendarForTimeZone(timeZone)
        guard let previousDate = calendar.date(byAdding: .day, value: -1, to: eventDate) else {
            return nil
        }
        return calculateSolarEvents(
            for: previousDate,
            latitude: latitude,
            longitude: longitude,
            timeZone: timeZone
        )?.civilDusk
    }

    private static func solarEventDate(
        latitude: Double,
        longitude: Double,
        zenith: Double,
        rising: Bool,
        context: SolarCalculationContext
    ) -> Date? {
        let gamma = fractionalYearAngle(for: context.dayOfYear)
        let eqTime = equationOfTime(for: gamma)
        let decl = solarDeclination(for: gamma)

        let latRad = degreesToRadians(latitude)
        let zenithRad = degreesToRadians(zenith)
        let cosHourAngle = (
            cos(zenithRad) / (cos(latRad) * cos(decl))
        ) - (tan(latRad) * tan(decl))

        guard cosHourAngle >= -1.0, cosHourAngle <= 1.0 else {
            return nil
        }

        let hourAngle = radiansToDegrees(acos(cosHourAngle))
        let solarNoonUTCMinutes = solarNoonUTCMinutes(for: longitude, equationOfTime: eqTime)
        let eventUTCMinutes = rising
            ? solarNoonUTCMinutes - (4.0 * hourAngle)
            : solarNoonUTCMinutes + (4.0 * hourAngle)
        return context.utcMidnight.addingTimeInterval(eventUTCMinutes * 60.0)
    }

    private static func solarCalculationContext(
        for eventDate: Date,
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone
    ) -> SolarCalculationContext? {
        guard coordinatesAreValid(latitude: latitude, longitude: longitude) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let year = calendar.dateComponents([.year], from: eventDate).year,
              let month = calendar.dateComponents([.month], from: eventDate).month,
              let day = calendar.dateComponents([.day], from: eventDate).day,
              let dayOfYear = calendar.ordinality(of: .day, in: .year, for: eventDate).map(Double.init) else {
            return nil
        }

        let utcCalendar = Calendar(identifier: .gregorian)
        guard let utcMidnight = utcCalendar.date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day)) else {
            return nil
        }

        return SolarCalculationContext(utcMidnight: utcMidnight, dayOfYear: dayOfYear)
    }

    private static func calendarForTimeZone(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static func fractionalYearAngle(for dayOfYear: Double) -> Double {
        (2.0 * .pi / 365.0) * (dayOfYear - 1.0)
    }

    private static func equationOfTime(for gamma: Double) -> Double {
        229.18 * (
            0.000075
            + 0.001868 * cos(gamma)
            - 0.032077 * sin(gamma)
            - 0.014615 * cos(2.0 * gamma)
            - 0.040849 * sin(2.0 * gamma)
        )
    }

    private static func solarDeclination(for gamma: Double) -> Double {
        0.006918
            - 0.399912 * cos(gamma)
            + 0.070257 * sin(gamma)
            - 0.006758 * cos(2.0 * gamma)
            + 0.000907 * sin(2.0 * gamma)
            - 0.002697 * cos(3.0 * gamma)
            + 0.001480 * sin(3.0 * gamma)
    }

    private static func solarNoonUTCMinutes(for longitude: Double, dayOfYear: Double) -> Double {
        let gamma = fractionalYearAngle(for: dayOfYear)
        let eqTime = equationOfTime(for: gamma)
        return solarNoonUTCMinutes(for: longitude, equationOfTime: eqTime)
    }

    private static func solarNoonUTCMinutes(for longitude: Double, equationOfTime: Double) -> Double {
        720.0 - (4.0 * longitude) - equationOfTime
    }

    private static func coordinatesAreValid(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite && (-90.0...90.0).contains(latitude) && (-180.0...180.0).contains(longitude)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    private static func degreesToRadians(_ value: Double) -> Double {
        value * .pi / 180.0
    }

    private static func radiansToDegrees(_ value: Double) -> Double {
        value * 180.0 / .pi
    }
}
