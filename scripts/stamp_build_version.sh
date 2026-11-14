#!/usr/bin/env bash
# REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.
set -euo pipefail

project_dir="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
marketing_version="${MARKETING_VERSION:-2.0.0}"
state_dir="${project_dir}/.build"
display_state_file="${state_dir}/travels-version-state"
bundle_state_file="${state_dir}/travels-bundle-build-state"
minimum_bundle_build="${TRAVELS_MINIMUM_BUNDLE_BUILD:-311}"
source_plist="${project_dir}/iOSApp/TravelsApp/Info.plist"
# REGRESSION GUARD: Xcode processes Info.plist after this build phase, so the target must consume this generated plist; stamping only the product plist is overwritten with build-setting defaults.
generated_plist="${DERIVED_FILE_DIR:-${state_dir}}/TravelsStampedInfo.plist"
product_plist="${TARGET_BUILD_DIR:-}/$(basename "${FULL_PRODUCT_NAME:-Travels.app}")/Info.plist"

if ! command -v git >/dev/null 2>&1; then
  exit 0
fi

if ! git -C "$project_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

short_sha="$(git -C "$project_dir" rev-parse --short HEAD 2>/dev/null || true)"
if [[ -z "$short_sha" ]]; then
  exit 0
fi

tagged_commit=false
while IFS= read -r tag; do
  case "$tag" in
    "$marketing_version"|"v${marketing_version}")
      tagged_commit=true
      break
      ;;
  esac
done < <(git -C "$project_dir" tag --points-at HEAD 2>/dev/null || true)

if [[ "$tagged_commit" == true ]]; then
  display_version="${marketing_version}.0+${short_sha}"
  mkdir -p "$state_dir"
  printf '0\n' > "$display_state_file"
else
  stored_counter=0
  if [[ -f "$display_state_file" ]]; then
    read -r stored_counter < "$display_state_file" || stored_counter=0
  fi
  if [[ ! "$stored_counter" =~ ^[0-9]+$ ]]; then
    stored_counter=0
  fi

  display_version="${marketing_version}-dev.${stored_counter}+${short_sha}"
  mkdir -p "$state_dir"
  printf '%s\n' "$((stored_counter + 1))" > "$display_state_file"
fi

if [[ ! "$minimum_bundle_build" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: TRAVELS_MINIMUM_BUNDLE_BUILD must be a positive integer" >&2
  exit 2
fi

if [[ -n "${TRAVELS_BUNDLE_BUILD_NUMBER:-}" ]]; then
  if [[ ! "$TRAVELS_BUNDLE_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: TRAVELS_BUNDLE_BUILD_NUMBER must be a positive integer" >&2
    exit 2
  fi
  bundle_build="$TRAVELS_BUNDLE_BUILD_NUMBER"
else
  bundle_build="$minimum_bundle_build"
  if [[ -f "$bundle_state_file" ]]; then
    read -r stored_bundle_build < "$bundle_state_file" || stored_bundle_build="$minimum_bundle_build"
    if [[ "$stored_bundle_build" =~ ^[1-9][0-9]*$ ]] && (( stored_bundle_build > bundle_build )); then
      bundle_build="$stored_bundle_build"
    fi
  fi
fi

mkdir -p "$state_dir"
printf '%s\n' "$((bundle_build + 1))" > "$bundle_state_file"

set_plist_string() {
  local plist="$1"
  local key="$2"
  local value="$3"
  /usr/bin/plutil -replace "$key" -string "$value" "$plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :${key} ${value}" "$plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :${key} string ${value}" "$plist"
}

if [[ -f "$source_plist" ]]; then
  mkdir -p "$(dirname "$generated_plist")"
  /bin/cp "$source_plist" "$generated_plist"
  set_plist_string "$generated_plist" CFBundleVersion "$bundle_build"
  set_plist_string "$generated_plist" TravelsDisplayVersion "$display_version"
fi

if [[ -f "$product_plist" ]]; then
  set_plist_string "$product_plist" CFBundleVersion "$bundle_build"
  set_plist_string "$product_plist" TravelsDisplayVersion "$display_version"
fi

echo "Stamped CFBundleVersion ${bundle_build}"
echo "Stamped TravelsDisplayVersion ${display_version}"
