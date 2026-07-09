#!/usr/bin/env bash
# Evergreen fleet — primary Cursor Cloud Tailscale install + join.
set -euo pipefail

AUTH_KEY="${TAILSCALE_AUTH_KEY:-${TS_AUTHKEY:-${TAILSCALE_AUTHKEY:-}}}"
HOSTNAME_VALUE="${FLEET_HOSTNAME:-${TS_HOSTNAME:-cursor-model-sites-preview}}"
TS_SOCKET="${TS_SOCKET:-/var/run/tailscale/tailscaled.sock}"
TS_STATE="${TS_STATE:-/var/lib/tailscale/tailscaled.state}"
TS_USERSPACE_PORT_HTTP="${TS_USERSPACE_PORT_HTTP:-1054}"
TS_USERSPACE_PORT_SOCKS="${TS_USERSPACE_PORT_SOCKS:-1055}"
USERSPACE=false
[[ ! -c /dev/net/tun ]] && USERSPACE=true

log() { printf '[install_cursor_cloud_tailscale] %s\n' "$*"; }

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

proxy_ports_listening() {
  if command -v ss >/dev/null 2>&1; then
    ss -tln 2>/dev/null | grep -q ":${TS_USERSPACE_PORT_HTTP} " &&
      ss -tln 2>/dev/null | grep -q ":${TS_USERSPACE_PORT_SOCKS} "
    return $?
  fi
  pgrep -af tailscaled 2>/dev/null |
    grep -q "outbound-http-proxy-listen=localhost:${TS_USERSPACE_PORT_HTTP}"
}

export_userspace_proxy_env() {
  if ! $USERSPACE || ! proxy_ports_listening; then
    return 0
  fi
  export ALL_PROXY="socks5h://localhost:${TS_USERSPACE_PORT_SOCKS}/"
  export HTTP_PROXY="http://localhost:${TS_USERSPACE_PORT_HTTP}/"
  export HTTPS_PROXY="http://localhost:${TS_USERSPACE_PORT_HTTP}/"
}

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

if ! command -v tailscale >/dev/null 2>&1; then
  log "Installing Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
fi

TAILSCALED_ARGS=(--state="$TS_STATE" --socket="$TS_SOCKET")
if $USERSPACE; then
  TAILSCALED_ARGS+=(--tun=userspace-networking)
  TAILSCALED_ARGS+=(--outbound-http-proxy-listen="localhost:${TS_USERSPACE_PORT_HTTP}")
  TAILSCALED_ARGS+=(--socks5-server="localhost:${TS_USERSPACE_PORT_SOCKS}")
fi

mkdir -p "$(dirname "$TS_SOCKET")" "$(dirname "$TS_STATE")"

if pgrep -x tailscaled >/dev/null 2>&1 && ! tailscale --socket="$TS_SOCKET" status >/dev/null 2>&1; then
  log "Stopping stale tailscaled (socket mismatch)"
  pkill -x tailscaled 2>/dev/null || true
  sleep 1
elif $USERSPACE && pgrep -x tailscaled >/dev/null 2>&1 &&
  tailscale --socket="$TS_SOCKET" status >/dev/null 2>&1 && ! proxy_ports_listening; then
  log "Restarting tailscaled to enable userspace proxy listeners"
  pkill -x tailscaled 2>/dev/null || true
  sleep 1
fi

if ! pgrep -x tailscaled >/dev/null 2>&1; then
  log "Starting tailscaled (userspace=${USERSPACE})"
  nohup tailscaled "${TAILSCALED_ARGS[@]}" >/var/log/tailscaled.log 2>&1 &
  for _ in $(seq 1 30); do
    tailscale --socket="$TS_SOCKET" status >/dev/null 2>&1 && break
    sleep 1
  done
fi

if [[ -n "$(tailscale --socket="$TS_SOCKET" ip -4 2>/dev/null | tr -d '[:space:]')" ]]; then
  log "Already connected"
  export_userspace_proxy_env
  tailscale --socket="$TS_SOCKET" status
  exit 0
fi

if [[ -z "$AUTH_KEY" ]]; then
  log "ERROR: TAILSCALE_AUTH_KEY required for non-interactive join" >&2
  exit 1
fi

export_userspace_proxy_env

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
