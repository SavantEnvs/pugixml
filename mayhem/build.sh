#!/usr/bin/env bash
#
# mayhem/build.sh — build pugixml's fuzz harnesses (sanitized, DWARF 3) plus its own test suite
# (normal flags). Runs in /mayhem as `mayhem`; re-runnable and needs no network.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# Sanitized build dirs are named build-* so upstream's `/build*/` .gitignore entry covers them.
OUT=build-mayhem
mkdir -p "$OUT"

# 1) The library, instrumented for sanitizers AND coverage (fuzzer-no-link) so the fuzzed code has SanCov edges.
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -fsanitize=fuzzer-no-link -c src/pugixml.cpp -o "$OUT/pugixml.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$OUT/lsan_off.o"
# The standalone driver is C: compile it as C so its LLVMFuzzerTestOneInput reference isn't mangled.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OUT/standalone_main.o"

# 2) Each upstream harness, as a libFuzzer binary and as a run-once standalone reproducer.
for h in fuzz_parse fuzz_xpath; do
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -fsanitize=fuzzer-no-link -c "tests/$h.cpp" -o "$OUT/$h.o"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
      "$OUT/$h.o" "$OUT/pugixml.o" "$OUT/lsan_off.o" -o "/mayhem/$h"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS \
      "$OUT/$h.o" "$OUT/pugixml.o" "$OUT/lsan_off.o" "$OUT/standalone_main.o" -o "/mayhem/$h-standalone"
done

# 3) Upstream's own test suite with the project's NORMAL flags (no sanitizers, no -gdwarf-3);
#    test.sh only runs it. Output lands in build/ (gitignored upstream).
make -j"$MAYHEM_JOBS" CXX="$CXX" CXXFLAGS="-g -O2 $COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS" build/make-${CXX%% *}-debug-standard-any/test
