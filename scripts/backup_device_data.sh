#!/usr/bin/env bash
# REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/backup_device_data.sh [--device DEVICE_ID] [--output-root PATH] [--truncate-log]

Copies the Travels application-support directory from a paired physical iPhone,
validates the copied SQLite database, and writes a backup manifest. The phone's
maintenance log is changed only when --truncate-log is explicitly supplied and
the backup database passes its integrity check.

Options:
  --device DEVICE_ID    devicectl device identifier or name. If omitted, the
                        script uses the only available paired physical device.
  --output-root PATH    Parent directory for timestamped backups. Defaults to
                        ../device-backups relative to the repository.
  --truncate-log        Replace the on-device Maintenance.log with an empty
                        file after the backup has been validated.
  -h, --help            Show this help.

Environment overrides:
  TRAVELS_DEVICE_ID     Default device identifier or name.
  TRAVELS_BUNDLE_ID     App bundle identifier. Defaults to
                        com.adigitalanalog.Travels.
  TRAVELS_BACKUP_ROOT   Default backup parent directory.

Examples:
  scripts/backup_device_data.sh
  scripts/backup_device_data.sh --device Ersa
  scripts/backup_device_data.sh --device Ersa --truncate-log
USAGE
}

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
device_id="${TRAVELS_DEVICE_ID:-}"
bundle_id="${TRAVELS_BUNDLE_ID:-com.adigitalanalog.Travels}"
output_root="${TRAVELS_BACKUP_ROOT:-${repo_dir}/../device-backups}"
truncate_log=false
remote_support_path="Library/Application Support/Travels"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      if [[ $# -lt 2 ]]; then
        echo "error: --device requires a value" >&2
        exit 2
      fi
      device_id="$2"
      shift 2
      ;;
    --output-root)
      if [[ $# -lt 2 ]]; then
        echo "error: --output-root requires a value" >&2
        exit 2
      fi
      output_root="$2"
      shift 2
      ;;
    --truncate-log)
      truncate_log=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

for command in sqlite3 shasum; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "error: required command not found: $command" >&2
    exit 1
  fi
done

if [[ -x /usr/bin/devicectl ]]; then
  devicectl_command=(/usr/bin/devicectl)
elif command -v devicectl >/dev/null 2>&1; then
  devicectl_command=(devicectl)
elif command -v xcrun >/dev/null 2>&1 && xcrun --find devicectl >/dev/null 2>&1; then
  devicectl_command=(xcrun devicectl)
else
  echo "error: devicectl was not found at /usr/bin/devicectl, in PATH, or through xcrun" >&2
  exit 1
fi

if [[ -z "$device_id" ]]; then
  available_device_ids=()
  while IFS= read -r candidate_device_id; do
    available_device_ids+=("$candidate_device_id")
  done < <(
      "${devicectl_command[@]}" list devices | awk '
        /available/ {
          for (i = 1; i <= NF; i++) {
            if ($i ~ /^[0-9A-Fa-f-]{36}$/) {
              print $i
            }
          }
        }
      '
    )
  if [[ "${#available_device_ids[@]}" -eq 0 ]]; then
    echo "error: no available paired physical iOS device found" >&2
    echo "hint: connect/unlock the phone, trust this Mac, then run devicectl list devices" >&2
    exit 1
  fi
  if [[ "${#available_device_ids[@]}" -gt 1 ]]; then
    echo "error: multiple available devices found; pass --device DEVICE_ID" >&2
    "${devicectl_command[@]}" list devices >&2
    exit 1
  fi
  device_id="${available_device_ids[0]}"
fi

timestamp="$(date '+%Y-%m-%d-%H%M%S')"
backup_dir="${output_root}/${timestamp}-Travels"
manifest_path="${backup_dir}/backup-manifest.txt"
mkdir -p "$backup_dir"

echo "==> Backing up Travels data from device $device_id"
echo "==> Destination: $backup_dir"
"${devicectl_command[@]}" device copy from \
  --device "$device_id" \
  --domain-type appDataContainer \
  --domain-identifier "$bundle_id" \
  --source "$remote_support_path" \
  --destination "$backup_dir"

database_candidates=()
while IFS= read -r database_candidate; do
  database_candidates+=("$database_candidate")
done < <(find "$backup_dir" -type f -name 'Travels.sqlite' -print)
if [[ "${#database_candidates[@]}" -ne 1 ]]; then
  echo "error: expected exactly one Travels.sqlite in the copied data; found ${#database_candidates[@]}" >&2
  exit 1
fi
database_path="${database_candidates[0]}"

integrity_result="$(sqlite3 "$database_path" 'PRAGMA quick_check;')"
if [[ "$integrity_result" != "ok" ]]; then
  echo "error: copied database failed PRAGMA quick_check: $integrity_result" >&2
  echo "The on-device maintenance log was not changed." >&2
  exit 1
fi

table_count() {
  local table_name="$1"
  if [[ "$(sqlite3 "$database_path" "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = '${table_name}';")" == "1" ]]; then
    sqlite3 "$database_path" "SELECT count(*) FROM ${table_name};"
  else
    printf 'unavailable'
  fi
}

events_count="$(table_count events)"
geolocations_count="$(table_count geolocations)"
database_sha256="$(shasum -a 256 "$database_path" | awk '{print $1}')"
maintenance_log_path="$(find "$backup_dir" -type f -name 'Maintenance.log' -print -quit)"
if [[ -n "$maintenance_log_path" ]]; then
  maintenance_log_bytes="$(stat -f '%z' "$maintenance_log_path")"
else
  maintenance_log_bytes="missing"
fi

{
  printf 'created_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'device=%s\n' "$device_id"
  printf 'bundle_id=%s\n' "$bundle_id"
  printf 'database=%s\n' "${database_path#"${backup_dir}/"}"
  printf 'database_quick_check=%s\n' "$integrity_result"
  printf 'database_sha256=%s\n' "$database_sha256"
  printf 'events=%s\n' "$events_count"
  printf 'geolocations=%s\n' "$geolocations_count"
  printf 'maintenance_log_bytes=%s\n' "$maintenance_log_bytes"
  printf 'maintenance_log_truncation_requested=%s\n' "$truncate_log"
} > "$manifest_path"

echo "==> Database integrity: $integrity_result"
echo "==> Events: $events_count"
echo "==> Geolocations: $geolocations_count"
echo "==> Database SHA-256: $database_sha256"

if [[ "$truncate_log" == true ]]; then
  if [[ "$maintenance_log_bytes" == "missing" ]]; then
    echo "error: Maintenance.log was not present in the validated backup; refusing to truncate" >&2
    exit 1
  fi

  temporary_dir="$(mktemp -d)"
  preflight_dir="$(mktemp -d)"
  verification_dir="$(mktemp -d)"
  cleanup() {
    rm -rf "$temporary_dir" "$preflight_dir" "$verification_dir"
  }
  trap cleanup EXIT
  : > "${temporary_dir}/Maintenance.log"

  # REGRESSION GUARD: never clear diagnostics until the complete app-support
  # copy and SQLite integrity check above have succeeded. Verify the exact
  # remote object is a regular file, and target that file rather than its
  # parent directory so truncation cannot replace the Travels directory.
  echo "==> Verifying the on-device Maintenance.log is a regular file"
  preflight_log="${preflight_dir}/Maintenance.log"
  "${devicectl_command[@]}" device copy from \
    --device "$device_id" \
    --domain-type appDataContainer \
    --domain-identifier "$bundle_id" \
    --source "${remote_support_path}/Maintenance.log" \
    --destination "$preflight_log"
  if [[ ! -f "$preflight_log" || -L "$preflight_log" ]]; then
    echo "error: the on-device Maintenance.log did not copy as a regular file; refusing to truncate" >&2
    exit 1
  fi

  echo "==> Truncating the on-device Maintenance.log"
  "${devicectl_command[@]}" device copy to \
    --device "$device_id" \
    --domain-type appDataContainer \
    --domain-identifier "$bundle_id" \
    --source "${temporary_dir}/Maintenance.log" \
    --destination "${remote_support_path}/Maintenance.log"

  verification_log="${verification_dir}/Maintenance.log"
  "${devicectl_command[@]}" device copy from \
    --device "$device_id" \
    --domain-type appDataContainer \
    --domain-identifier "$bundle_id" \
    --source "${remote_support_path}/Maintenance.log" \
    --destination "$verification_log"

  if [[ ! -f "$verification_log" || -L "$verification_log" ]]; then
    echo "error: could not verify the on-device Maintenance.log as a regular file after truncation" >&2
    exit 1
  fi
  verification_bytes="$(stat -f '%z' "$verification_log")"
  if [[ "$verification_bytes" -ge "$maintenance_log_bytes" && "$maintenance_log_bytes" -gt 0 ]]; then
    echo "error: Maintenance.log did not become smaller after truncation" >&2
    exit 1
  fi
  if [[ "$verification_bytes" -gt 0 ]]; then
    echo "==> Maintenance.log was truncated; the app wrote $verification_bytes new byte(s) before verification"
  else
    echo "==> Maintenance.log was truncated to zero bytes"
  fi
  printf 'maintenance_log_bytes_after_truncation=%s\n' "$verification_bytes" >> "$manifest_path"
fi

echo "==> Backup completed: $backup_dir"
echo "==> Manifest: $manifest_path"
