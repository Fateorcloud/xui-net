#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$PROJECT_DIR/scripts/lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  sudo bash deploy.sh xui [--yes]
  sudo bash deploy.sh nat-proxy [--yes]
  sudo bash deploy.sh network [--yes]

Commands:
  xui       Install or repair the isolated xui side stack.
  nat-proxy Install or repair the optional NAT egress proxy.
  network   Run xui and nat-proxy setup in sequence.
USAGE
}

COMMAND="${1:-help}"
if [[ "${2:-}" == "--yes" || "${1:-}" == "--yes" ]]; then
  export ASSUME_YES=1
fi

case "$COMMAND" in
  xui)
    require_root
    load_env
    confirm "Set up isolated xui component?"
    bash "$PROJECT_DIR/scripts/35_setup_xui.sh"
    ;;
  nat-proxy)
    require_root
    load_env
    confirm "Set up isolated NAT egress proxy?"
    bash "$PROJECT_DIR/scripts/50_setup_nat_proxy.sh"
    ;;
  network)
    require_root
    load_env
    confirm "Set up isolated xui and NAT network components?"
    bash "$PROJECT_DIR/scripts/35_setup_xui.sh"
    bash "$PROJECT_DIR/scripts/50_setup_nat_proxy.sh"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
