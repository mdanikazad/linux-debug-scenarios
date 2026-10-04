#!/usr/bin/env bash
# scenario4-network-misconfig.sh
# ---------------------------------------------------------------
# Scenario: An application can't be reached because the network
# is misconfigured (wrong/missing route, broken DNS, etc.).
# Your job : Restore connectivity.
#
# Implemented inside a local netns so we never touch the host's
# real network. Requires: Linux + sudo + iproute2.
# On macOS, this script prints a notice and exits cleanly.
# ---------------------------------------------------------------
set -e

SCEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB="${SCEN_DIR}/.scenario4_lab"
mkdir -p "${LAB}"

if [ "$(uname -s)" != "Linux" ]; then
    echo "[scenario4] Skipped: netns-based scenarios require Linux."
    echo "            (you can still study .scenario4_lab/ artifacts)"
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "[scenario4] Please run as root: sudo $0" >&2
    exit 1
fi

NS="scen4"
ip netns del "${NS}" 2>/dev/null || true

echo "[scenario4] Creating network namespace '${NS}' ..."
ip netns add "${NS}"
ip -netns "${NS}" link set lo up

cat > "${LAB}/service.py" <<'EOF'
import http.server, socketserver
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers()
        self.wfile.write(b"hello from scenario4\n")
    def log_message(self, *a, **k): pass
with socketserver.TCPServer(("127.0.0.1", 8080), H) as s:
    s.serve_forever()
EOF

echo "[scenario4] Starting HTTP service inside '${NS}' on 127.0.0.1:8080 ..."
ip netns exec "${NS}" python3 "${LAB}/service.py" \
    >"${LAB}/service.log" 2>&1 &
echo $! > "${LAB}/service.pid"

mkdir -p "${LAB}/etc"
cat > "${LAB}/etc/hosts" <<'EOF'
127.0.0.1   localhost
EOF
# Intentionally do NOT add 'app.local' - the user must add it.
ip netns exec "${NS}" bash -c "mount --bind ${LAB}/etc/hosts /etc/hosts"

# Wipe the default route so any non-loopback traffic fails.
ip -netns "${NS}" route flush table main >/dev/null 2>&1 || true
ip -netns "${NS}" route add 127.0.0.0/8 dev lo

cat <<'EOF'

============================================================
 SCENARIO 4 READY
============================================================
A service is running inside a network namespace but the
application cannot reach it. The namespace has:
  - no DNS resolution for the app's hostname
  - default route removed
  - the service bound only to 127.0.0.1:8080

Your goal: diagnose and restore connectivity.

Useful commands (sudo):
  - ip netns list
  - ip netns exec scen4 ip a
  - ip netns exec scen4 ip r
  - ip netns exec scen4 cat /etc/hosts
  - ip netns exec scen4 curl -v http://app.local:8080/

Lab files:
  - .scenario4_lab/service.py
  - .scenario4_lab/etc/hosts
============================================================
EOF

exit 0

# ---- cleanup subcommand ----
if [ "${1:-}" = "cleanup" ]; then
set -e
SCEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB="${SCEN_DIR}/.scenario4_lab"
NS="scen4"

if [ "$(uname -s)" = "Linux" ] && [ "$(id -u)" -eq 0 ]; then
    if [ -f "${LAB}/service.pid" ]; then
        kill -9 "$(cat "${LAB}/service.pid")" 2>/dev/null || true
    fi
    ip netns del "${NS}" 2>/dev/null || true
fi
rm -rf "${LAB}"
echo "[cleanup] scenario 4 cleaned up."

fi
