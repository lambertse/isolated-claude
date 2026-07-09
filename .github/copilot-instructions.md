# isolated-claude (ai-agent-vm)

Launcher (`ai-agent-vm`, a bash script) that runs an AI coding agent CLI inside a
per-project Docker container on macOS, keeping host secrets/dotfiles out of the
container while sharing login credentials across projects via a named Docker volume.

## Repository layout

- `ai-agent-vm` — the launcher script itself (installed to `~/.local/bin/ai-agent-vm`).
  All subcommands (`run` (default), `login`, `shell`, `stop`, `rm`, `ps`, `rebuild`,
  `help`) are implemented as `cmd_<name>` bash functions dispatched from `main()`.
- `Dockerfile` — builds the `ai-agent-vm:latest` image (Node LTS + the agent CLI
  npm package, no git by design, runs as non-root `node` user).
- `entrypoint.sh` — runs once per container via `tini` on `docker run` (NOT on
  `docker exec`, since exec skips ENTRYPOINT) to wire up persisted config/history.
- `install.sh` — copies the three files above into `~/.local/share/ai-agent-vm/`,
  symlinks `ai-agent-vm` onto `PATH`, and builds the image. There is no build system,
  package manager, or test suite in this repo — everything is plain shell.
- `uninstall.sh` — reverses `install.sh` and also removes all Docker state for this
  tool (containers labelled `ai-agent-vm=1`, the image, the auth/config volumes).
  Keep it in sync with anything `install.sh` or `ai-agent-vm` creates (new volumes,
  env-var-configurable names, etc.) so a full uninstall/reinstall cycle stays clean.

## No build/test/lint tooling

There are no automated tests, linters, or CI configs. When validating changes to
`ai-agent-vm`, `entrypoint.sh`, `install.sh`, or `uninstall.sh`, exercise them manually, e.g.:

```bash
bash -n ai-agent-vm entrypoint.sh install.sh uninstall.sh   # syntax check
shellcheck ai-agent-vm entrypoint.sh install.sh uninstall.sh  # if shellcheck is available
docker build -t ai-agent-vm:latest .              # verify Dockerfile still builds
```

## Key architecture: two-volume persistence model

Understanding this requires reading `ai-agent-vm`, `Dockerfile`, and `entrypoint.sh`
together — the split is not obvious from any single file:

1. **`ai-agent-vm-auth`** (Docker named volume, mounted at `/home/node/.claude` in
   every container) — holds credentials (`.credentials.json`), settings, plugins.
   Shared across ALL project containers so you log in once (`ai-agent-vm login`).
   **Important:** `~/.claude` and `~/.claude.json` are paths hardcoded by the
   upstream agent CLI package itself — not something this project chooses. Do not
   rename these specific paths (or the npm package name / CLI binary name `claude`)
   even though the rest of the project uses "ai-agent" naming; doing so would break
   the actual tool, which always reads/writes those literal paths.
2. **Per-container local state** — `entrypoint.sh` redirects `projects/`, `sessions/`,
   `session-env/`, `shell-snapshots/`, `plans/`, `tasks/`, `file-history/`, `todos/`,
   `debug/`, `paste-cache/`, and `history.jsonl` out of the shared volume into
   `~/.ai-agent-local/` (container-local filesystem) via symlinks, so one project's
   history/session state never leaks into another's. This isolation logic runs on
   every container start and must tolerate re-running idempotently (handles
   migrating pre-existing real files/dirs into the local copy on first upgrade).
3. **`~/.claude.json`** (account/onboarding state) is a *file* at `$HOME`, not inside
   `.claude/`, so it needs separate handling: `entrypoint.sh` persists it as
   `~/.claude/_home_agent.json` inside the auth volume (a filename we invented; safe
   to rename) and symlinks `~/.claude.json` to that path. (`ai-agent-vm`'s
   `ensure_config_volume`/`link_config_cmd` functions reference an older/alternate
   `ai-agent-vm-config` volume approach and are currently dead code — not called
   from `main()` — check both when touching config persistence, they must stay
   consistent with what `entrypoint.sh` actually does.)

## Container naming and lifecycle

- One container per project directory: name is `ai-agent-vm-<12-char-sha256-of-cwd>`
  (`project_container_name()`), so containers are found deterministically from any
  shell in that directory.
- `cmd_run` (default when no recognized subcommand is given) starts/reuses the
  container then does `docker exec -it <name> "$AGENT_BIN" "$@"` — every invocation
  spawns a fresh agent process, which is what makes tmux-pane-per-session usage
  work while sharing one container per project. `AGENT_BIN` (default `claude`) is
  the one place the real CLI binary name is defined; use it instead of hardcoding
  `claude` elsewhere in the script.
- Any unrecognized first argument is forwarded to the agent binary itself (see
  `main()`'s `case` statement) — don't add new subcommands without checking this
  doesn't collide with real CLI flags.
- Only the current working directory is bind-mounted (`-v "$(pwd -P):/workspace"`);
  no other host paths are exposed, and git is intentionally not installed in the
  image (run git on the host).

## Conventions

- Scripts use `set -euo pipefail` (`ai-agent-vm`) / `set -e` (`entrypoint.sh`) —
  preserve this; avoid patterns that swallow errors unintentionally.
- User-configurable behavior goes through env vars with `AI_AGENT_VM_*` defaults
  documented in both `README.md`'s Configuration table and `cmd_help()` in
  `ai-agent-vm` — keep these two in sync when adding new env vars.
- `die()` is the standard way to abort with an error message to stderr in
  `ai-agent-vm`; use it instead of ad-hoc `echo >&2; exit 1`.
- Project-specific naming uses "ai-agent" (script name, image, volumes, container
  labels, env vars, our own invented directories/files). Exception: paths and
  identifiers that are fixed by the upstream CLI package (`~/.claude`,
  `~/.claude.json`, the `claude` binary name, the `@anthropic-ai/claude-code` npm
  package, and env vars the CLI itself reads like `CLAUDE_CODE_DISABLE_TELEMETRY`
  / `CLAUDE_CODE_OAUTH_TOKEN`) must stay as-is — renaming them breaks functionality
  since the real tool doesn't know about "ai-agent" paths.
