#!/bin/sh
# Runs on every container start AND via `docker exec` (no — exec skips ENTRYPOINT).
# That's fine: we only need this to run once at container creation time, which
# matches ENTRYPOINT behavior. For exec'd sessions, the symlink is already in place.
set -e

VOLUME_ROOT="$HOME/.claude"
PERSISTED_CONFIG="$VOLUME_ROOT/_home_claude.json"
HOME_CONFIG="$HOME/.claude.json"

# Ensure the volume mount actually exists (it should; launcher always mounts it).
if [ -d "$VOLUME_ROOT" ]; then
  # If ~/.claude.json exists and is a real file (not our symlink), migrate it into the volume.
  if [ -f "$HOME_CONFIG" ] && [ ! -L "$HOME_CONFIG" ]; then
    # Only move if the persisted one doesn't already exist (don't clobber shared state).
    if [ ! -e "$PERSISTED_CONFIG" ]; then
      mv "$HOME_CONFIG" "$PERSISTED_CONFIG"
    else
      rm -f "$HOME_CONFIG"
    fi
  fi

  # If nothing persisted yet, try restoring from Claude's own backup dir.
  if [ ! -e "$PERSISTED_CONFIG" ]; then
    latest_backup="$(ls -1t "$VOLUME_ROOT"/backups/.claude.json.backup.* 2>/dev/null | head -n1 || true)"
    if [ -n "$latest_backup" ] && [ -f "$latest_backup" ]; then
      cp "$latest_backup" "$PERSISTED_CONFIG"
    fi
  fi

  # Remove any stale symlink, then (re)create it pointing at the persisted file.
  # If the persisted file still doesn't exist, create an empty JSON object so Claude
  # Code treats it as a configured install rather than running onboarding.
  if [ ! -e "$PERSISTED_CONFIG" ]; then
    printf '{}' > "$PERSISTED_CONFIG"
  fi

  rm -f "$HOME_CONFIG"
  ln -s "$PERSISTED_CONFIG" "$HOME_CONFIG"

  # ── Per-container isolation ──────────────────────────────────────────
  # These dirs hold project-specific history, sessions, and ephemeral state.
  # We redirect them to container-local storage so they don't leak between
  # project containers via the shared auth volume.
  #
  # Container-local storage lives at ~/.claude-local/ (inside the container's
  # own filesystem, NOT the volume). It survives for the container's lifetime
  # — which matches one-container-per-project semantics.
  LOCAL_ROOT="$HOME/.claude-local"
  mkdir -p "$LOCAL_ROOT"

  for dir_name in projects sessions session-env shell-snapshots plans tasks file-history todos debug paste-cache; do
    local_dir="$LOCAL_ROOT/$dir_name"
    volume_dir="$VOLUME_ROOT/$dir_name"

    mkdir -p "$local_dir"

    # If the volume has existing data for this dir (from before isolation was added),
    # leave it in the volume but don't use it — the symlink points to the local copy.
    # Remove any real dir or stale symlink at the volume path, replace with symlink.
    if [ -L "$volume_dir" ]; then
      rm -f "$volume_dir"
    elif [ -d "$volume_dir" ]; then
      # First time after upgrade: move existing volume data into local so current
      # container doesn't lose its in-progress work, but future containers start clean.
      cp -a "$volume_dir/." "$local_dir/" 2>/dev/null || true
      rm -rf "$volume_dir"
    fi
    ln -s "$local_dir" "$volume_dir"
  done

  # history.jsonl — same treatment but it's a file, not a dir.
  local_history="$LOCAL_ROOT/history.jsonl"
  volume_history="$VOLUME_ROOT/history.jsonl"
  if [ ! -e "$local_history" ]; then
    # Seed from volume if it existed before isolation.
    if [ -f "$volume_history" ] && [ ! -L "$volume_history" ]; then
      cp "$volume_history" "$local_history"
    else
      touch "$local_history"
    fi
  fi
  if [ -f "$volume_history" ] && [ ! -L "$volume_history" ]; then
    rm -f "$volume_history"
  fi
  rm -f "$volume_history"
  ln -s "$local_history" "$volume_history"
fi

exec "$@"
