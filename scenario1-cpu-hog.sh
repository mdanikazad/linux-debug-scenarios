#!/usr/bin/env bash
# scenario1-cpu-hog.sh
# ---------------------------------------------------------------
# Scenario: An application process is consuming huge CPU.
# Your job : Find the offending process and kill it.
#
# This script will:
#   1. Compile a tiny "tight loop" C program that pegs a CPU core.
#   2. Launch several copies of it in the background.
#   3. Leave them running for the user to investigate.
# ---------------------------------------------------------------
set -e

SCEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCEN_DIR}/.scenario1_build"
mkdir -p "${BUILD_DIR}"

echo "[scenario1] Preparing CPU-hog binaries in ${BUILD_DIR} ..."

cat > "${BUILD_DIR}/cpu_hog.c" <<'EOF'
#include <stdio.h>
int main(void) {
    /* Intentionally busy-loop to burn CPU. */
    while (1) { /* spin */ }
    return 0; /* unreachable */
}
EOF

if command -v cc >/dev/null 2>&1; then
    cc -O2 -o "${BUILD_DIR}/cpu_hog" "${BUILD_DIR}/cpu_hog.c"
elif command -v gcc >/dev/null 2>&1; then
    gcc -O2 -o "${BUILD_DIR}/cpu_hog" "${BUILD_DIR}/cpu_hog.c"
elif command -v clang >/dev/null 2>&1; then
    clang -O2 -o "${BUILD_DIR}/cpu_hog" "${BUILD_DIR}/cpu_hog.c"
else
    echo "[scenario1] ERROR: no C compiler found (need cc/gcc/clang)." >&2
    exit 1
fi

CORES=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 1)
HOGS=$(( CORES / 2 ))
if [ "${HOGS}" -lt 1 ]; then HOGS=1; fi
if [ "${HOGS}" -gt 4 ]; then HOGS=4; fi

echo "[scenario1] Launching ${HOGS} cpu_hog processes (cores detected: ${CORES}) ..."

PIDS=()
for i in $(seq 1 "${HOGS}"); do
    "${BUILD_DIR}/cpu_hog" &
    PIDS+=($!)
done

echo "${PIDS[@]}" > "${BUILD_DIR}/pids.txt"
sleep 2

cat <<'EOF'

============================================================
 SCENARIO 1 READY
============================================================
A misbehaving application is consuming huge CPU on this host.
Your goal: identify the process(es) and stop them.

Tools an SRE would reach for:
  - top / htop
  - ps auxf
  - pidstat 1
  - /proc/loadavg

Lab artifacts (intentionally easy to find - this is a lab):
  - PIDs:    .scenario1_build/pids.txt
  - Binary:  .scenario1_build/cpu_hog
  - Source:  .scenario1_build/cpu_hog.c

When you're done, run:  bash scenario1-cpu-hog.sh cleanup
============================================================
EOF

exit 0

# ---- cleanup subcommand ----
if [ "${1:-}" = "cleanup" ]; then
set -e
SCEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCEN_DIR}/.scenario1_build"
PIDS_FILE="${BUILD_DIR}/pids.txt"
if [ -f "${PIDS_FILE}" ]; then
    for p in $(cat "${PIDS_FILE}"); do
        kill -9 "${p}" 2>/dev/null || true
        echo "[cleanup] killed PID ${p}"
    done
fi
pkill -9 -f "${BUILD_DIR}/cpu_hog" 2>/dev/null || true
rm -rf "${BUILD_DIR}"
echo "[cleanup] scenario 1 cleaned up."

fi
