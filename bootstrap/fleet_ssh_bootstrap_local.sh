#!/usr/bin/env bash
# Evergreen fleet — enable Tailscale SSH and verify fleet SSH readiness.
set -euo pipefail

TS_SOCKET="${TS_SOCKET:-/var/run/tailscale/tailscaled.sock}"
TS_HOSTNAME="${FLEET_HOSTNAME:-${TS_HOSTNAME:-cursor-model-sites-preview}}"
TS_CMD=(tailscale --socket="$TS_SOCKET")

log() { printf '[fleet_ssh_bootstrap_local] %s\n' "$*"; }

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

if ! command -v tailscale >/dev/null 2>&1; then
  log "Tailscale not installed; run bootstrap/install_cursor_cloud_tailscale.sh first"
  exit 1
fi

log "Enabling Tailscale SSH (RunSSH)"
"${TS_CMD[@]}" set --ssh --hostname="$TS_HOSTNAME"

log "Verifying RunSSH preference"
if ! "${TS_CMD[@]}" debug prefs | grep -q '"RunSSH":true'; then
  log "ERROR: RunSSH is not true"
  exit 1
fi

if command -v ss >/dev/null 2>&1; then
  if ss -tlnp | grep -q ':22 '; then
    log "OpenSSH listening on :22 (Tailscale SSH also enabled)"
  else
    log "No listener on :22 — Tailscale SSH-only mode"
  fi
fi

TS_IP="$("${TS_CMD[@]}" ip -4)"
if [[ -z "$TS_IP" ]]; then
  log "ERROR: no Tailscale IPv4 assigned (node not logged in?)"
  exit 1
fi

log "Fleet SSH ready on ${TS_HOSTNAME} (${TS_IP})"
