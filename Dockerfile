# AI Agent VM image — arm64/amd64, Node LTS + the AI Agent CLI package, plus a
# C/C++ and basic Python dev toolchain.
FROM node:22-slim

# Minimal runtime deps. ca-certificates for HTTPS, tini for proper signal handling,
# curl for healthchecks / manual debugging.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      tini \
      curl \
    && rm -rf /var/lib/apt/lists/*

# Dev toolchain (Debian bookworm versions: GCC 12, CMake 3.25, GoogleTest 1.12,
# Google Benchmark 1.7, Python 3.11). Kept as its own layer, before the CLI install,
# so bumping the CLI doesn't reinstall the toolchain.
#   - C/C++:  build-essential (gcc/g++/make), gdb, valgrind, ninja, pkg-config, ccache
#   - Tests:  GoogleTest + GoogleMock, Google Benchmark (CMake: find_package(GTest),
#             find_package(benchmark))
#   - VCS:    git (+ less as its pager). --no-install-recommends skips openssh-client:
#             no SSH keys live in the container anyway, so push/pull from the host.
#   - Python: python3 (+ `python` alias), pip, venv, pytest
# safe.directory: the host dir mounted at /workspace is often owned by a different
# uid (e.g. 501 on macOS) than `node` (1000); without it git refuses the repo as
# "dubious ownership". '*' also covers submodules / nested repos. Fine in a
# single-user, disposable container.
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      gdb \
      valgrind \
      cmake \
      ninja-build \
      pkg-config \
      ccache \
      libgtest-dev \
      libgmock-dev \
      libbenchmark-dev \
      git \
      less \
      python3 \
      python-is-python3 \
      python3-pip \
      python3-venv \
      python3-pytest \
    && rm -rf /var/lib/apt/lists/* \
    && git config --system --add safe.directory '*'

# Install the AI Agent CLI globally. Package name is fixed upstream (published to npm)
# and cannot be renamed here.
RUN npm install -g @anthropic-ai/claude-code && npm cache clean --force

# Entrypoint that wires up ~/.claude.json from inside the auth volume.
# The AI Agent CLI stores account state in ~/.claude.json (a file, not the .claude/ dir) —
# a path hardcoded by the CLI itself, not something we choose.
# We keep the real file inside the volume at ~/.claude/_home_agent.json and symlink
# ~/.claude.json -> that path, so it persists across containers just like .credentials.json.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Run as the non-root `node` user that the base image already provides (uid 1000).
# Its HOME is /home/node. The AI Agent CLI stores credentials under ~/.claude.
USER node
WORKDIR /workspace

# The auth volume will be mounted at /home/node/.claude by the launcher.
# We don't VOLUME-declare it here so the launcher controls lifecycle.

# Debian marks the system Python as externally managed (PEP 668), so a bare
# `pip install` errors out. The container is disposable, so allow it: as `node`,
# pip falls back to a --user install in ~/.local (container-local), whose bin/
# goes on PATH. A venv (`python -m venv .venv`) still works and is preferred per project.
ENV TERM=xterm-256color \
    CLAUDE_CODE_DISABLE_TELEMETRY=1 \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    PATH=/home/node/.local/bin:$PATH

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
# Default command keeps container alive so the launcher can `docker exec` into it.
CMD ["sleep", "infinity"]

