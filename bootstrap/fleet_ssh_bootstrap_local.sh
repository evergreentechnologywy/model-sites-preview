#!/usr/bin/env bash
set -euo pipefail

# Evergreen fleet: enable Tailscale SSH (RunSSH) on this node.

echo "[fleet_ssh_bootstrap_local] enabling Tailscale SSH"

if ! command -v tailscale >/dev/null 2>&1; then
  echo "tailscale not installed; run bootstrap/start_tailscale_cloud.sh first" >&2
  exit 1
fi

sudo tailscale set --ssh
sudo tailscale debug prefs | grep -i RunSSH || true

echo "[fleet_ssh_bootstrap_local] SSH listen check"
if ss -tlnp 2>/dev/null | grep -q ':22'; then
  echo "[fleet_ssh_bootstrap_local] port 22 listening (openssh or tailscale ssh)"
else
  echo "[fleet_ssh_bootstrap_local] port 22 not bound — Tailscale SSH-only (expected on cloud agents)"
fi

sudo tailscale ip -4 || true
echo "[fleet_ssh_bootstrap_local] done"
