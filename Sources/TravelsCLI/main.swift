// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import TravelsCore

@main
struct TravelsTool {
    static func main() throws {
        let args = CommandLine.arguments.dropFirst()
        guard let command = args.first else {
            printUsage()
            return
        }

        switch command {
        case "import-legacy":
            guard args.count == 3 else {
                print("Usage: travels-tool import-legacy <legacy travels.sqlite> <modern.sqlite>")
                return
            }
            let legacyURL = URL(fileURLWithPath: args.dropFirst().first!)
            let modernURL = URL(fileURLWithPath: args.dropFirst(2).first!)
            let store = try TravelsStore(url: modernURL)
            let summary = try LegacyTravelsImporter(destination: store).importDatabase(at: legacyURL)
            print("Imported \(summary.importedEvents) events, \(summary.importedGeolocations) geolocations, \(summary.importedSettings) settings; skipped \(summary.skippedDuplicates) duplicates.")

        case "import-gpx":
            guard args.count == 3 else {
                print("Usage: travels-tool import-gpx <file.gpx> <modern.sqlite>")
                return
            }
            let gpxURL = URL(fileURLWithPath: args.dropFirst().first!)
            let modernURL = URL(fileURLWithPath: args.dropFirst(2).first!)
            let store = try TravelsStore(url: modernURL)
            let result = try GPXImporter.parse(url: gpxURL)
            for event in result.events {
                _ = try store.saveEvent(event)
            }
            print("Imported \(result.events.count) GPX events; skipped \(result.skippedInvalidPoints) invalid points.")

        case "export-gpx":
            guard args.count == 3 else {
                print("Usage: travels-tool export-gpx <modern.sqlite> <output.gpx>")
                return
            }
            let modernURL = URL(fileURLWithPath: args.dropFirst().first!)
            let outputURL = URL(fileURLWithPath: args.dropFirst(2).first!)
            let store = try TravelsStore(url: modernURL)
            let events = try store.allEvents()
            let xml = try GPXExporter.export(events: events)
            try xml.write(to: outputURL, atomically: true, encoding: .utf8)
            print("Exported \(events.count) events to \(outputURL.path).")

        default:
            printUsage()
        }
    }

    private static func printUsage() {
        print("""
        travels-tool commands:
          import-legacy <legacy travels.sqlite> <modern.sqlite>
          import-gpx <file.gpx> <modern.sqlite>
          export-gpx <modern.sqlite> <output.gpx>
        """)
    }
}
