#!/usr/bin/env bash
# uninstall.sh — remove everything install.sh set up (launcher symlink, installed
# files) plus all Docker state (containers, image, volumes) for this tool, so a
# subsequent ./install.sh starts completely fresh with no cached image layers,
# containers, or credentials left behind.
set -euo pipefail

IMAGE_NAME="${AI_AGENT_VM_IMAGE:-ai-agent-vm:latest}"
AUTH_VOLUME="${AI_AGENT_VM_AUTH_VOLUME:-ai-agent-vm-auth}"
CONFIG_VOLUME="${AI_AGENT_VM_CONFIG_VOLUME:-ai-agent-vm-config}"
INSTALL_DIR="$HOME/.local/share/ai-agent-vm"
LAUNCHER_LINK="$HOME/.local/bin/ai-agent-vm"

YES=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes) YES=1 ;;
    -h|--help)
      cat <<EOF
Usage: ./uninstall.sh [-y|--yes]

Removes:
  - Docker containers labelled ai-agent-vm=1 (one per project)
  - Docker image '$IMAGE_NAME'
  - Docker volumes '$AUTH_VOLUME' and '$CONFIG_VOLUME' (auth/credentials)
  - Launcher symlink '$LAUNCHER_LINK'
  - Installed files under '$INSTALL_DIR'

-y/--yes skips the confirmation prompt.
EOF
      exit 0
      ;;
  esac
done

if [[ "$YES" -ne 1 ]]; then
  echo "This will remove all ai-agent-vm containers, the '$IMAGE_NAME' image,"
  echo "the '$AUTH_VOLUME' / '$CONFIG_VOLUME' volumes (including saved login credentials),"
  echo "the launcher symlink, and installed files under '$INSTALL_DIR'."
  read -r -p "Continue? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  echo "uninstall: removing ai-agent-vm containers ..."
  ids="$(docker ps -aq --filter "label=ai-agent-vm=1")"
  if [[ -n "$ids" ]]; then
    # shellcheck disable=SC2086
    docker rm -f $ids >/dev/null
  fi

  echo "uninstall: removing Docker image '$IMAGE_NAME' ..."
  docker rmi -f "$IMAGE_NAME" >/dev/null 2>&1 || true

  echo "uninstall: removing Docker volumes ..."
  docker volume rm "$AUTH_VOLUME" >/dev/null 2>&1 || true
  docker volume rm "$CONFIG_VOLUME" >/dev/null 2>&1 || true
else
  echo "uninstall: docker not found or daemon not reachable — skipping container/image/volume cleanup" >&2
fi

echo "uninstall: removing launcher symlink ($LAUNCHER_LINK) ..."
rm -f "$LAUNCHER_LINK"

echo "uninstall: removing installed files ($INSTALL_DIR) ..."
rm -rf "$INSTALL_DIR"

echo "uninstall: done. Run ./install.sh for a completely fresh install."
