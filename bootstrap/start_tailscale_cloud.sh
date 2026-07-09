#!/usr/bin/env bash
# Evergreen fleet — Tailscale userspace bootstrap for Cursor Cloud Agent VMs.
# See: https://cursor.com/docs/cloud-agent/setup#running-tailscale
set -euo pipefail

export TS_SOCKET="${TS_SOCKET:-/var/run/tailscale/tailscaled.sock}"
export TS_USERSPACE_PORT_HTTP="${TS_USERSPACE_PORT_HTTP:-1054}"
export TS_USERSPACE_PORT_SOCKS="${TS_USERSPACE_PORT_SOCKS:-1055}"

AUTH_KEY="${TAILSCALE_AUTH_KEY:-${TS_AUTHKEY:-${TAILSCALE_AUTHKEY:-}}}"
if [[ -n "$AUTH_KEY" ]]; then
  export TAILSCALE_AUTH_KEY="$AUTH_KEY"
fi

if [[ -n "${FLEET_HOSTNAME:-}" ]]; then
  export FLEET_HOSTNAME
elif [[ -n "${TS_HOSTNAME:-}" ]]; then
  export FLEET_HOSTNAME="$TS_HOSTNAME"
fi

exec bash "$(dirname "$0")/install_cursor_cloud_tailscale.sh"
