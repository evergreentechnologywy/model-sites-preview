#!/usr/bin/env bash
# Evergreen fleet — fallback session rejoin for Cursor Cloud agents.
set -euo pipefail

AUTH_KEY="${TAILSCALE_AUTH_KEY:-${TS_AUTHKEY:-${TAILSCALE_AUTHKEY:-}}}"
HOSTNAME_VALUE="${FLEET_HOSTNAME:-${TS_HOSTNAME:-cursor-model-sites-preview}}"
TS_SOCKET="${TS_SOCKET:-/var/run/tailscale/tailscaled.sock}"

log() { printf '[cursor_cloud_session_tailscale] %s\n' "$*"; }

read_authkey_file() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  local key
  key="$(tr -d '[:space:]' <"$path")"
  [[ -n "$key" ]] || return 1
  AUTH_KEY="$key"
  return 0
}

if [[ -z "$AUTH_KEY" ]]; then
  for candidate in \
    /run/secrets/tailscale-auth-key \
    /run/secrets/TS_AUTHKEY \
    /run/secrets/ts_authkey \
    /etc/evergreen/ts_authkey \
    "${HOME}/.evergreen/ts_authkey" \
    "${HOME}/.config/evergreen/ts_authkey"; do
    read_authkey_file "$candidate" && break
  done
fi

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

if [[ -n "$(tailscale --socket="$TS_SOCKET" ip -4 2>/dev/null | tr -d '[:space:]')" ]]; then
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
