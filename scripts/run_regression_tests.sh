#!/usr/bin/env bash
# REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/run_regression_tests.sh [--filter TEST_FILTER] [--skip-full] [--failure-detail] [--verbose]

Runs the Travels Swift package regression tests.

Options:
  --filter TEST_FILTER  Run an additional focused XCTest filter.
  --skip-full          Skip the full `swift test` run and only run --filter.
  --failure-detail     Show detailed failure/error lines instead of a compact failing-test summary.
  --verbose            Show full SwiftPM/XCTest output, including passed tests.
  -h, --help           Show this help.

Environment overrides:
  TRAVELS_SCRIPT_HOME  Home/cache directory used by SwiftPM. Defaults to
                       .build/script-home so the command works in restricted
                       environments and does not depend on user cache writes.
  TRAVELS_TEST_LOG_DIR Directory for full test logs. Defaults to .build/test-logs.
  TRAVELS_SWIFT_FLAGS  Extra arguments passed before any --filter option.

Examples:
  scripts/run_regression_tests.sh
  scripts/run_regression_tests.sh --filter LocationTrackingStateMachineTests
  scripts/run_regression_tests.sh --skip-full --filter LocationTrackingStateMachineTests/testIdleDetectionRecordsActiveTransitionUsingFallbackReferenceWhenSpeedUnavailable
USAGE
}

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
filter=""
skip_full=false
failure_detail=false
verbose=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --filter)
      if [[ $# -lt 2 ]]; then
        echo "error: --filter requires a value" >&2
        exit 2
      fi
      filter="$2"
      shift 2
      ;;
    --skip-full)
      skip_full=true
      shift
      ;;
    --failure-detail)
      failure_detail=true
      shift
      ;;
    --verbose)
      verbose=true
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

cd "$repo_dir"

script_home="${TRAVELS_SCRIPT_HOME:-${repo_dir}/.build/script-home}"
log_dir="${TRAVELS_TEST_LOG_DIR:-${repo_dir}/.build/test-logs}"
mkdir -p "$script_home" "$log_dir" "${repo_dir}/.build/clang-module-cache"
export HOME="$script_home"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${repo_dir}/.build/clang-module-cache}"
swift_flags=(--disable-sandbox)
if [[ -n "${TRAVELS_SWIFT_FLAGS:-}" ]]; then
  # shellcheck disable=SC2206
  swift_flags+=(${TRAVELS_SWIFT_FLAGS})
fi

print_failure_summary() {
  local log_file="$1"
  awk '
    /: error: -\[/ {
      line = $0
      location = line
      sub(/: error: -.*/, "", location)
      test = line
      sub(/^.*: error: -\[/, "", test)
      sub(/\] :.*/, "", test)
      message = line
      sub(/^.*\] : /, "", message)
      key = test
      if (!(key in seen)) {
        seen[key] = 1
        order[++count] = key
        locations[key] = location
        messages[key] = message
      }
      next
    }
    /error: Process .*unexpected signal|unexpected signal|Fatal error|BUILD FAILED/ {
      other[++otherCount] = $0
    }
    END {
      if (count == 0) {
        print "  (No XCTest assertion lines found.)"
      } else {
        for (i = 1; i <= count; i++) {
          key = order[i]
          print "  - " key
          print "    " locations[key]
          if (messages[key] != "") {
            print "    " messages[key]
          }
        }
      }
      if (otherCount > 0) {
        print "  Other failures:"
        for (i = 1; i <= otherCount && i <= 8; i++) {
          print "    " other[i]
        }
      }
    }
  ' "$log_file"
}

run_test_command() {
  local label="$1"
  shift

  echo "==> $label"
  if [[ "$verbose" == true ]]; then
    swift test "${swift_flags[@]}" "$@"
    return
  fi

  local safe_label timestamp log_file status
  safe_label="$(printf '%s' "$label" | tr -cs '[:alnum:]_.-' '-')"
  timestamp="$(date +%Y%m%d-%H%M%S)"
  log_file="${log_dir}/${timestamp}-${safe_label}.log"

  set +e
  swift test "${swift_flags[@]}" "$@" >"$log_file" 2>&1
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    grep -E "Test Suite '.*' passed|Executed [0-9]+ tests|BUILD SUCCEEDED|Build complete|Regression test command completed" "$log_file" \
      | grep -v "Test Case .* passed" \
      | tail -n 8 || true
    echo "==> Passed. Full log: $log_file"
    return 0
  fi

  if [[ "$failure_detail" == true ]]; then
    echo "==> Failed. Key failure lines:"
    grep -E "error:|failed|FAILED|Fatal error|XCTAssert|unexpected signal|BUILD FAILED" "$log_file" \
      | grep -v "Test Case .* passed" \
      | tail -n 80 || true
  else
    echo "==> Failed. Failing tests:"
    print_failure_summary "$log_file"
    echo "==> Re-run with --failure-detail for assertion-by-assertion output."
  fi
  echo "==> Full log: $log_file"
  return "$status"
}

if [[ "$skip_full" == false ]]; then
  run_test_command "Running full Swift package test suite"
fi

if [[ -n "$filter" ]]; then
  run_test_command "Running focused Swift package test filter ${filter}" --filter "$filter"
fi

echo "==> Regression test command completed"
