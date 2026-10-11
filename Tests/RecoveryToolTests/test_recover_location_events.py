# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
# REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

from __future__ import annotations

import datetime as dt
import io
import importlib.util
import sqlite3
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from zoneinfo import ZoneInfo


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPOSITORY_ROOT / "scripts" / "recover_location_events.py"
SPEC = importlib.util.spec_from_file_location("recover_location_events", MODULE_PATH)
assert SPEC and SPEC.loader
recovery = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = recovery
SPEC.loader.exec_module(recovery)


EVENTS_SCHEMA = """
CREATE TABLE events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    horizontalAccuracy REAL NOT NULL DEFAULT -1,
    verticalAccuracy REAL NOT NULL DEFAULT -1,
    altitude REAL NOT NULL DEFAULT 0,
    course REAL NOT NULL DEFAULT -1,
    speed REAL NOT NULL DEFAULT -1,
    timestamp REAL NOT NULL,
    localizedDate TEXT,
    source INTEGER NOT NULL,
    geolocationID INTEGER,
    note TEXT NOT NULL DEFAULT '',
    tags TEXT NOT NULL DEFAULT '',
    externalReference TEXT NOT NULL DEFAULT '',
    photoFilename TEXT NOT NULL DEFAULT '',
    isDemo INTEGER NOT NULL DEFAULT 0,
    tripEndpointOverride INTEGER,
    solar_period TEXT NOT NULL DEFAULT 'unknown',
    solar_period_percent REAL,
    solar_period_calculated_at REAL,
    UNIQUE(latitude, longitude, timestamp, source, externalReference)
);
CREATE TABLE settings (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
"""


def recovery_line(
    *,
    event_id: int = 0,
    timestamp: str = "7/18/26, 8:36:00\u202fAM",
    latitude: float = 33.787584,
    longitude: float = -118.024203,
    accuracy: float = 10.0,
    speed: float = 0.0,
    manual: bool = False,
) -> str:
    return (
        "[08:36:00] [Location] Saved location event recovery details; "
        f"eventID={event_id} kind=new timestamp={timestamp} latitude={latitude:.6f} "
        f"longitude={longitude:.6f} horizontalAccuracy={accuracy:.1f}m speed={speed:.2f}m/s "
        f"course=-1.0 manual={str(manual).lower()} source=coreLocation cached=false "
        "immediatePreciseEntry=false replacingEventID=none\n"
    )


class RecoveryToolTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.database = self.root / "Travels.sqlite"
        self.log = self.root / "Maintenance.log"
        connection = sqlite3.connect(self.database)
        connection.executescript(EVENTS_SCHEMA)
        connection.execute(
            "INSERT INTO settings(key, value) VALUES(?, ?)",
            ("modern.appSettings", '{"locationDetailMode":"balanced"}'),
        )
        connection.commit()
        connection.close()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_parser_handles_narrow_no_break_space_and_adaptive_distance(self) -> None:
        self.log.write_text(
            "[08:35:00] [Location] Adaptive distance changed 350.0m -> 612.5m; reason=test.\n"
            + recovery_line(),
            encoding="utf-8",
        )
        records, errors = recovery.parse_recovery_records(
            self.log,
            ZoneInfo("America/Los_Angeles"),
            350.0,
        )
        self.assertEqual(errors, [])
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0].timestamp.hour, 8)
        self.assertEqual(records[0].minimum_distance_meters, 612.5)

    def test_filter_matches_accept_replace_and_reject_rules(self) -> None:
        self.log.write_text(recovery_line(), encoding="utf-8")
        candidate = recovery.parse_recovery_records(
            self.log,
            ZoneInfo("America/Los_Angeles"),
            350.0,
        )[0][0]
        earlier = candidate.apple_reference_timestamp - 60
        far_previous = recovery.StoredEvent(1, 33.780000, -118.024203, 10.0, 5.0, earlier, None)
        self.assertEqual(recovery.filter_decision(candidate, far_previous)[0], "accept")

        nearby_previous = recovery.StoredEvent(1, candidate.latitude, candidate.longitude, 20.0, 5.0, earlier, None)
        self.assertEqual(recovery.filter_decision(candidate, nearby_previous)[0], "replace")

        accurate_previous = recovery.StoredEvent(1, candidate.latitude, candidate.longitude, 5.0, 0.0, earlier, None)
        self.assertEqual(recovery.filter_decision(candidate, accurate_previous)[0], "reject")

    def test_apply_inserts_missing_event_and_skips_tolerant_duplicate(self) -> None:
        self.log.write_text(recovery_line() + recovery_line(event_id=42), encoding="utf-8")
        connection = sqlite3.connect(self.database)
        connection.row_factory = sqlite3.Row
        records, errors = recovery.parse_recovery_records(
            self.log,
            ZoneInfo("America/Los_Angeles"),
            recovery.load_initial_minimum_distance(connection),
        )
        self.assertEqual(errors, [])
        actions = recovery.recover_events(
            connection,
            records,
            apply_changes=True,
        )
        connection.commit()
        self.assertEqual([action.action for action in actions], ["inserted", "already_present"])
        self.assertEqual(connection.execute("SELECT count(*) FROM events").fetchone()[0], 1)
        connection.close()

    def test_manual_event_bypasses_distance_filter(self) -> None:
        self.log.write_text(recovery_line(manual=True), encoding="utf-8")
        records, _ = recovery.parse_recovery_records(
            self.log,
            ZoneInfo("America/Los_Angeles"),
            350.0,
        )
        candidate = records[0]
        previous = recovery.StoredEvent(
            1,
            candidate.latitude,
            candidate.longitude,
            1.0,
            0.0,
            candidate.apple_reference_timestamp + 60,
            None,
        )
        self.assertEqual(recovery.filter_decision(candidate, previous)[0], "accept")

    def test_dry_run_simulates_insert_before_later_replacement(self) -> None:
        self.log.write_text(
            recovery_line(
                timestamp="10/10/26, 9:29:49\u202fAM",
                latitude=41.797153,
                longitude=12.246577,
                accuracy=897.9,
                speed=-1.0,
                manual=True,
            )
            + recovery_line(
                timestamp="10/10/26, 9:34:02\u202fAM",
                latitude=41.797216,
                longitude=12.245082,
                accuracy=229.0,
                speed=-1.0,
            ),
            encoding="utf-8",
        )
        connection = sqlite3.connect(self.database)
        connection.row_factory = sqlite3.Row
        records, _ = recovery.parse_recovery_records(
            self.log,
            ZoneInfo("Europe/Rome"),
            350.0,
        )
        actions = recovery.recover_events(
            connection,
            records,
            apply_changes=False,
            simulate_changes=True,
        )
        self.assertEqual([action.action for action in actions], ["would_insert", "would_replace"])
        connection.rollback()
        self.assertEqual(connection.execute("SELECT count(*) FROM events").fetchone()[0], 0)
        connection.close()

    def test_replacement_chain_is_idempotent_after_final_state_exists(self) -> None:
        self.log.write_text(
            recovery_line(
                event_id=83,
                timestamp="10/10/26, 9:29:49\u202fAM",
                latitude=41.797153,
                longitude=12.246577,
                accuracy=897.9,
                speed=-1.0,
                manual=True,
            )
            + recovery_line(
                event_id=83,
                timestamp="10/10/26, 9:34:02\u202fAM",
                latitude=41.797216,
                longitude=12.245082,
                accuracy=229.0,
                speed=-1.0,
            ),
            encoding="utf-8",
        )
        connection = sqlite3.connect(self.database)
        connection.row_factory = sqlite3.Row
        records, _ = recovery.parse_recovery_records(
            self.log,
            ZoneInfo("Europe/Rome"),
            350.0,
        )
        first_actions = recovery.recover_events(connection, records, apply_changes=True)
        connection.commit()
        second_actions = recovery.recover_events(
            connection,
            records,
            apply_changes=False,
            simulate_changes=True,
        )
        connection.rollback()
        self.assertEqual([action.action for action in first_actions], ["inserted", "replaced"])
        self.assertEqual([action.action for action in second_actions], ["already_present", "already_present"])
        self.assertEqual(connection.execute("SELECT count(*) FROM events").fetchone()[0], 1)
        connection.close()

    def test_timestamp_alignment_uses_nearby_matching_database_anchor(self) -> None:
        self.log.write_text(
            recovery_line(
                event_id=7,
                timestamp="10/10/26, 8:19:23\u202fAM",
                latitude=41.797605,
                longitude=12.247041,
            )
            + recovery_line(
                timestamp="10/10/26, 8:25:28\u202fAM",
                latitude=41.797608,
                longitude=12.247034,
            ),
            encoding="utf-8",
        )
        connection = sqlite3.connect(self.database)
        connection.row_factory = sqlite3.Row
        rome_timestamp = recovery.parse_timestamp(
            "10/10/26, 8:19:23 AM",
            ZoneInfo("Europe/Rome"),
        ).timestamp() - recovery.APPLE_REFERENCE_UNIX_SECONDS
        connection.execute(
            """
            INSERT INTO events (
                id, latitude, longitude, horizontalAccuracy, verticalAccuracy, altitude,
                course, speed, timestamp, localizedDate, source, geolocationID, note,
                tags, externalReference, photoFilename, isDemo, tripEndpointOverride,
                solar_period, solar_period_percent, solar_period_calculated_at
            ) VALUES (7, 41.797605, 12.247041, 10, -1, 0, -1, 0, ?, '2026-10-10', 1,
                      NULL, '', '', '', '', 0, NULL, 'unknown', NULL, 0)
            """,
            (rome_timestamp,),
        )
        connection.commit()
        records, _ = recovery.parse_recovery_records(
            self.log,
            ZoneInfo("America/Los_Angeles"),
            350.0,
        )
        aligned, anchor_count = recovery.align_timestamps_with_database(connection, records)
        self.assertEqual(anchor_count, 1)
        self.assertEqual(aligned[1].timestamp.utcoffset(), dt.timedelta(hours=2))
        self.assertEqual(aligned[1].timestamp.hour, 8)
        connection.close()

    def test_print_events_processes_only_requested_date_without_writing(self) -> None:
        self.log.write_text(
            recovery_line(timestamp="7/18/26, 8:36:00\u202fAM")
            + recovery_line(
                timestamp="7/19/26, 8:36:00\u202fAM",
                latitude=34.100000,
                longitude=-118.200000,
            ),
            encoding="utf-8",
        )
        output = io.StringIO()
        with redirect_stdout(output):
            result = recovery.main(
                [
                    "--database", str(self.database),
                    "--log", str(self.log),
                    "--date", "20260719",
                    "--print-events",
                ]
            )
        self.assertEqual(result, 0)
        self.assertIn("ACCEPTED timestamp=2026-07-19", output.getvalue())
        self.assertNotIn("timestamp=2026-07-18", output.getvalue())
        self.assertIn("PRINT ONLY: processed 1 recovery records for 20260719", output.getvalue())
        connection = sqlite3.connect(self.database)
        self.assertEqual(connection.execute("SELECT count(*) FROM events").fetchone()[0], 0)
        connection.close()
        self.assertFalse((self.root / "Travels-location-recovery-20260719-report.json").exists())

    def test_date_must_be_valid_yyyymmdd(self) -> None:
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            recovery.parse_arguments(
                [
                    "--database", str(self.database),
                    "--log", str(self.log),
                    "--date", "20260230",
                ]
            )

    def test_apply_and_print_events_are_mutually_exclusive(self) -> None:
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            recovery.parse_arguments(
                [
                    "--database", str(self.database),
                    "--log", str(self.log),
                    "--date", "20260718",
                    "--apply",
                    "--print-events",
                ]
            )


if __name__ == "__main__":
    unittest.main()
