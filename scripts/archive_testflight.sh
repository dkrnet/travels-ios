#!/usr/bin/env bash
# REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/archive_testflight.sh --build-number NUMBER [--export] [--archive-path PATH] [--export-path PATH]

Creates and validates a Release archive suitable for external TestFlight.
Optionally exports an App Store Connect IPA. This script never uploads a build.

Options:
  --build-number NUMBER  Unused positive App Store Connect build number.
  --export               Export an IPA after creating the archive.
  --archive-path PATH    Override the .xcarchive output path.
  --export-path PATH     Override the IPA export directory.
  -h, --help             Show this help.
USAGE
}

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
marketing_version="2.0.0"
build_number=""
archive_path=""
export_path=""
should_export=false

is_ios_xcode_developer_dir() {
  local candidate="$1"
  [[ -x "${candidate}/usr/bin/xcodebuild" && -d "${candidate}/Platforms/iPhoneOS.platform" ]]
}

# REGRESSION GUARD: release archives require the full Xcode toolchain. Do not
# inherit a CommandLineTools-only xcode-select setting, which cannot archive iOS.
if [[ -n "${DEVELOPER_DIR:-}" ]] && is_ios_xcode_developer_dir "$DEVELOPER_DIR"; then
  :
elif selected_developer_dir="$(xcode-select -p 2>/dev/null)" && is_ios_xcode_developer_dir "$selected_developer_dir"; then
  DEVELOPER_DIR="$selected_developer_dir"
elif is_ios_xcode_developer_dir "/Applications/Xcode.app/Contents/Developer"; then
  DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
else
  echo "error: a full Xcode installation with the iPhoneOS platform is required" >&2
  exit 1
fi
export DEVELOPER_DIR

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-number)
      [[ $# -ge 2 ]] || { echo "error: --build-number requires a value" >&2; exit 2; }
      build_number="$2"
      shift 2
      ;;
    --export)
      should_export=true
      shift
      ;;
    --archive-path)
      [[ $# -ge 2 ]] || { echo "error: --archive-path requires a value" >&2; exit 2; }
      archive_path="$2"
      shift 2
      ;;
    --export-path)
      [[ $# -ge 2 ]] || { echo "error: --export-path requires a value" >&2; exit 2; }
      export_path="$2"
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

if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: --build-number must be an unused positive integer" >&2
  exit 2
fi

archive_path="${archive_path:-${repo_dir}/.build/testflight/Travels-${marketing_version}-${build_number}.xcarchive}"
export_path="${export_path:-${repo_dir}/.build/testflight/Travels-${marketing_version}-${build_number}}"
archive_info="${archive_path}/Products/Applications/Travels.app/Info.plist"
archive_app="${archive_path}/Products/Applications/Travels.app"

if [[ -e "$archive_path" ]]; then
  echo "error: archive path already exists: $archive_path" >&2
  exit 1
fi
if [[ "$should_export" == true && -e "$export_path" ]]; then
  echo "error: export path already exists: $export_path" >&2
  exit 1
fi
if [[ ! -f "${repo_dir}/Config/Signing.local.xcconfig" ]]; then
  echo "error: Config/Signing.local.xcconfig is required for signed archives" >&2
  exit 1
fi

# REGRESSION GUARD: App Store Connect rejects the entire upload when any app
# icon, including the 1024-pixel marketing icon, contains an alpha channel.
icon_dir="${repo_dir}/iOSApp/TravelsApp/Assets.xcassets/AppIcon.appiconset"
icon_count=0
while IFS= read -r -d '' icon_path; do
  ((icon_count += 1))
  icon_alpha="$(sips -g hasAlpha "$icon_path" 2>/dev/null | awk '/hasAlpha:/ { print $2 }')"
  if [[ "$icon_alpha" != "no" ]]; then
    echo "error: app icon contains an alpha channel: $icon_path" >&2
    exit 1
  fi
done < <(find "$icon_dir" -type f -name '*.png' -print0)
if [[ "$icon_count" -eq 0 ]]; then
  echo "error: no PNG app icons were found in $icon_dir" >&2
  exit 1
fi

mkdir -p "$(dirname "$archive_path")"

echo "==> Using Xcode at ${DEVELOPER_DIR}"
echo "==> Archiving Travels ${marketing_version} (${build_number})"
TRAVELS_BUNDLE_BUILD_NUMBER="$build_number" xcodebuild \
  -project "${repo_dir}/Travels.xcodeproj" \
  -scheme Travels \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive_path" \
  -allowProvisioningUpdates \
  archive

if [[ ! -f "$archive_info" ]]; then
  echo "error: archived app Info.plist was not found" >&2
  exit 1
fi

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$archive_info"
}

bundle_id="$(plist_value CFBundleIdentifier)"
archived_version="$(plist_value CFBundleShortVersionString)"
archived_build="$(plist_value CFBundleVersion)"
encryption_flag="$(plist_value ITSAppUsesNonExemptEncryption)"

[[ "$bundle_id" == "com.adigitalanalog.travels" ]] || { echo "error: unexpected bundle identifier: $bundle_id" >&2; exit 1; }
[[ "$archived_version" == "$marketing_version" ]] || { echo "error: unexpected marketing version: $archived_version" >&2; exit 1; }
[[ "$archived_build" == "$build_number" ]] || { echo "error: archive build number is $archived_build, expected $build_number" >&2; exit 1; }
[[ "$encryption_flag" == "false" ]] || { echo "error: ITSAppUsesNonExemptEncryption must be false" >&2; exit 1; }
[[ -f "${archive_app}/PrivacyInfo.xcprivacy" ]] || { echo "error: PrivacyInfo.xcprivacy is missing from the archive" >&2; exit 1; }

echo "==> Archive validation passed"
echo "    Bundle ID: $bundle_id"
echo "    Version:   $archived_version"
echo "    Build:     $archived_build"
echo "    Archive:   $archive_path"

if [[ "$should_export" == true ]]; then
  echo "==> Exporting App Store Connect IPA"
  xcodebuild \
    -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "${repo_dir}/Config/TestFlightExportOptions.plist" \
    -allowProvisioningUpdates

  ipa_path="$(find "$export_path" -maxdepth 1 -type f -name '*.ipa' -print -quit)"
  if [[ -z "$ipa_path" ]]; then
    echo "error: export completed without producing an IPA" >&2
    exit 1
  fi
  echo "==> Export validation passed"
  echo "    IPA: $ipa_path"
fi

echo "==> No build was uploaded. Use Xcode Organizer or Transporter only after final release review."
