#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
load_env

if [[ "${ENABLE_NAT_PROXY:-false}" != "true" ]]; then
  log "ENABLE_NAT_PROXY is not true; skipping optional NAT proxy setup"
  exit 0
fi

require_env_present NAT_SSH_HOST
require_env_present NAT_SSH_PORT
require_env_present NAT_SSH_USER
require_env_present NAT_SSH_KEY_PATH

if [[ ! -f "$NAT_SSH_KEY_PATH" ]]; then
  warn "NAT SSH key not found: $NAT_SSH_KEY_PATH"
  warn "Generate or copy it manually, then authorize ${NAT_SSH_KEY_PATH}.pub on $NAT_SSH_USER@$NAT_SSH_HOST"
  die "NAT SSH key missing"
fi

apt install -y autossh privoxy

render_nat_socks_service "/etc/systemd/system/nat-socks.service"

# Install the privoxy HTTP->SOCKS block idempotently: drop any previously managed block
# (matched by the markers), then append a freshly built one. NAT_HTTP_LISTEN may list
# multiple space/comma-separated addresses -> one listen-address line each. Prefer binding
# internal addresses (127.0.0.1 plus the docker gateway, e.g.
# "127.0.0.1:7890 172.19.0.1:7890") over 0.0.0.0: that keeps the proxy off the public
# interface entirely, so security does not rely solely on the firewall.
privoxy_config="/etc/privoxy/config"
sed -i '/^# >>> xui network deploy local HTTP proxy >>>/,/^# <<< xui network deploy local HTTP proxy <<</d' "$privoxy_config"
listen_addrs="$(printf '%s' "${NAT_HTTP_LISTEN:-127.0.0.1:7890}" | tr ',' ' ')"
{
  printf '\n# >>> xui network deploy local HTTP proxy >>>\n'
  for addr in $listen_addrs; do
    printf 'listen-address %s\n' "$addr"
  done
  printf 'forward-socks5t / %s .\n' "${NAT_SOCKS_LISTEN:-127.0.0.1:10808}"
  printf '# <<< xui network deploy local HTTP proxy <<<\n'
} >> "$privoxy_config"

# Boot resilience: a docker-gateway listen address (e.g. 172.19.0.1) only exists after
# Docker has created the network; start privoxy after docker and retry on failure so a
# reboot self-heals instead of leaving privoxy down.
install -d /etc/systemd/system/privoxy.service.d
cat > /etc/systemd/system/privoxy.service.d/override.conf <<'UNIT'
[Unit]
After=docker.service
Wants=docker.service
StartLimitIntervalSec=0

[Service]
Restart=on-failure
RestartSec=5
UNIT

# Open ufw for each non-loopback listen address so local docker containers can reach it
# (the internet still cannot: those are private, non-routable docker IPs).
if [[ -n "${NAT_HTTP_ALLOW_CIDR:-}" ]] && command -v ufw >/dev/null 2>&1; then
  for addr in $listen_addrs; do
    if [[ "${addr%%:*}" != "127.0.0.1" ]]; then
      ufw allow from "$NAT_HTTP_ALLOW_CIDR" to any port "${addr##*:}" proto tcp >/dev/null 2>&1 || true
      log "ufw: allowed ${NAT_HTTP_ALLOW_CIDR} -> ${addr##*:}/tcp"
    fi
  done
fi

systemctl daemon-reload
systemctl enable --now nat-socks
systemctl restart privoxy

log "Optional NAT proxy setup complete"
