# claude-vm

Run [Claude Code](https://claude.ai/code) inside a per-project Docker container on macOS (Apple Silicon). Your host filesystem stays isolated — only the current working directory is mounted into the container.

## Why

- **No credential sprawl** — SSH keys, `~/.aws`, dotfiles, and other host secrets are never visible inside the container.
- **One container per project** — named by hashing the project path. First run creates it; subsequent runs `docker exec` in (~50 ms).
- **Log in once** — a Docker named volume (`claude-vm-auth`) holds credentials and global config. Every project container shares it automatically.
- **tmux-friendly** — each `claude-vm` call spawns a fresh `claude` process, so different panes in the same project get independent sessions sharing one container.

## Prerequisites

- macOS (Apple Silicon recommended; amd64 works too)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) or [Colima](https://github.com/abiosoft/colima) running

## Install

```bash
git clone https://github.com/your-username/claude-vm.git
cd claude-vm
chmod +x install.sh
./install.sh
```

`install.sh` copies the three files (`claude-vm`, `Dockerfile`, `entrypoint.sh`) to `~/.local/share/claude-vm/`, symlinks the launcher to `~/.local/bin/claude-vm`, and builds the Docker image.

Make sure `~/.local/bin` is on your `PATH`:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### First-time login

```bash
claude-vm login
```

This opens a browser for the Anthropic OAuth flow. Your token is saved to the `claude-vm-auth` Docker volume — you never need to log in again, even across projects.

## Usage

```bash
cd ~/code/my-project
claude-vm                  # start (or reuse) the container, launch Claude Code
claude-vm --resume         # resume the last Claude session in this project
claude-vm shell            # open a bash shell inside the container
claude-vm ps               # list all project containers
claude-vm stop             # stop this project's container
claude-vm rm               # remove this project's container
claude-vm rebuild          # rebuild the Docker image (no cache)
```

All unrecognised arguments are forwarded directly to `claude`, so any flag that Claude Code accepts works with `claude-vm` too.

### tmux integration

Replace your existing Claude keybind with `claude-vm` in `~/.tmux.conf`:

```tmux
bind -r y run-shell '\
  SESSION="claude-$(echo #{pane_current_path} | md5sum | cut -c1-8)"; \
  tmux has-session -t "$SESSION" 2>/dev/null || \
  tmux new-session -d -s "$SESSION" -c "#{pane_current_path}" "claude-vm"; \
  tmux display-popup -w80% -h80% -E -S "bg=#141210" "tmux attach-session -t $SESSION"'
```

Multiple panes in the same project directory share one container but each get their own `claude` process.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `CLAUDE_VM_IMAGE` | `claude-vm:latest` | Docker image to use |
| `CLAUDE_VM_AUTH_VOLUME` | `claude-vm-auth` | Named volume for shared auth/config |
| `CLAUDE_VM_OAUTH_PORT` | `54545` | OAuth callback port (override if Anthropic changes it) |

## Performance

- **Image build**: one-time, ~30 s.
- **First `claude-vm` in a new directory**: ~1 s (container create + start).
- **Every subsequent call**: ~50 ms (`docker exec`).
- **Idle memory**: a single `sleep infinity` process — a few MB per container.

## How auth sharing works

Claude Code stores state in two places:

1. `~/.claude/` — credentials, settings, plugins, etc.
2. `~/.claude.json` — account/onboarding state (a file at `$HOME`, not inside `.claude/`)

The `claude-vm-auth` volume is mounted at `/home/node/.claude` in every container. `entrypoint.sh` symlinks `~/.claude.json` into that volume so account state persists alongside credentials. Credentials and global config are therefore shared across all projects.

**Isolated per container** (container-local, not in the shared volume): `projects/`, `sessions/`, `history.jsonl`, and other ephemeral state. Removing a project container with `claude-vm rm` only deletes that project's history — credentials and global config are untouched.

## Troubleshooting

**"Claude configuration file not found" / onboarding screen appears**

You're running an old image without `entrypoint.sh`. Rebuild and remove stale containers:

```bash
claude-vm rebuild
docker ps -aq --filter label=claude-vm=1 | xargs docker rm -f
```

**Still prompted to log in after a fresh install**

A stale OAuth env var on the host shell silently overrides the credentials file:

```bash
env | grep -iE 'CLAUDE_CODE_OAUTH_TOKEN|ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN'
```

Unset any matches in your shell rc.

> **macOS note:** Host Claude Code stores its OAuth token in the Keychain, not in `~/.claude/.credentials.json`. Seeding the volume from host `~/.claude` does **not** copy the token — run `claude-vm login` once instead.

**Inspect the auth volume**

```bash
docker run --rm --user 0:0 -v claude-vm-auth:/data alpine ls -la /data
```

**Reset auth entirely**

```bash
docker volume rm claude-vm-auth
claude-vm login
```

**Nuke everything**

```bash
docker ps -aq --filter label=claude-vm=1 | xargs -r docker rm -f
docker volume rm claude-vm-auth
docker rmi claude-vm:latest
```

## Notes

- No git inside the container by design. Run git on the host — the working directory is mounted read/write at `/workspace`.
- `claude-vm login` forwards port 54545 from `127.0.0.1` to the container for the OAuth redirect. Override the port with `CLAUDE_VM_OAUTH_PORT` if needed.
