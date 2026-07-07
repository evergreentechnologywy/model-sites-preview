#!/usr/bin/env bash
set -euo pipefail

# Evergreen fleet: install Tailscale and join the tailnet on cloud agents.
# Requires TAILSCALE_AUTH_KEY or TS_AUTHKEY in the environment.

HOSTNAME_VALUE="${FLEET_HOSTNAME:-${CURSOR_CONVERSATION_ID:-$(hostname -s)}}"
AUTH_KEY="${TAILSCALE_AUTH_KEY:-${TS_AUTHKEY:-}}"

if [[ -z "$AUTH_KEY" && -f /run/secrets/tailscale-auth-key ]]; then
  AUTH_KEY="$(tr -d '[:space:]' < /run/secrets/tailscale-auth-key)"
fi

echo "[start_tailscale_cloud] hostname=${HOSTNAME_VALUE}"

if ! command -v tailscale >/dev/null 2>&1; then
  echo "[start_tailscale_cloud] installing tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
fi

TS_SOCKET="${TS_SOCKET:-/run/tailscale/tailscaled.sock}"
TS_STATE="${TS_STATE:-/var/lib/tailscale/tailscaled.state}"
TAILSCALED_ARGS=(--state="$TS_STATE" --socket="$TS_SOCKET")

# Cloud/container environments may lack /dev/net/tun.
if [[ ! -c /dev/net/tun ]]; then
  TAILSCALED_ARGS+=(--tun=userspace-networking)
  if command -v systemctl >/dev/null 2>&1; then
    sudo mkdir -p /etc/systemd/system/tailscaled.service.d
    sudo tee /etc/systemd/system/tailscaled.service.d/userspace-networking.conf >/dev/null <<'EOF'
[Service]
Environment=TS_USERSPACE_NETWORKING=true
EOF
    sudo systemctl daemon-reload
  fi
fi

if command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; then
  sudo systemctl enable --now tailscaled
else
  sudo mkdir -p /run/tailscale /var/lib/tailscale
  if ! sudo tailscale --socket="$TS_SOCKET" status >/dev/null 2>&1; then
    sudo pkill -x tailscaled 2>/dev/null || true
    sleep 1
    sudo tailscaled "${TAILSCALED_ARGS[@]}" &
    for _ in $(seq 1 30); do
      sudo tailscale --socket="$TS_SOCKET" status >/dev/null 2>&1 && break
      sleep 1
    done
  fi
fi

if sudo tailscale --socket="$TS_SOCKET" status >/dev/null 2>&1; then
  echo "[start_tailscale_cloud] already connected"
else
  if [[ -z "$AUTH_KEY" ]]; then
    echo "[start_tailscale_cloud] ERROR: TAILSCALE_AUTH_KEY or TS_AUTHKEY required for non-interactive cloud bootstrap" >&2
    exit 1
  fi
  echo "[start_tailscale_cloud] joining tailnet"
  sudo tailscale --socket="$TS_SOCKET" up --ssh --hostname="$HOSTNAME_VALUE" --accept-routes --auth-key="$AUTH_KEY"
fi

sudo tailscale --socket="$TS_SOCKET" status
echo "[start_tailscale_cloud] done"
