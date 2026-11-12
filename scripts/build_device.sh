#!/usr/bin/env bash
# REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/build_device.sh [--configuration Debug|Release] [--clean] [--no-allow-provisioning-updates]

Builds the Travels iOS app for a physical device and prints the .app path.

Options:
  --configuration NAME  Xcode build configuration. Defaults to Debug.
  --clean               Remove the script-managed device build output first.
  --no-allow-provisioning-updates
                        Do not pass -allowProvisioningUpdates to xcodebuild.
  -h, --help            Show this help.

Environment overrides:
  TRAVELS_SCHEME        Xcode scheme. Defaults to Travels.
  TRAVELS_PROJECT       Xcode project. Defaults to Travels.xcodeproj.
  TRAVELS_BUILD_ROOT    Build output root. Defaults to .build/device.
  TRAVELS_XCODE_LOG     xcodebuild log path. Defaults to .build/device/xcodebuild-NAME.log.
USAGE
}

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scheme="${TRAVELS_SCHEME:-Travels}"
project="${TRAVELS_PROJECT:-Travels.xcodeproj}"
configuration="Debug"
build_root="${TRAVELS_BUILD_ROOT:-${repo_dir}/.build/device}"
clean=false
allow_provisioning_updates=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      if [[ $# -lt 2 ]]; then
        echo "error: --configuration requires a value" >&2
        exit 2
      fi
      configuration="$2"
      shift 2
      ;;
    --clean)
      clean=true
      shift
      ;;
    --allow-provisioning-updates)
      allow_provisioning_updates=true
      shift
      ;;
    --no-allow-provisioning-updates)
      allow_provisioning_updates=false
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
  *)
    echo "error: unsupported configuration: $configuration" >&2
    exit 2
    ;;
esac

derived_data_path="${build_root}/DerivedData"
products_path="${build_root}/Products"
app_path="${products_path}/${configuration}-iphoneos/Travels.app"
xcode_log="${TRAVELS_XCODE_LOG:-${build_root}/xcodebuild-${configuration}.log}"

cd "$repo_dir"

if [[ "$clean" == true ]]; then
  echo "==> Removing $build_root"
  rm -rf "$build_root"
fi

mkdir -p "$build_root"

echo "==> Building $scheme for a physical iOS device"
build_command=(
  xcodebuild
  -project "$project"
  -scheme "$scheme"
  -configuration "$configuration"
  -destination 'generic/platform=iOS'
  -derivedDataPath "$derived_data_path"
)
if [[ "$allow_provisioning_updates" == true ]]; then
  build_command+=(-allowProvisioningUpdates)
fi
build_command+=(SYMROOT="$products_path" build)

if ! "${build_command[@]}" >"$xcode_log" 2>&1; then
  echo "error: device build failed" >&2
  echo "==> Relevant xcodebuild messages:" >&2
  grep -E "xcodeproj: error:|CodeSign|resource fork|Finder information|similar detritus|No Accounts|No profiles|DVTDeveloperAccountManager: Failed|missing Xcode-" "$xcode_log" >&2 || true
  if grep -Eq "resource fork|Finder information|similar detritus" "$xcode_log"; then
    cat >&2 <<'HINT'
==> Bundle metadata diagnosis:
The generated app bundle contains extended attributes that iOS code signing rejects.
Run scripts/build_device.sh --clean once. If it still fails, check whether the checkout or build output is inside a synced/Desktop folder that adds Finder/FileProvider metadata.
HINT
  fi
  if grep -Eq "xcodeproj: error: No Accounts|xcodeproj: error: No profiles" "$xcode_log"; then
    cat >&2 <<'HINT'
==> Signing diagnosis:
Xcode could not access a valid Apple developer account or provisioning profile for the app.
Open Xcode > Settings > Accounts, refresh or re-add the Apple ID, then open Travels.xcodeproj and confirm the Travels target has a valid team/profile.
If a valid local provisioning profile already exists, try:
  scripts/build_device.sh --no-allow-provisioning-updates
HINT
  fi
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
