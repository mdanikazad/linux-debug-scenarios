#!/usr/bin/env bash
# scenario2-nginx-port-bind.sh
# ---------------------------------------------------------------
# Scenario: nginx is configured but won't start because port 80
# is already bound by something else.
# Your job : Find the conflict, free port 80, and start nginx.
# ---------------------------------------------------------------
set -e

SCEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="${SCEN_DIR}/.scenario2_conf"
RUN_DIR="${SCEN_DIR}/.scenario2_run"
LOG_DIR="${SCEN_DIR}/.scenario2_log"
mkdir -p "${CONF_DIR}" "${RUN_DIR}" "${LOG_DIR}"

if [ "$(id -u)" -ne 0 ]; then
    echo "[scenario2] Please run as root (sudo $0)" >&2
    exit 1
fi

if ! command -v nginx >/dev/null 2>&1; then
    echo "[scenario2] nginx not found. Install it first (brew install nginx | apt install nginx)." >&2
    exit 1
fi

cat > "${CONF_DIR}/nginx-lab.conf" <<EOF
worker_processes 1;
error_log ${LOG_DIR}/error.log;
pid       ${RUN_DIR}/nginx.pid;
daemon    on;

events { worker_connections 64; }

http {
    access_log ${LOG_DIR}/access.log;
    client_body_temp_path ${RUN_DIR}/client_body;
    proxy_temp_path       ${RUN_DIR}/proxy;
    fastcgi_temp_path     ${RUN_DIR}/fastcgi;
    uwsgi_temp_path       ${RUN_DIR}/uwsgi;
    scgi_temp_path        ${RUN_DIR}/scgi;

    server {
        listen 80 default_server;
        server_name _;
        root ${RUN_DIR};
    }
}
EOF

echo "[scenario2] Planting a process that already owns port 80 ..."
cd "${RUN_DIR}"
( python3 -m http.server 80 >"${LOG_DIR}/squatter.log" 2>&1 & echo $! >"${RUN_DIR}/squatter.pid" )
sleep 1

echo "[scenario2] Attempting to start nginx (expected to fail) ..."
nginx -t -c "${CONF_DIR}/nginx-lab.conf" 2>&1 | sed 's/^/[scenario2-nginx-t] /' || true
nginx -c "${CONF_DIR}/nginx-lab.conf" 2>&1 | sed 's/^/[scenario2-nginx] /' || true

cat <<'EOF'

============================================================
 SCENARIO 2 READY
============================================================
nginx is configured to listen on port 80, but the service
won't start. Something else is already holding that port.

Your goal: identify the squatter, stop it, and bring nginx up.

Tools an SRE would reach for:
  - sudo lsof -i :80
  - sudo netstat -anp tcp | grep '\.80 '
  - sudo ss -ltnp 'sport = :80'
  - nginx -t -c <conf>
  - tail -f the lab error.log

Lab files:
  - config:   .scenario2_conf/nginx-lab.conf
  - logs:     .scenario2_log/
  - pid file: .scenario2_run/squatter.pid

When fixed, verify with: curl -sI http://127.0.0.1/ | head -1
============================================================
EOF

exit 0

# ---- cleanup subcommand ----
if [ "${1:-}" = "cleanup" ]; then
set -e
SCEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="${SCEN_DIR}/.scenario2_run"
CONF_DIR="${SCEN_DIR}/.scenario2_conf"
LOG_DIR="${SCEN_DIR}/.scenario2_log"

if [ -f "${RUN_DIR}/nginx.pid" ]; then
    nginx -c "${CONF_DIR}/nginx-lab.conf" -s quit 2>/dev/null || true
fi
if [ -f "${RUN_DIR}/squatter.pid" ]; then
    kill -9 "$(cat "${RUN_DIR}/squatter.pid")" 2>/dev/null || true
fi
# Also catch any http.server still bound to 80 just in case.
pkill -9 -f "http.server 80" 2>/dev/null || true
rm -rf "${RUN_DIR}" "${CONF_DIR}" "${LOG_DIR}"
echo "[cleanup] scenario 2 cleaned up."

fi
