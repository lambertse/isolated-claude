# isolated-claude

Run an AI coding agent CLI inside a per-project Docker container on macOS (Apple Silicon). Your host filesystem stays isolated — only the current working directory is mounted into the container.

## Why

- **No credential sprawl** — SSH keys, `~/.aws`, dotfiles, and other host secrets are never visible inside the container.
- **One container per project** — named by hashing the project path. First run creates it; subsequent runs `docker exec` in (~50 ms).
- **Log in once** — a Docker named volume (`ai-agent-vm-auth`) holds credentials and global config. Every project container shares it automatically.
- **tmux-friendly** — each `ai-agent-vm` call spawns a fresh agent process, so different panes in the same project get independent sessions sharing one container.

## Prerequisites

- macOS (Apple Silicon recommended; amd64 works too)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) or [Colima](https://github.com/abiosoft/colima) running

## Install

```bash
git clone https://github.com/lambertse/isolated-claude.git
cd isolated-claude
chmod +x install.sh
./install.sh
```

`install.sh` copies the three files (`ai-agent-vm`, `Dockerfile`, `entrypoint.sh`) to `~/.local/share/ai-agent-vm/`, symlinks the launcher to `~/.local/bin/ai-agent-vm`, and builds the Docker image.

Make sure `~/.local/bin` is on your `PATH`:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### First-time login

```bash
ai-agent-vm login
```

This opens a browser for the Anthropic OAuth flow. Your token is saved to the `ai-agent-vm-auth` Docker volume — you never need to log in again, even across projects.

## Usage

```bash
cd ~/code/my-project
ai-agent-vm                  # start (or reuse) the container, launch the agent CLI
ai-agent-vm --resume         # resume the last agent session in this project
ai-agent-vm shell            # open a bash shell inside the container
ai-agent-vm ps               # list all project containers
ai-agent-vm stop             # stop this project's container
ai-agent-vm rm               # remove this project's container
ai-agent-vm rebuild          # rebuild the Docker image (no cache)
```

All unrecognised arguments are forwarded directly to the agent binary, so any flag it accepts works with `ai-agent-vm` too.

### tmux integration

Replace your existing agent keybind with `ai-agent-vm` in `~/.tmux.conf`:

```tmux
bind -r y run-shell '\
  SESSION="agent-$(echo #{pane_current_path} | md5sum | cut -c1-8)"; \
  tmux has-session -t "$SESSION" 2>/dev/null || \
  tmux new-session -d -s "$SESSION" -c "#{pane_current_path}" "ai-agent-vm"; \
  tmux display-popup -w80% -h80% -E -S "bg=#141210" "tmux attach-session -t $SESSION"'
```

Multiple panes in the same project directory share one container but each get their own agent process.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `AI_AGENT_VM_IMAGE` | `ai-agent-vm:latest` | Docker image to use |
| `AI_AGENT_VM_AUTH_VOLUME` | `ai-agent-vm-auth` | Named volume for shared auth/config |
| `AI_AGENT_VM_OAUTH_PORT` | `54545` | OAuth callback port (override if Anthropic changes it) |

## Performance

- **Image build**: one-time, ~30 s.
- **First `ai-agent-vm` in a new directory**: ~1 s (container create + start).
- **Every subsequent call**: ~50 ms (`docker exec`).
- **Idle memory**: a single `sleep infinity` process — a few MB per container.

## How auth sharing works

The agent CLI stores state in two places (paths hardcoded by the CLI itself, not something this project chooses):

1. `~/.claude/` — credentials, settings, plugins, etc.
2. `~/.claude.json` — account/onboarding state (a file at `$HOME`, not inside `.claude/`)

The `ai-agent-vm-auth` volume is mounted at `/home/node/.claude` in every container. `entrypoint.sh` symlinks `~/.claude.json` into that volume so account state persists alongside credentials. Credentials and global config are therefore shared across all projects.

**Isolated per container** (container-local, not in the shared volume): `projects/`, `sessions/`, `history.jsonl`, and other ephemeral state. Removing a project container with `ai-agent-vm rm` only deletes that project's history — credentials and global config are untouched.

## Troubleshooting

**"Claude configuration file not found" / onboarding screen appears**

You're running an old image without `entrypoint.sh`. Rebuild and remove stale containers:

```bash
ai-agent-vm rebuild
docker ps -aq --filter label=ai-agent-vm=1 | xargs docker rm -f
```

**Still prompted to log in after a fresh install**

A stale OAuth env var on the host shell silently overrides the credentials file:

```bash
env | grep -iE 'CLAUDE_CODE_OAUTH_TOKEN|ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN'
```

Unset any matches in your shell rc.

> **macOS note:** The host agent CLI stores its OAuth token in the Keychain, not in `~/.claude/.credentials.json`. Seeding the volume from host `~/.claude` does **not** copy the token — run `ai-agent-vm login` once instead.

**Inspect the auth volume**

```bash
docker run --rm --user 0:0 -v ai-agent-vm-auth:/data alpine ls -la /data
```

**Reset auth entirely**

```bash
docker volume rm ai-agent-vm-auth
ai-agent-vm login
```

**Nuke everything**

```bash
docker ps -aq --filter label=ai-agent-vm=1 | xargs -r docker rm -f
docker volume rm ai-agent-vm-auth
docker rmi ai-agent-vm:latest
```

## Notes

- No git inside the container by design. Run git on the host — the working directory is mounted read/write at `/workspace`.
- `ai-agent-vm login` forwards port 54545 from `127.0.0.1` to the container for the OAuth redirect. Override the port with `AI_AGENT_VM_OAUTH_PORT` if needed.
