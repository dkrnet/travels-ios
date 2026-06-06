// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public enum DemoData {
    public static func seed(into store: TravelsStore, anchoredTo referenceDate: Date) throws {
        let calendar = Calendar.current
        let launchDay = calendar.startOfDay(for: referenceDate)

        let demoEvents = [
            DemoEvent(dayOffset: -3, minuteOffset: 7 * 60 + 5, latitude: 37.8044, longitude: -122.2711, note: "Leaving home.", speed: 0.0, horizontalAccuracy: 18, course: -1),
            DemoEvent(dayOffset: -3, minuteOffset: 7 * 60 + 12, latitude: 37.8053, longitude: -122.2701, note: "", speed: 11.2, horizontalAccuracy: 14, course: 95),
            DemoEvent(dayOffset: -3, minuteOffset: 7 * 60 + 20, latitude: 37.8068, longitude: -122.2686, note: "Quick coffee stop.", speed: 0.0, horizontalAccuracy: 12, course: -1),
            DemoEvent(dayOffset: -3, minuteOffset: 7 * 60 + 31, latitude: 37.8087, longitude: -122.2662, note: "", speed: 10.4, horizontalAccuracy: 13, course: 98),
            DemoEvent(dayOffset: -3, minuteOffset: 7 * 60 + 44, latitude: 37.8119, longitude: -122.2625, note: "At work.", speed: 0.0, horizontalAccuracy: 11, course: -1),
            DemoEvent(dayOffset: -3, minuteOffset: 12 * 60 + 8, latitude: 37.8138, longitude: -122.2609, note: "", speed: 0.0, horizontalAccuracy: 15, course: -1),
            DemoEvent(dayOffset: -3, minuteOffset: 12 * 60 + 16, latitude: 37.8157, longitude: -122.2580, note: "", speed: 0.0, horizontalAccuracy: 15, course: -1),
            DemoEvent(dayOffset: -3, minuteOffset: 17 * 60 + 20, latitude: 37.8128, longitude: -122.2612, note: "", speed: 11.0, horizontalAccuracy: 14, course: 260),
            DemoEvent(dayOffset: -3, minuteOffset: 17 * 60 + 35, latitude: 37.8069, longitude: -122.2684, note: "", speed: 10.8, horizontalAccuracy: 14, course: 255),
            DemoEvent(dayOffset: -3, minuteOffset: 17 * 60 + 48, latitude: 37.8044, longitude: -122.2711, note: "Back home.", speed: 0.0, horizontalAccuracy: 17, course: -1),

            DemoEvent(dayOffset: -2, minuteOffset: 8 * 60, latitude: 37.8044, longitude: -122.2711, note: "Morning bike ride.", speed: 0.0, horizontalAccuracy: 18, course: -1),
            DemoEvent(dayOffset: -2, minuteOffset: 8 * 60 + 10, latitude: 37.8057, longitude: -122.2700, note: "", speed: 5.8, horizontalAccuracy: 12, course: 87),
            DemoEvent(dayOffset: -2, minuteOffset: 8 * 60 + 20, latitude: 37.8078, longitude: -122.2681, note: "", speed: 5.7, horizontalAccuracy: 12, course: 89),
            DemoEvent(dayOffset: -2, minuteOffset: 8 * 60 + 30, latitude: 37.8100, longitude: -122.2660, note: "", speed: 0.0, horizontalAccuracy: 10, course: -1),
            DemoEvent(dayOffset: -2, minuteOffset: 8 * 60 + 41, latitude: 37.8210, longitude: -122.2504, note: "", speed: 5.9, horizontalAccuracy: 13, course: 54),
            DemoEvent(dayOffset: -2, minuteOffset: 8 * 60 + 55, latitude: 37.8044, longitude: -122.2711, note: "Done for now.", speed: 0.0, horizontalAccuracy: 17, course: -1),

            DemoEvent(dayOffset: -1, minuteOffset: 9 * 60 + 10, latitude: 37.8044, longitude: -122.2711, note: "Morning walk.", speed: 0.0, horizontalAccuracy: 18, course: -1),
            DemoEvent(dayOffset: -1, minuteOffset: 9 * 60 + 20, latitude: 37.8060, longitude: -122.2697, note: "", speed: 1.5, horizontalAccuracy: 10, course: 45),
            DemoEvent(dayOffset: -1, minuteOffset: 9 * 60 + 31, latitude: 37.8220, longitude: -122.2500, note: "", speed: 0.0, horizontalAccuracy: 12, course: -1),
            DemoEvent(dayOffset: -1, minuteOffset: 9 * 60 + 40, latitude: 37.8230, longitude: -122.2489, note: "", speed: 1.4, horizontalAccuracy: 11, course: 60),
            DemoEvent(dayOffset: -1, minuteOffset: 9 * 60 + 52, latitude: 37.8245, longitude: -122.2475, note: "", speed: 0.0, horizontalAccuracy: 12, course: -1),
            DemoEvent(dayOffset: -1, minuteOffset: 10 * 60 + 8, latitude: 37.8044, longitude: -122.2711, note: "Back home.", speed: 0.0, horizontalAccuracy: 18, course: -1)
        ]

        for demoEvent in demoEvents {
            guard let timestamp = calendar.date(byAdding: .day, value: demoEvent.dayOffset, to: launchDay)?
                .addingTimeInterval(TimeInterval(demoEvent.minuteOffset * 60)) else {
                continue
            }

            let event = LocationEvent(
                latitude: demoEvent.latitude,
                longitude: demoEvent.longitude,
                horizontalAccuracy: demoEvent.horizontalAccuracy,
                course: demoEvent.course,
                speed: demoEvent.speed,
                timestamp: timestamp,
                localizedDate: TravelsDateTools.localizedDayString(for: timestamp, timeZoneIdentifier: nil),
                source: .simulated,
                note: demoEvent.note
            )
            _ = try store.saveEvent(event, isDemo: true)
        }
    }
}

private struct DemoEvent {
    let dayOffset: Int
    let minuteOffset: Int
    let latitude: Double
    let longitude: Double
    let note: String
    let speed: Double
    let horizontalAccuracy: Double
    let course: Double
}
