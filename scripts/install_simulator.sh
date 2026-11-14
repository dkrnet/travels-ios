#!/usr/bin/env bash
# REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/install_simulator.sh [--build] [--fresh] [--launch] [--device DEVICE_ID] [--name NAME] [--app PATH] [--configuration Debug|Release]

Installs Travels on an iOS simulator. Existing app data is preserved unless
--fresh is explicitly supplied.

Options:
  --build               Build first using scripts/build_simulator.sh.
  --fresh               Uninstall Travels and delete its simulator data first.
  --launch              Launch Travels after installation.
  --device DEVICE_ID    Simulator UDID. Takes precedence over --name.
  --name NAME           Exact simulator name. Defaults to iPhone 17 Pro.
  --app PATH            Travels.app path. Defaults to the managed build output.
  --configuration NAME  Debug or Release. Defaults to Debug.
  -h, --help            Show this help.
USAGE
}

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="Debug"
device_id=""
simulator_name="${TRAVELS_SIMULATOR_NAME:-iPhone 17 Pro}"
build_root="${TRAVELS_BUILD_ROOT:-${repo_dir}/.build/simulator}"
app_path=""
build_first=false
fresh=false
launch=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build) build_first=true; shift ;;
    --fresh) fresh=true; shift ;;
    --launch) launch=true; shift ;;
    --device)
      [[ $# -ge 2 ]] || { echo "error: --device requires a value" >&2; exit 2; }
      device_id="$2"
      shift 2
      ;;
    --name)
      [[ $# -ge 2 ]] || { echo "error: --name requires a value" >&2; exit 2; }
      simulator_name="$2"
      shift 2
      ;;
    --app)
      [[ $# -ge 2 ]] || { echo "error: --app requires a value" >&2; exit 2; }
      app_path="$2"
      shift 2
      ;;
    --configuration)
      [[ $# -ge 2 ]] || { echo "error: --configuration requires a value" >&2; exit 2; }
      configuration="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$configuration" in
  Debug|Release) ;;
  *) echo "error: unsupported configuration: $configuration" >&2; exit 2 ;;
esac

resolve_simulator_id() {
  local target_name="$1"
  local candidate
  local matches=()

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] && matches+=("$candidate")
  done < <(
    xcrun simctl list devices available | awk -v target="$target_name" '
      {
        line = $0
        sub(/^[[:space:]]+/, "", line)
        prefix = target " ("
        if (substr(line, 1, length(prefix)) == prefix) {
          rest = substr(line, length(prefix) + 1)
          close_index = index(rest, ")")
          if (close_index > 1) print substr(rest, 1, close_index - 1)
        }
      }
    '
  )

  if [[ "${#matches[@]}" -eq 0 ]]; then
    echo "error: no available simulator named '$target_name' was found" >&2
    echo "hint: run xcrun simctl list devices available or pass --device DEVICE_ID" >&2
    exit 1
  fi
  if [[ "${#matches[@]}" -gt 1 ]]; then
    echo "error: multiple available simulators named '$target_name' were found; pass --device DEVICE_ID" >&2
    printf '  %s\n' "${matches[@]}" >&2
    exit 1
  fi

  printf '%s\n' "${matches[0]}"
}

if [[ -z "$device_id" ]]; then
  device_id="$(resolve_simulator_id "$simulator_name")"
fi

if [[ "$build_first" == true ]]; then
  "${repo_dir}/scripts/build_simulator.sh" --configuration "$configuration" --device "$device_id"
fi

if [[ -z "$app_path" ]]; then
  app_path="${build_root}/Products/${configuration}-iphonesimulator/Travels.app"
fi
if [[ ! -d "$app_path" ]]; then
  echo "error: app bundle not found: $app_path" >&2
  echo "hint: run scripts/install_simulator.sh --build" >&2
  exit 1
fi

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${app_path}/Info.plist" 2>/dev/null || true)"
if [[ -z "$bundle_id" ]]; then
  echo "error: built app does not contain a CFBundleIdentifier" >&2
  exit 1
fi

echo "==> Booting simulator $device_id"
xcrun simctl boot "$device_id" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$device_id" -b

if [[ "$fresh" == true ]]; then
  echo "==> Removing the existing $bundle_id app and simulator data"
  xcrun simctl uninstall "$device_id" "$bundle_id" >/dev/null 2>&1 || true
fi

echo "==> Installing $app_path"
xcrun simctl install "$device_id" "$app_path"

if [[ "$launch" == true ]]; then
  echo "==> Launching $bundle_id"
  xcrun simctl launch "$device_id" "$bundle_id"
fi

echo "==> Simulator install completed"

