#!/usr/bin/env bash
# REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/install_device.sh [--build] [--device DEVICE_ID] [--app PATH] [--configuration Debug|Release]

Installs Travels onto a connected physical iPhone without uninstalling the app
or deleting its data container.

Options:
  --build               Build the app first using scripts/build_device.sh.
  --device DEVICE_ID    devicectl device identifier. If omitted, the script uses
                        the only available paired physical device.
  --app PATH            Path to Travels.app. Defaults to the script-managed
                        Debug device build output.
  --configuration NAME  Build configuration used with --build and default --app.
                        Defaults to Debug.
  -h, --help            Show this help.

Examples:
  scripts/install_device.sh --build
  scripts/install_device.sh --device F7AC9E82-CA67-521D-938F-C55D350BDE3A --build
  scripts/install_device.sh --app .build/device/Products/Debug-iphoneos/Travels.app
USAGE
}

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="${TRAVELS_BUILD_ROOT:-${repo_dir}/.build/device}"
configuration="Debug"
device_id="${TRAVELS_DEVICE_ID:-}"
app_path=""
build_first=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build)
      build_first=true
      shift
      ;;
    --device)
      if [[ $# -lt 2 ]]; then
        echo "error: --device requires a value" >&2
        exit 2
      fi
      device_id="$2"
      shift 2
      ;;
    --app)
      if [[ $# -lt 2 ]]; then
        echo "error: --app requires a value" >&2
        exit 2
      fi
      app_path="$2"
      shift 2
      ;;
    --configuration)
      if [[ $# -lt 2 ]]; then
        echo "error: --configuration requires a value" >&2
        exit 2
      fi
      configuration="$2"
      shift 2
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

case "$configuration" in
  Debug|Release) ;;
  *)
    echo "error: unsupported configuration: $configuration" >&2
    exit 2
    ;;
esac

if [[ "$build_first" == true ]]; then
  "${repo_dir}/scripts/build_device.sh" --configuration "$configuration"
fi

if [[ -z "$app_path" ]]; then
  app_path="${build_root}/Products/${configuration}-iphoneos/Travels.app"
fi

if [[ ! -d "$app_path" ]]; then
  echo "error: app bundle not found: $app_path" >&2
  echo "hint: run scripts/install_device.sh --build" >&2
  exit 1
fi

if [[ -z "$device_id" ]]; then
  available_device_ids=()
  while IFS= read -r candidate_device_id; do
    available_device_ids+=("$candidate_device_id")
  done < <(
      xcrun devicectl list devices | awk '
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
    echo "hint: connect/unlock the phone, trust this Mac, then run xcrun devicectl list devices" >&2
    exit 1
  fi
  if [[ "${#available_device_ids[@]}" -gt 1 ]]; then
    echo "error: multiple available devices found; pass --device DEVICE_ID" >&2
    xcrun devicectl list devices >&2
    exit 1
  fi
  device_id="${available_device_ids[0]}"
fi

echo "==> Installing non-destructively onto device $device_id"
echo "==> App: $app_path"
xcrun devicectl device install app --device "$device_id" "$app_path"
echo "==> Install completed without uninstalling the existing app"
