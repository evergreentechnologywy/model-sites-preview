#!/usr/bin/env bash
# Evergreen fleet — primary Cursor Cloud Tailscale install + join.
set -euo pipefail

AUTH_KEY="${TAILSCALE_AUTH_KEY:-${TS_AUTHKEY:-${TAILSCALE_AUTHKEY:-}}}"
HOSTNAME_VALUE="${FLEET_HOSTNAME:-${TS_HOSTNAME:-cursor-model-sites-preview}}"
TS_SOCKET="${TS_SOCKET:-/run/tailscale/tailscaled.sock}"
TS_STATE="${TS_STATE:-/var/lib/tailscale/tailscaled.state}"

log() { printf '[install_cursor_cloud_tailscale] %s\n' "$*"; }

if [[ -z "$AUTH_KEY" && -f /run/secrets/tailscale-auth-key ]]; then
  AUTH_KEY="$(tr -d '[:space:]' < /run/secrets/tailscale-auth-key)"
fi

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

if ! command -v tailscale >/dev/null 2>&1; then
  log "Installing Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
fi

TAILSCALED_ARGS=(--state="$TS_STATE" --socket="$TS_SOCKET")
if [[ ! -c /dev/net/tun ]]; then
  TAILSCALED_ARGS+=(--tun=userspace-networking)
fi

mkdir -p "$(dirname "$TS_SOCKET")" "$(dirname "$TS_STATE")"

if pgrep -x tailscaled >/dev/null 2>&1 && ! tailscale --socket="$TS_SOCKET" status >/dev/null 2>&1; then
  log "Stopping stale tailscaled (socket mismatch)"
  pkill -x tailscaled 2>/dev/null || true
  sleep 1
fi

if ! pgrep -x tailscaled >/dev/null 2>&1; then
  log "Starting tailscaled (userspace=${TAILSCALED_ARGS[*]})"
  nohup tailscaled "${TAILSCALED_ARGS[@]}" >/var/log/tailscaled.log 2>&1 &
  for _ in $(seq 1 30); do
    tailscale --socket="$TS_SOCKET" status >/dev/null 2>&1 && break
    sleep 1
  done
fi

if tailscale --socket="$TS_SOCKET" status 2>/dev/null | grep -qE '^100\.'; then
  log "Already connected"
  tailscale --socket="$TS_SOCKET" status
  exit 0
fi

if [[ -z "$AUTH_KEY" ]]; then
  log "ERROR: TAILSCALE_AUTH_KEY required for non-interactive join" >&2
  exit 1
fi

log "Joining tailnet as ${HOSTNAME_VALUE}"
tailscale --socket="$TS_SOCKET" up \
  --reset \
  --ssh \
  --hostname="$HOSTNAME_VALUE" \
  --accept-routes=false \
  --auth-key="$AUTH_KEY" \
  --timeout=60s

tailscale --socket="$TS_SOCKET" status
log "IPv4: $(tailscale --socket="$TS_SOCKET" ip -4)"
