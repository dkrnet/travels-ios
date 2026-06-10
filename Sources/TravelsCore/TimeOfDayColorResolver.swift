// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct RGBColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = cleaned.hasPrefix("#") ? String(cleaned.dropFirst()) : cleaned
        guard value.count == 6 else { return nil }

        let characters = Array(value)
        func component(_ start: Int) -> Double? {
            let pair = String(characters[start...start + 1])
            guard let byte = UInt8(pair, radix: 16) else { return nil }
            return Double(byte) / 255.0
        }

        guard let red = component(0),
              let green = component(2),
              let blue = component(4) else {
            return nil
        }

        self.init(red: red, green: green, blue: blue)
    }

    public func blended(with other: RGBColor, fraction: Double) -> RGBColor {
        let amount = min(max(fraction, 0.0), 1.0)
        if amount <= 0 {
            return self
        }
        if amount >= 1 {
            return other
        }

        let lhs = Self.linearized(self)
        let rhs = Self.linearized(other)
        let blended = RGBColor(
            red: Self.delinearize(lhs.red + (rhs.red - lhs.red) * amount),
            green: Self.delinearize(lhs.green + (rhs.green - lhs.green) * amount),
            blue: Self.delinearize(lhs.blue + (rhs.blue - lhs.blue) * amount)
        )
        return blended.clamped()
    }

    private func clamped() -> RGBColor {
        RGBColor(
            red: min(max(red, 0.0), 1.0),
            green: min(max(green, 0.0), 1.0),
            blue: min(max(blue, 0.0), 1.0)
        )
    }

    private static func linearized(_ color: RGBColor) -> RGBColor {
        RGBColor(
            red: linearize(color.red),
            green: linearize(color.green),
            blue: linearize(color.blue)
        )
    }

    private static func linearize(_ value: Double) -> Double {
        if value <= 0.04045 {
            return value / 12.92
        }
        return pow((value + 0.055) / 1.055, 2.4)
    }

    private static func delinearize(_ value: Double) -> Double {
        if value <= 0.0031308 {
            return value * 12.92
        }
        return 1.055 * pow(value, 1.0 / 2.4) - 0.055
    }
}

public enum TimeOfDayBaseColors {
    public static let midnight = RGBColor(hex: "#000000")!
    public static let endOfNight = RGBColor(hex: "#2F3437")!
    public static let morningTwilight = RGBColor(hex: "#F2A15B")!
    public static let beginningOfDay = RGBColor(hex: "#63C3FF")!
    public static let midday = RGBColor(hex: "#0077CC")!
    public static let endOfDay = RGBColor(hex: "#2FAF9B")!
    public static let eveningTwilight = RGBColor(hex: "#D96F5D")!
    public static let beginningOfNight = RGBColor(hex: "#2F3437")!
    public static let unknown = RGBColor(hex: "#A3A3A3")!
}

public struct TimeOfDayColorResolver: Sendable {
    public init() {}

    public func color(for detail: EventDetail) -> RGBColor {
        switch detail.event.solarPeriod {
        case .morningCivilTwilight:
            return twilightColor(
                percent: detail.event.solarPeriodPercent,
                start: TimeOfDayBaseColors.endOfNight,
                middle: TimeOfDayBaseColors.morningTwilight,
                end: TimeOfDayBaseColors.beginningOfDay
            )
        case .day:
            return twilightColor(
                percent: detail.event.solarPeriodPercent,
                start: TimeOfDayBaseColors.beginningOfDay,
                middle: TimeOfDayBaseColors.midday,
                end: TimeOfDayBaseColors.endOfDay
            )
        case .eveningCivilTwilight:
            return twilightColor(
                percent: detail.event.solarPeriodPercent,
                start: TimeOfDayBaseColors.endOfDay,
                middle: TimeOfDayBaseColors.eveningTwilight,
                end: TimeOfDayBaseColors.beginningOfNight
            )
        case .nightBeforeMidnight, .nightAfterMidnight:
            return twilightColor(
                percent: detail.event.solarPeriodPercent,
                start: TimeOfDayBaseColors.beginningOfNight,
                middle: TimeOfDayBaseColors.midnight,
                end: TimeOfDayBaseColors.beginningOfNight
            )
        case .unknown:
            return TimeOfDayBaseColors.unknown
        }
    }

    public func displayText(for detail: EventDetail) -> String {
        switch detail.event.solarPeriod {
        case .morningCivilTwilight:
            return twilightDisplayText(
                prefix: "Morning Twilight",
                percent: detail.event.solarPeriodPercent
            )
        case .day:
            return "Day"
        case .eveningCivilTwilight:
            return twilightDisplayText(
                prefix: "Evening Twilight",
                percent: detail.event.solarPeriodPercent
            )
        case .nightBeforeMidnight, .nightAfterMidnight:
            return "Night"
        case .unknown:
            return "Unknown"
        }
    }

    private func twilightColor(percent: Double?, start: RGBColor, middle: RGBColor, end: RGBColor) -> RGBColor {
        guard let percent else {
            return middle
        }

        let clamped = min(max(percent, 0.0), 1.0)
        if clamped <= 0.5 {
            return start.blended(with: middle, fraction: clamped / 0.5)
        }
        return middle.blended(with: end, fraction: (clamped - 0.5) / 0.5)
    }

    private func twilightDisplayText(prefix: String, percent: Double?) -> String {
        guard let percent else {
            return prefix
        }

        let clamped = min(max(percent, 0.0), 1.0)
        let percentage = Int((clamped * 100.0).rounded())
        return "\(prefix) - \(percentage)%"
    }

}
