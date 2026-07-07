#!/usr/bin/env bash
# Evergreen fleet — Tailscale userspace bootstrap for Cursor Cloud Agent VMs.
# See: https://cursor.com/docs/cloud-agent/setup#running-tailscale
set -euo pipefail

TS_AUTHKEY="${TS_AUTHKEY:-${TAILSCALE_AUTHKEY:-${TAILSCALE_AUTH_KEY:-}}}"
TS_HOSTNAME="${TS_HOSTNAME:-${FLEET_HOSTNAME:-cursor-model-sites-preview}}"
TS_STATE_DIR="${TS_STATE_DIR:-/var/lib/tailscale}"
TS_SOCKET="${TS_SOCKET:-/var/run/tailscale/tailscaled.sock}"
TS_USERSPACE_PORT_HTTP="${TS_USERSPACE_PORT_HTTP:-1054}"
TS_USERSPACE_PORT_SOCKS="${TS_USERSPACE_PORT_SOCKS:-1055}"
TS_CMD=(tailscale --socket="$TS_SOCKET")

log() { printf '[start_tailscale_cloud] %s\n' "$*"; }

read_authkey_file() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  local key
  key="$(tr -d '[:space:]' <"$path")"
  [[ -n "$key" ]] || return 1
  TS_AUTHKEY="$key"
  return 0
}

if [[ -z "$TS_AUTHKEY" ]]; then
  for candidate in \
    /run/secrets/TS_AUTHKEY \
    /run/secrets/ts_authkey \
    /etc/evergreen/ts_authkey \
    "${HOME}/.evergreen/ts_authkey" \
    "${HOME}/.config/evergreen/ts_authkey"; do
    read_authkey_file "$candidate" && break
  done
fi
export TS_AUTHKEY

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

if ! command -v tailscale >/dev/null 2>&1; then
  log "Installing Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
fi

mkdir -p "$(dirname "$TS_SOCKET")" "$TS_STATE_DIR"

if pgrep -af 'tailscaled.*userspace-networking' >/dev/null 2>&1 \
  && "${TS_CMD[@]}" status >/dev/null 2>&1; then
  log "Userspace tailscaled already running"
else
  if pgrep -x tailscaled >/dev/null 2>&1; then
    log "Stopping existing tailscaled to start userspace instance"
    systemctl stop tailscaled 2>/dev/null || true
    pkill -x tailscaled 2>/dev/null || true
    sleep 1
  fi
  log "Starting tailscaled (userspace networking)"
  nohup tailscaled \
    --state="$TS_STATE_DIR/tailscaled.state" \
    --socket="$TS_SOCKET" \
    --tun=userspace-networking \
    --outbound-http-proxy-listen="localhost:${TS_USERSPACE_PORT_HTTP}" \
    --socks5-server="localhost:${TS_USERSPACE_PORT_SOCKS}" \
    >/var/log/tailscaled.log 2>&1 &
  ready=false
  for _ in $(seq 1 30); do
    if "${TS_CMD[@]}" status >/dev/null 2>&1; then
      ready=true
      break
    fi
    sleep 1
  done
  if [[ "$ready" != true ]]; then
    log "tailscaled did not become ready within 30s; see /var/log/tailscaled.log"
    exit 1
  fi
fi

export ALL_PROXY="socks5h://localhost:${TS_USERSPACE_PORT_SOCKS}/"
export HTTP_PROXY="http://localhost:${TS_USERSPACE_PORT_HTTP}/"
export HTTPS_PROXY="http://localhost:${TS_USERSPACE_PORT_HTTP}/"

UP_ARGS=(up --ssh --hostname="$TS_HOSTNAME" --accept-routes=false --reset)
if [[ -n "$TS_AUTHKEY" ]]; then
  UP_ARGS+=(--auth-key="$TS_AUTHKEY")
  UP_ARGS+=(--timeout=60s)
else
  UP_ARGS+=(--timeout=120s)
fi

log "Joining tailnet as ${TS_HOSTNAME}"
if ! "${TS_CMD[@]}" "${UP_ARGS[@]}"; then
  log "tailscale up did not complete; check TS_AUTHKEY secret or login URL from: ${TS_CMD[*]} status"
  "${TS_CMD[@]}" status || true
  exit 1
fi

log "Tailscale IPv4: $("${TS_CMD[@]}" ip -4)"
