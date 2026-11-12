#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
# REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

"""Recover logged Travels location events into an offline database copy.

The maintenance log intentionally includes a compact recovery record after a
location event is accepted. This tool parses those records, applies the same
accept/replace/reject rules as LocationFiltering.swift, and writes eligible
missing events to a supplied SQLite database. It never accesses an iPhone.
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import json
import math
import re
import shutil
import sqlite3
import sys
from pathlib import Path
from typing import Iterable
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


APPLE_REFERENCE_UNIX_SECONDS = 978_307_200.0
LOCATION_SERVICES_SOURCE = 1
DEFAULT_MINIMUM_DISTANCES = {
    "highDetail": 250.0,
    "balanced": 350.0,
    "batterySaver": 750.0,
    "roadTrip": 1_000.0,
}

RECOVERY_RECORD_RE = re.compile(
    r"Saved location event recovery details;\s+"
    r"eventID=(?P<event_id>-?\d+)\s+"
    r"kind=(?P<kind>\w+)\s+"
    r"timestamp=(?P<timestamp>.+?)\s+"
    r"latitude=(?P<latitude>[-+\d.eE]+)\s+"
    r"longitude=(?P<longitude>[-+\d.eE]+)\s+"
    r"horizontalAccuracy=(?P<accuracy>[^\s]+)\s+"
    r"speed=(?P<speed>[^\s]+)\s+"
    r"course=(?P<course>[^\s]+)\s+"
    r"manual=(?P<manual>true|false)\s+"
    r"source=(?P<context_source>[^\s]+)\s+"
    r"cached=(?P<cached>true|false)\s+"
    r"immediatePreciseEntry=(?P<immediate>true|false)\s+"
    r"replacingEventID=(?P<replacing_event_id>[^\s]+)"
)
ADAPTIVE_DISTANCE_RE = re.compile(
    r"Adaptive distance changed\s+[-+\d.eE]+m\s+->\s+(?P<distance>[-+\d.eE]+)m"
)
ACCEPTED_THRESHOLD_RE = re.compile(
    r"Location accepted(?: and replaced previous event)?\s+@\s+.+?"
    r"moved\s+[-+\d.eE]+m\s+which meets the\s+(?P<threshold>[-+\d.eE]+)m distance threshold"
)


@dataclasses.dataclass(frozen=True)
class LoggedLocationEvent:
    line_number: int
    logged_event_id: int
    logged_kind: str
    timestamp_text: str
    timestamp: dt.datetime
    latitude: float
    longitude: float
    horizontal_accuracy: float
    speed: float
    course: float
    manual: bool
    context_source: str
    cached: bool
    immediate_precise_entry: bool
    replacing_event_id: int | None
    minimum_distance_meters: float
    is_pausing: bool

    @property
    def apple_reference_timestamp(self) -> float:
        return self.timestamp.timestamp() - APPLE_REFERENCE_UNIX_SECONDS


@dataclasses.dataclass(frozen=True)
class StoredEvent:
    event_id: int
    latitude: float
    longitude: float
    horizontal_accuracy: float
    speed: float
    timestamp: float
    geolocation_id: int | None


@dataclasses.dataclass(frozen=True)
class RecoveryAction:
    line_number: int
    logged_event_id: int
    timestamp: str
    latitude: float
    longitude: float
    action: str
    reason: str
    affected_event_id: int | None = None


def parse_metric(value: str, suffix: str) -> float:
    normalized = value.removesuffix(suffix)
    if normalized == "unknown":
        return math.nan
    return float(normalized)


def parse_timestamp(value: str, time_zone: ZoneInfo) -> dt.datetime:
    normalized = value.replace("\u202f", " ").replace("\u00a0", " ").strip()
    formats = (
        "%m/%d/%y, %I:%M:%S %p",
        "%m/%d/%Y, %I:%M:%S %p",
        "%m/%d/%y, %H:%M:%S",
        "%m/%d/%Y, %H:%M:%S",
    )
    for date_format in formats:
        try:
            return dt.datetime.strptime(normalized, date_format).replace(tzinfo=time_zone)
        except ValueError:
            continue
    raise ValueError(f"unsupported location timestamp: {value!r}")


def parse_date_argument(value: str) -> dt.date:
    try:
        return dt.datetime.strptime(value, "%Y%m%d").date()
    except ValueError as error:
        raise argparse.ArgumentTypeError("date must be a valid calendar date in YYYYMMDD format") from error


def records_for_date(
    records: Iterable[LoggedLocationEvent],
    selected_date: dt.date,
) -> list[LoggedLocationEvent]:
    return [record for record in records if record.timestamp.date() == selected_date]


def parse_recovery_records(
    log_path: Path,
    time_zone: ZoneInfo,
    initial_minimum_distance: float,
) -> tuple[list[LoggedLocationEvent], list[str]]:
    records: list[LoggedLocationEvent] = []
    errors: list[str] = []
    minimum_distance = initial_minimum_distance
    is_pausing = False
    accepted_threshold: float | None = None

    with log_path.open("r", encoding="utf-8", errors="replace") as log_file:
        for line_number, line in enumerate(log_file, start=1):
            if "Adaptive distance changed" in line:
                if match := ADAPTIVE_DISTANCE_RE.search(line):
                    minimum_distance = float(match.group("distance"))
            if "Core Location paused location updates" in line:
                is_pausing = True
            elif "Core Location resumed location updates" in line:
                is_pausing = False

            if "Location accepted" in line:
                match = ACCEPTED_THRESHOLD_RE.search(line)
                accepted_threshold = float(match.group("threshold")) if match else None
                continue
            if "Location rejected @" in line:
                is_pausing = False
                accepted_threshold = None
                continue
            if "Saved location event recovery details" not in line:
                continue

            match = RECOVERY_RECORD_RE.search(line)
            if not match:
                errors.append(f"line {line_number}: malformed recovery record")
                continue
            try:
                replacing_text = match.group("replacing_event_id")
                records.append(
                    LoggedLocationEvent(
                        line_number=line_number,
                        logged_event_id=int(match.group("event_id")),
                        logged_kind=match.group("kind"),
                        timestamp_text=match.group("timestamp"),
                        timestamp=parse_timestamp(match.group("timestamp"), time_zone),
                        latitude=float(match.group("latitude")),
                        longitude=float(match.group("longitude")),
                        horizontal_accuracy=parse_metric(match.group("accuracy"), "m"),
                        speed=parse_metric(match.group("speed"), "m/s"),
                        course=float(match.group("course")) if match.group("course") != "unknown" else math.nan,
                        manual=match.group("manual") == "true",
                        context_source=match.group("context_source"),
                        cached=match.group("cached") == "true",
                        immediate_precise_entry=match.group("immediate") == "true",
                        replacing_event_id=None if replacing_text == "none" else int(replacing_text),
                        minimum_distance_meters=accepted_threshold or minimum_distance,
                        is_pausing=is_pausing,
                    )
                )
            except (TypeError, ValueError) as error:
                errors.append(f"line {line_number}: {error}")
            finally:
                # LocationTrackingService clears the pause state after handling one sample.
                is_pausing = False
                accepted_threshold = None

    return records, errors


def align_timestamps_with_database(
    connection: sqlite3.Connection,
    records: list[LoggedLocationEvent],
) -> tuple[list[LoggedLocationEvent], int]:
    """Infer changing device UTC offsets from log records still present in SQLite."""
    anchors: list[tuple[int, dt.tzinfo]] = []
    for record in records:
        if record.logged_event_id <= 0:
            continue
        row = connection.execute(
            "SELECT latitude, longitude, timestamp FROM events WHERE id = ?",
            (record.logged_event_id,),
        ).fetchone()
        if row is None:
            continue
        # Event IDs can be reused by accept-and-replace. Only the matching
        # coordinates are safe anchors for the historical log record.
        if abs(float(row["latitude"]) - record.latitude) > 0.00000051:
            continue
        if abs(float(row["longitude"]) - record.longitude) > 0.00000051:
            continue

        logged_wall_time = record.timestamp.replace(tzinfo=None)
        stored_utc = dt.datetime.fromtimestamp(
            float(row["timestamp"]) + APPLE_REFERENCE_UNIX_SECONDS,
            tz=dt.timezone.utc,
        ).replace(tzinfo=None)
        raw_offset_seconds = (logged_wall_time - stored_utc).total_seconds()
        rounded_offset_seconds = round(raw_offset_seconds / 900.0) * 900
        if abs(raw_offset_seconds - rounded_offset_seconds) > 2.0:
            continue
        if not (-14 * 3600 <= rounded_offset_seconds <= 14 * 3600):
            continue
        anchors.append(
            (
                record.line_number,
                dt.timezone(dt.timedelta(seconds=rounded_offset_seconds)),
            )
        )

    if not anchors:
        return records, 0

    aligned: list[LoggedLocationEvent] = []
    for record in records:
        _, inferred_time_zone = min(
            anchors,
            key=lambda anchor: (abs(anchor[0] - record.line_number), anchor[0] > record.line_number),
        )
        local_components = record.timestamp.replace(tzinfo=None)
        aligned.append(dataclasses.replace(record, timestamp=local_components.replace(tzinfo=inferred_time_zone)))
    return aligned, len(anchors)


def haversine_meters(
    latitude_1: float,
    longitude_1: float,
    latitude_2: float,
    longitude_2: float,
) -> float:
    radius = 6_371_000.0
    phi_1 = math.radians(latitude_1)
    phi_2 = math.radians(latitude_2)
    delta_phi = math.radians(latitude_2 - latitude_1)
    delta_lambda = math.radians(longitude_2 - longitude_1)
    a = (
        math.sin(delta_phi / 2) ** 2
        + math.cos(phi_1) * math.cos(phi_2) * math.sin(delta_lambda / 2) ** 2
    )
    return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def filter_decision(
    candidate: LoggedLocationEvent,
    previous: StoredEvent | None,
    *,
    paused_minimum_distance: float = 50.0,
    maximum_horizontal_accuracy: float = 100.0,
    improvement_window_seconds: float = 300.0,
) -> tuple[str, str]:
    if previous is None:
        return "accept", "no previous event available"
    if candidate.manual:
        return "accept", "manual capture requested"

    elapsed = candidate.apple_reference_timestamp - previous.timestamp
    if elapsed < 0:
        return "reject", "candidate timestamp is older than the previous accepted event"

    distance = haversine_meters(
        previous.latitude,
        previous.longitude,
        candidate.latitude,
        candidate.longitude,
    )
    if distance <= previous.horizontal_accuracy:
        more_accurate = candidate.horizontal_accuracy < previous.horizontal_accuracy
        candidate_speed_unavailable = not math.isfinite(candidate.speed) or candidate.speed < 0
        previous_speed_unavailable = not math.isfinite(previous.speed) or previous.speed < 0
        at_least_as_accurate_and_slower = (
            candidate.horizontal_accuracy <= previous.horizontal_accuracy
            and (
                (candidate.speed >= 0 and previous.speed >= 0 and candidate.speed < previous.speed)
                or (candidate_speed_unavailable and previous.speed <= 0)
                or (previous_speed_unavailable and candidate.speed <= 0)
            )
        )
        if elapsed < improvement_window_seconds and (more_accurate or at_least_as_accurate_and_slower):
            return "replace", "inside previous radius with a qualifying accuracy/speed improvement"
        return "reject", "inside previous event radius without a qualifying improvement"

    if distance <= candidate.horizontal_accuracy:
        return "reject", "within the candidate accuracy radius"

    threshold = paused_minimum_distance if candidate.is_pausing else candidate.minimum_distance_meters
    distance_ok = distance >= threshold
    accuracy_ok = candidate.horizontal_accuracy <= maximum_horizontal_accuracy
    if distance_ok and accuracy_ok:
        return "accept", f"moved {distance:.1f}m, meeting the {threshold:.1f}m threshold"
    return "reject", "did not meet the current filter rules"


def validate_database(connection: sqlite3.Connection) -> None:
    result = connection.execute("PRAGMA integrity_check").fetchone()
    if result is None or str(result[0]).lower() != "ok":
        raise RuntimeError(f"database integrity check failed: {result}")
    columns = {row[1] for row in connection.execute("PRAGMA table_info(events)")}
    required = {
        "id", "latitude", "longitude", "horizontalAccuracy", "course", "speed",
        "timestamp", "localizedDate", "source", "geolocationID", "solar_period",
        "solar_period_percent", "solar_period_calculated_at",
    }
    missing = required - columns
    if missing:
        raise RuntimeError(f"events table is missing required columns: {', '.join(sorted(missing))}")


def load_initial_minimum_distance(connection: sqlite3.Connection) -> float:
    row = connection.execute(
        "SELECT value FROM settings WHERE key = ?",
        ("modern.appSettings",),
    ).fetchone()
    if row:
        try:
            mode = json.loads(row[0]).get("locationDetailMode", "balanced")
            return DEFAULT_MINIMUM_DISTANCES.get(mode, DEFAULT_MINIMUM_DISTANCES["balanced"])
        except (json.JSONDecodeError, TypeError):
            pass
    return DEFAULT_MINIMUM_DISTANCES["balanced"]


def stored_event(row: sqlite3.Row | None) -> StoredEvent | None:
    if row is None:
        return None
    return StoredEvent(
        event_id=int(row["id"]),
        latitude=float(row["latitude"]),
        longitude=float(row["longitude"]),
        horizontal_accuracy=float(row["horizontalAccuracy"]),
        speed=float(row["speed"]),
        timestamp=float(row["timestamp"]),
        geolocation_id=row["geolocationID"],
    )


def find_existing_event(
    connection: sqlite3.Connection,
    candidate: LoggedLocationEvent,
    *,
    trust_logged_event_id: bool = True,
) -> StoredEvent | None:
    if trust_logged_event_id and candidate.logged_event_id > 0:
        row = connection.execute(
            "SELECT * FROM events WHERE id = ?",
            (candidate.logged_event_id,),
        ).fetchone()
        if row is not None:
            return stored_event(row)
    row = connection.execute(
        """
        SELECT * FROM events
        WHERE source = ?
          AND abs(timestamp - ?) <= 1.0
          AND abs(latitude - ?) <= 0.00000051
          AND abs(longitude - ?) <= 0.00000051
        ORDER BY abs(timestamp - ?), id
        LIMIT 1
        """,
        (
            LOCATION_SERVICES_SOURCE,
            candidate.apple_reference_timestamp,
            candidate.latitude,
            candidate.longitude,
            candidate.apple_reference_timestamp,
        ),
    ).fetchone()
    return stored_event(row)


def find_previous_event(connection: sqlite3.Connection, candidate: LoggedLocationEvent) -> StoredEvent | None:
    row = connection.execute(
        """
        SELECT * FROM events
        WHERE timestamp <= ? AND isDemo = 0
        ORDER BY timestamp DESC, id DESC
        LIMIT 1
        """,
        (candidate.apple_reference_timestamp,),
    ).fetchone()
    return stored_event(row)


def event_values(
    candidate: LoggedLocationEvent,
    geolocation_id: int | None,
) -> tuple[object, ...]:
    return (
        candidate.latitude,
        candidate.longitude,
        candidate.horizontal_accuracy,
        -1.0,
        0.0,
        candidate.course,
        candidate.speed,
        candidate.apple_reference_timestamp,
        candidate.timestamp.strftime("%Y-%m-%d"),
        LOCATION_SERVICES_SOURCE,
        geolocation_id,
        "",
        "",
        "",
        "",
        0,
        None,
        "unknown",
        None,
        dt.datetime.now(dt.timezone.utc).timestamp() - APPLE_REFERENCE_UNIX_SECONDS,
    )


def insert_event(
    connection: sqlite3.Connection,
    candidate: LoggedLocationEvent,
) -> int:
    cursor = connection.execute(
        """
        INSERT INTO events (
            latitude, longitude, horizontalAccuracy, verticalAccuracy, altitude, course, speed,
            timestamp, localizedDate, source, geolocationID, note, tags, externalReference,
            photoFilename, isDemo, tripEndpointOverride, solar_period, solar_period_percent,
            solar_period_calculated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        event_values(candidate, None),
    )
    return int(cursor.lastrowid)


def replace_event(
    connection: sqlite3.Connection,
    event_id: int,
    candidate: LoggedLocationEvent,
    geolocation_id: int | None,
) -> None:
    values = event_values(candidate, geolocation_id)
    connection.execute(
        """
        UPDATE events SET
            latitude = ?, longitude = ?, horizontalAccuracy = ?, verticalAccuracy = ?,
            altitude = ?, course = ?, speed = ?, timestamp = ?, localizedDate = ?,
            source = ?, geolocationID = ?, note = ?, tags = ?, externalReference = ?,
            photoFilename = ?, isDemo = ?, tripEndpointOverride = ?, solar_period = ?,
            solar_period_percent = ?, solar_period_calculated_at = ?
        WHERE id = ?
        """,
        (*values, event_id),
    )


def create_backup(database_path: Path) -> Path:
    timestamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_path = database_path.with_name(f"{database_path.name}.before-log-recovery-{timestamp}")
    shutil.copy2(database_path, backup_path)
    for suffix in ("-wal", "-shm"):
        sidecar = Path(f"{database_path}{suffix}")
        if sidecar.exists():
            shutil.copy2(sidecar, Path(f"{backup_path}{suffix}"))
    return backup_path


def recover_events(
    connection: sqlite3.Connection,
    candidates: Iterable[LoggedLocationEvent],
    *,
    apply_changes: bool,
    simulate_changes: bool = False,
) -> list[RecoveryAction]:
    candidate_list = list(candidates)
    actions: list[RecoveryAction] = []
    write_changes = apply_changes or simulate_changes
    terminal_candidates: dict[int, LoggedLocationEvent] = {}
    for candidate in candidate_list:
        if candidate.logged_event_id > 0:
            terminal_candidates[candidate.logged_event_id] = candidate
    completed_chains: dict[int, StoredEvent] = {}
    for logged_event_id, terminal_candidate in terminal_candidates.items():
        if existing := find_existing_event(
            connection,
            terminal_candidate,
            trust_logged_event_id=False,
        ):
            completed_chains[logged_event_id] = existing

    for candidate in candidate_list:
        if candidate.logged_event_id in completed_chains:
            existing = completed_chains[candidate.logged_event_id]
            actions.append(
                action_for(
                    candidate,
                    "already_present",
                    "final state for the logged event replacement chain already exists",
                    existing.event_id,
                )
            )
            continue
        existing = find_existing_event(connection, candidate)
        if existing is not None:
            actions.append(action_for(candidate, "already_present", "matching event already exists", existing.event_id))
            continue

        previous = find_previous_event(connection, candidate)
        decision, reason = filter_decision(candidate, previous)
        if decision == "reject":
            actions.append(action_for(candidate, "rejected", reason, previous.event_id if previous else None))
            continue

        if decision == "replace" and previous is not None:
            if write_changes:
                replace_event(connection, previous.event_id, candidate, previous.geolocation_id)
            actions.append(action_for(candidate, "would_replace" if not apply_changes else "replaced", reason, previous.event_id))
            continue

        inserted_id = insert_event(connection, candidate) if write_changes else None
        actions.append(action_for(candidate, "would_insert" if not apply_changes else "inserted", reason, inserted_id))
    return actions


def action_for(
    candidate: LoggedLocationEvent,
    action: str,
    reason: str,
    affected_event_id: int | None,
) -> RecoveryAction:
    return RecoveryAction(
        line_number=candidate.line_number,
        logged_event_id=candidate.logged_event_id,
        timestamp=candidate.timestamp.isoformat(),
        latitude=candidate.latitude,
        longitude=candidate.longitude,
        action=action,
        reason=reason,
        affected_event_id=affected_event_id,
    )


def write_report(
    report_path: Path,
    database_path: Path,
    log_path: Path,
    time_zone: ZoneInfo,
    parse_errors: list[str],
    actions: list[RecoveryAction],
    backup_path: Path | None,
    timestamp_anchor_count: int,
    selected_date: dt.date,
) -> None:
    counts: dict[str, int] = {}
    for action in actions:
        counts[action.action] = counts.get(action.action, 0) + 1
    report = {
        "database": str(database_path.resolve()),
        "log": str(log_path.resolve()),
        "time_zone": str(time_zone),
        "selected_date": selected_date.strftime("%Y%m%d"),
        "backup": str(backup_path.resolve()) if backup_path else None,
        "timestamp_anchor_count": timestamp_anchor_count,
        "parse_errors": parse_errors,
        "summary": counts,
        "actions": [dataclasses.asdict(action) for action in actions],
    }
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def print_event_actions(actions: Iterable[RecoveryAction]) -> None:
    for action in actions:
        outcome = "REJECTED" if action.action == "rejected" else "ACCEPTED"
        affected_event = (
            f" affectedEventID={action.affected_event_id}"
            if action.affected_event_id is not None
            else ""
        )
        print(
            f"{outcome} timestamp={action.timestamp} "
            f"latitude={action.latitude:.6f} longitude={action.longitude:.6f} "
            f"action={action.action}{affected_event} reason={action.reason}"
        )


def parse_arguments(arguments: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", required=True, type=Path, help="Offline Travels.sqlite copy to inspect or repair.")
    parser.add_argument("--log", required=True, type=Path, help="Maintenance.log snapshot to parse.")
    parser.add_argument(
        "--date",
        required=True,
        type=parse_date_argument,
        metavar="YYYYMMDD",
        help="Process only recovery records whose logged local date matches YYYYMMDD.",
    )
    parser.add_argument(
        "--time-zone",
        default="America/Los_Angeles",
        help="IANA time zone used when the phone formatted log timestamps (default: America/Los_Angeles).",
    )
    parser.add_argument(
        "--report",
        type=Path,
        help="JSON audit report path (default: beside the database, except in print-only mode).",
    )
    output_mode = parser.add_mutually_exclusive_group()
    output_mode.add_argument("--apply", action="store_true", help="Apply eligible inserts/replacements. Default is dry-run.")
    output_mode.add_argument(
        "--print-events",
        action="store_true",
        help="Print each selected event as accepted or rejected without changing the database.",
    )
    return parser.parse_args(arguments)


def main(arguments: list[str] | None = None) -> int:
    options = parse_arguments(arguments if arguments is not None else sys.argv[1:])
    if not options.database.is_file():
        raise SystemExit(f"database does not exist: {options.database}")
    if not options.log.is_file():
        raise SystemExit(f"log does not exist: {options.log}")
    try:
        time_zone = ZoneInfo(options.time_zone)
    except ZoneInfoNotFoundError as error:
        raise SystemExit(f"invalid IANA time zone: {options.time_zone}") from error

    report_path = options.report
    if report_path is None and not options.print_events:
        report_path = options.database.with_name(
            f"{options.database.stem}-location-recovery-{options.date.strftime('%Y%m%d')}-report.json"
        )
    backup_path: Path | None = None
    connection = sqlite3.connect(options.database)
    connection.row_factory = sqlite3.Row
    try:
        validate_database(connection)
        initial_distance = load_initial_minimum_distance(connection)
        candidates, parse_errors = parse_recovery_records(options.log, time_zone, initial_distance)
        candidates, timestamp_anchor_count = align_timestamps_with_database(connection, candidates)
        candidates = records_for_date(candidates, options.date)
        if options.apply:
            connection.execute("PRAGMA wal_checkpoint(FULL)")
            backup_path = create_backup(options.database)
            connection.execute("BEGIN IMMEDIATE")
        actions = recover_events(
            connection,
            candidates,
            apply_changes=options.apply,
            simulate_changes=not options.apply,
        )
        if options.apply:
            connection.commit()
            validate_database(connection)
        else:
            connection.rollback()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()

    if report_path is not None:
        write_report(
            report_path,
            options.database,
            options.log,
            time_zone,
            parse_errors,
            actions,
            backup_path,
            timestamp_anchor_count,
            options.date,
        )
    if options.print_events:
        print_event_actions(actions)
    counts: dict[str, int] = {}
    for action in actions:
        counts[action.action] = counts.get(action.action, 0) + 1
    mode = "APPLIED" if options.apply else ("PRINT ONLY" if options.print_events else "DRY RUN")
    print(
        f"{mode}: processed {len(actions)} recovery records for "
        f"{options.date.strftime('%Y%m%d')} with {len(parse_errors)} parse errors"
    )
    for action, count in sorted(counts.items()):
        print(f"  {action}: {count}")
    if backup_path:
        print(f"Backup: {backup_path}")
    if report_path is not None:
        print(f"Report: {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
