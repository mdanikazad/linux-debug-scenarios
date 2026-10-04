#!/usr/bin/env bash
# scenario5-memory-leak.sh
# ---------------------------------------------------------------
# Scenario: A process is leaking memory. Find which one (and
# which child / sub-process) and stop it.
# ---------------------------------------------------------------
set -e

SCEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCEN_DIR}/.scenario5_build"
mkdir -p "${BUILD_DIR}"

TOTAL_MB=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024)}')
if [ -z "${TOTAL_MB}" ] || [ "${TOTAL_MB}" -lt 1 ]; then
    TOTAL_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 4096)
fi

LEAK_CHUNK_MB=$(( TOTAL_MB / 20 ))
if [ "${LEAK_CHUNK_MB}" -lt 64  ]; then LEAK_CHUNK_MB=64; fi
if [ "${LEAK_CHUNK_MB}" -gt 512 ]; then LEAK_CHUNK_MB=512; fi

cat > "${BUILD_DIR}/leak.c" <<EOF
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

int main(int argc, char **argv) {
    /* Allocate ${LEAK_CHUNK_MB} MB every second and never free. */
    srand((unsigned)time(NULL) ^ (unsigned)getpid());
    long chunk = ${LEAK_CHUNK_MB} * 1024 * 1024;
    int  tag   = (argc > 1) ? atoi(argv[1]) : 0;
    while (1) {
        void *p = malloc(chunk);
        if (!p) { fprintf(stderr, "OOM tag=%d\n", tag); return 1; }
        memset(p, 0xAB, chunk);   /* touch pages so RSS actually grows */
        sleep(1);
    }
    return 0;
}
EOF

echo "[scenario5] Building leak binary (chunk=${LEAK_CHUNK_MB}MB per second) ..."
if command -v cc >/dev/null 2>&1; then
    cc -O2 -o "${BUILD_DIR}/leak" "${BUILD_DIR}/leak.c"
elif command -v gcc >/dev/null 2>&1; then
    gcc -O2 -o "${BUILD_DIR}/leak" "${BUILD_DIR}/leak.c"
elif command -v clang >/dev/null 2>&1; then
    clang -O2 -o "${BUILD_DIR}/leak" "${BUILD_DIR}/leak.c"
else
    echo "[scenario5] ERROR: no C compiler found (need cc/gcc/clang)." >&2
    exit 1
fi

echo "[scenario5] Launching 3 leak processes (tags 1..3) ..."
PIDS=()
for tag in 1 2 3; do
    "${BUILD_DIR}/leak" "${tag}" &
    PIDS+=($!)
done
echo "${PIDS[@]}" > "${BUILD_DIR}/pids.txt"
sleep 3

cat <<'EOF'

============================================================
 SCENARIO 5 READY
============================================================
A process is leaking memory on this host. Three candidates
are running; one of them is much worse than the others.

Your goal: identify the worst offender and stop it (you may
leave the others running if you want to compare RSS).

Tools an SRE would reach for:
  - top / htop  (sort by RES or %MEM)
  - ps aux --sort=-%mem | head
  - pidstat -r 1
  - smem -rs rss
  - /proc/<pid>/status    (VmRSS, VmSize)

Lab artifacts:
  - binary: .scenario5_build/leak
  - pids:   .scenario5_build/pids.txt
  - source: .scenario5_build/leak.c

When you're done, run:  bash scenario5-memory-leak.sh cleanup
============================================================
EOF

exit 0

# ---- cleanup subcommand ----
if [ "${1:-}" = "cleanup" ]; then
set -e
SCEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCEN_DIR}/.scenario5_build"
PIDS_FILE="${BUILD_DIR}/pids.txt"
if [ -f "${PIDS_FILE}" ]; then
    for p in $(cat "${PIDS_FILE}"); do
        kill -9 "${p}" 2>/dev/null || true
        echo "[cleanup] killed PID ${p}"
    done
fi
pkill -9 -f "${BUILD_DIR}/leak" 2>/dev/null || true
rm -rf "${BUILD_DIR}"
echo "[cleanup] scenario 5 cleaned up."

fi
