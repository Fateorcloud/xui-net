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

# Install the privoxy HTTP->SOCKS block idempotently: drop any previously managed
# block (matched by the markers), then append the freshly rendered one. This lets
# NAT_HTTP_LISTEN change (e.g. 0.0.0.0:7890 so local docker containers can use it)
# without leaving duplicate/conflicting listen-address lines on re-run.
privoxy_config="/etc/privoxy/config"
sed -i '/^# >>> xui network deploy local HTTP proxy >>>/,/^# <<< xui network deploy local HTTP proxy <<</d' "$privoxy_config"
privoxy_block="$(sed \
  -e "s#__NAT_HTTP_LISTEN__#${NAT_HTTP_LISTEN:-127.0.0.1:7890}#g" \
  -e "s#__NAT_SOCKS_LISTEN__#${NAT_SOCKS_LISTEN:-127.0.0.1:10808}#g" \
  "$PROJECT_ROOT/templates/privoxy-local-proxy.conf")"
printf '\n%s\n' "$privoxy_block" >> "$privoxy_config"

# If the HTTP proxy is exposed beyond loopback, allow only the given CIDR through ufw
# (e.g. a docker bridge subnet) so local containers can reach it but the internet cannot.
nat_http_listen="${NAT_HTTP_LISTEN:-127.0.0.1:7890}"
if [[ "${nat_http_listen%%:*}" != "127.0.0.1" && -n "${NAT_HTTP_ALLOW_CIDR:-}" ]] && command -v ufw >/dev/null 2>&1; then
  ufw allow from "$NAT_HTTP_ALLOW_CIDR" to any port "${nat_http_listen##*:}" proto tcp >/dev/null 2>&1 || true
  log "ufw: allowed ${NAT_HTTP_ALLOW_CIDR} -> ${nat_http_listen##*:}/tcp"
fi

systemctl daemon-reload
systemctl enable --now nat-socks
systemctl restart privoxy

log "Optional NAT proxy setup complete"
