#!/usr/bin/env bash
# Evergreen fleet — fallback session rejoin for Cursor Cloud agents.
set -euo pipefail

AUTH_KEY="${TAILSCALE_AUTH_KEY:-${TS_AUTHKEY:-${TAILSCALE_AUTHKEY:-}}}"
HOSTNAME_VALUE="${FLEET_HOSTNAME:-${TS_HOSTNAME:-cursor-model-sites-preview}}"
TS_SOCKET="${TS_SOCKET:-/run/tailscale/tailscaled.sock}"

log() { printf '[cursor_cloud_session_tailscale] %s\n' "$*"; }

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

if ! command -v tailscale >/dev/null 2>&1; then
  log "Tailscale missing; run bootstrap/install_cursor_cloud_tailscale.sh"
  exit 1
fi

if ! pgrep -x tailscaled >/dev/null 2>&1; then
  log "tailscaled not running; delegating to install script"
  exec bash "$(dirname "$0")/install_cursor_cloud_tailscale.sh"
fi

if tailscale --socket="$TS_SOCKET" status 2>/dev/null | grep -qE '^100\.'; then
  log "Session already connected"
  tailscale --socket="$TS_SOCKET" status
  exit 0
fi

if [[ -z "$AUTH_KEY" ]]; then
  log "ERROR: TAILSCALE_AUTH_KEY required to rejoin session" >&2
  exit 1
fi

log "Rejoining tailnet as ${HOSTNAME_VALUE}"
tailscale --socket="$TS_SOCKET" up \
  --reset \
  --ssh \
  --hostname="$HOSTNAME_VALUE" \
  --accept-routes=false \
  --auth-key="$AUTH_KEY" \
  --timeout=60s

tailscale --socket="$TS_SOCKET" status
log "IPv4: $(tailscale --socket="$TS_SOCKET" ip -4)"
