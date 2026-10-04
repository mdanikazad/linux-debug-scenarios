#!/usr/bin/env bash
# scenario3-disk-fill.sh
# ---------------------------------------------------------------
# Scenario: The / partition is ~90% full because of runaway logs.
# Your job : Find the offending log files and free up the space.
#
# We do NOT touch your real root partition; the mess lives in
# .scenario3_lab/ inside the repo so 'du' / 'df' can be used
# against the lab path to rehearse the workflow safely.
# ---------------------------------------------------------------
set -e

SCEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB="${SCEN_DIR}/.scenario3_lab"
LOG="${LAB}/var/log"
mkdir -p "${LOG}/nginx" "${LOG}/app" "${LOG}/audit"

echo "[scenario3] Creating realistic-looking log directories under ${LOG} ..."

for f in "${LOG}/nginx/access.log" "${LOG}/nginx/error.log" \
         "${LOG}/app/app.log"     "${LOG}/app/debug.log"  \
         "${LOG}/audit/audit.log"; do
    : > "$f"
done

echo "[scenario3] Writing ~250MB of garbage to ${LOG}/app/debug.log ..."
yes A | head -c 262144000 > "${LOG}/app/debug.log"

echo "[scenario3] Writing ~50MB to ${LOG}/nginx/access.log (red herring) ..."
yes A | head -c 52428800  > "${LOG}/nginx/access.log"

echo
echo "[scenario3] Current lab size:"
du -sh "${LAB}"/* 2>/dev/null | sed 's/^/  /'

cat <<'EOF'

============================================================
 SCENARIO 3 READY
============================================================
The / partition is reportedly ~90% full. The disk is being
eaten by logs. One file in particular is the runaway.

Your goal: locate the biggest log file(s) under the lab
directory and free up the space.

Tools an SRE would reach for:
  - df -h
  - sudo du -sh /* 2>/dev/null | sort -h | tail
  - du -ah /var/log | sort -h | tail
  - lsof +L1         # deleted-but-open files
  - find / -xdev -size +100M -type f

Lab root: .scenario3_lab/

When fixed, the runaway file under that tree should be gone
or dramatically smaller.
============================================================
EOF

exit 0

# ---- cleanup subcommand ----
if [ "${1:-}" = "cleanup" ]; then
set -e
SCEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rm -rf "${SCEN_DIR}/.scenario3_lab"
echo "[cleanup] scenario 3 cleaned up."

fi
