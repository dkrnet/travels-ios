#!/usr/bin/env bash
# REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/build_simulator.sh [--configuration Debug|Release] [--device DEVICE_ID] [--name NAME] [--clean]

Builds the Travels iOS app for a simulator and prints its metadata and .app path.
The default destination is the available simulator named "iPhone 17 Pro".

Options:
  --configuration NAME  Xcode build configuration. Defaults to Debug.
  --device DEVICE_ID    Simulator UDID. Takes precedence over --name.
  --name NAME           Exact simulator name. Defaults to iPhone 17 Pro.
  --clean               Remove the script-managed simulator build output first.
  -h, --help            Show this help.

Environment overrides:
  TRAVELS_SCHEME          Xcode scheme. Defaults to Travels.
  TRAVELS_PROJECT         Xcode project. Defaults to Travels.xcodeproj.
  TRAVELS_SIMULATOR_NAME  Simulator name. Defaults to iPhone 17 Pro.
  TRAVELS_BUILD_ROOT      Build output root. Defaults to .build/simulator.
  TRAVELS_XCODE_LOG       xcodebuild log path. Defaults under the build root.
USAGE
}

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scheme="${TRAVELS_SCHEME:-Travels}"
project="${TRAVELS_PROJECT:-Travels.xcodeproj}"
configuration="Debug"
device_id=""
simulator_name="${TRAVELS_SIMULATOR_NAME:-iPhone 17 Pro}"
build_root="${TRAVELS_BUILD_ROOT:-${repo_dir}/.build/simulator}"
clean=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      [[ $# -ge 2 ]] || { echo "error: --configuration requires a value" >&2; exit 2; }
      configuration="$2"
      shift 2
      ;;
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
    --clean)
      clean=true
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

derived_data_path="${build_root}/DerivedData"
products_path="${build_root}/Products"
app_path="${products_path}/${configuration}-iphonesimulator/Travels.app"
xcode_log="${TRAVELS_XCODE_LOG:-${build_root}/xcodebuild-${configuration}.log}"

cd "$repo_dir"

if [[ "$clean" == true ]]; then
  echo "==> Removing $build_root"
  rm -rf "$build_root"
fi

mkdir -p "$build_root"

echo "==> Building $scheme for simulator $device_id"
if ! xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -configuration "$configuration" \
  -destination "platform=iOS Simulator,id=${device_id}" \
  -derivedDataPath "$derived_data_path" \
  SYMROOT="$products_path" \
  CODE_SIGNING_ALLOWED=NO \
  build >"$xcode_log" 2>&1; then
  echo "error: simulator build failed" >&2
  echo "==> Relevant xcodebuild messages:" >&2
  grep -E "(^|: )(error|warning):|BUILD FAILED|CoreSimulatorService" "$xcode_log" >&2 || true
  echo "==> Full xcodebuild log: $xcode_log" >&2
  exit 65
fi

if [[ ! -d "$app_path" ]]; then
  echo "error: expected built app was not found at $app_path" >&2
  echo "==> Full xcodebuild log: $xcode_log" >&2
  exit 1
fi

echo "==> Built app:"
echo "$app_path"

app_info_plist="${app_path}/Info.plist"
plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$app_info_plist" 2>/dev/null || true
}

bundle_version="$(plist_value CFBundleVersion)"
display_version="$(plist_value TravelsDisplayVersion)"

# REGRESSION GUARD: simulator builds must validate the same generated version metadata as device builds so an unstamped build is never mistaken for the current source.
if [[ ! "$bundle_version" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: built app has invalid or unstamped CFBundleVersion: ${bundle_version:-unavailable}" >&2
  exit 1
fi
if [[ ! "$display_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-dev\.[0-9]+|\.[0-9]+)\+[0-9A-Fa-f]+$ ]]; then
  echo "error: built app has invalid or unstamped TravelsDisplayVersion: ${display_version:-unavailable}" >&2
  exit 1
fi

echo "==> Build metadata:"
echo "    Bundle version: ${bundle_version}"
echo "    Build ID:       ${display_version}"

