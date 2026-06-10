#!/usr/bin/env bash
set -euo pipefail

project_dir="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
marketing_version="${MARKETING_VERSION:-2.0.0}"
state_dir="${project_dir}/.build"
state_file="${state_dir}/travels-version-state"
source_plist="${project_dir}/iOSApp/TravelsApp/Info.plist"
generated_plist="${DERIVED_FILE_DIR:-${state_dir}}/TravelsStampedInfo.plist"

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
  build_version="${marketing_version}.0+${short_sha}"
  mkdir -p "$state_dir"
  printf '0\n' > "$state_file"
else
  stored_counter=0
  if [[ -f "$state_file" ]]; then
    read -r stored_counter < "$state_file" || stored_counter=0
  fi
  if [[ ! "$stored_counter" =~ ^[0-9]+$ ]]; then
    stored_counter=0
  fi

  build_version="${marketing_version}-dev.${stored_counter}+${short_sha}"
  mkdir -p "$state_dir"
  printf '%s\n' "$((stored_counter + 1))" > "$state_file"
fi

if [[ -f "$source_plist" ]]; then
  mkdir -p "$(dirname "$generated_plist")"
  /bin/cp "$source_plist" "$generated_plist"
  /usr/bin/plutil -replace CFBundleVersion -string "$build_version" "$generated_plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${build_version}" "$generated_plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${build_version}" "$generated_plist"
fi

echo "Stamped CFBundleVersion ${build_version}"
