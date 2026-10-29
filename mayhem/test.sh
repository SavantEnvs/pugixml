#!/usr/bin/env bash
#
# mayhem/test.sh — RUN pugixml's own test suite (built by mayhem/build.sh) and report CTRF counts.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${CXX:=clang++}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

RUNNER="build/make-${CXX%% *}-debug-standard-any/test"
[ -x "$RUNNER" ] || { echo "missing $RUNNER — mayhem/build.sh should have built it" >&2; emit_ctrf pugixml-tests 0 1; exit $?; }

out="$("$RUNNER" 2>&1)"; rc=$?
printf '%s\n' "$out"

# The runner prints "Success: N tests passed." or "FAILURE: F out of T tests failed."; anything else
# (no summary, e.g. a neutered or crashed runner) counts as a failure.
if [ "$rc" -eq 0 ] && [[ "$out" =~ Success:\ ([0-9]+)\ tests\ passed\. ]] && [ "${BASH_REMATCH[1]}" -ge 100 ]; then
  emit_ctrf pugixml-tests "${BASH_REMATCH[1]}" 0
elif [[ "$out" =~ FAILURE:\ ([0-9]+)\ out\ of\ ([0-9]+)\ tests\ failed\. ]]; then
  emit_ctrf pugixml-tests $(( BASH_REMATCH[2] - BASH_REMATCH[1] )) "${BASH_REMATCH[1]}"
else
  emit_ctrf pugixml-tests 0 1
fi
